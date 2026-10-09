-- Customers submit payment evidence; only a trusted administrator records paid.
-- Apply after reviewing the existing transactions/customer schema. Existing
-- financial status and balances stay authoritative during receipt review.
begin;

create table if not exists public.customer_payment_settings (
  id integer primary key check (id = 1),
  gcash_qr_image_url text not null check (gcash_qr_image_url ~ '^https://[^[:space:]]+$'),
  gcash_recipient_name text not null default 'L. C. O.' check (length(btrim(gcash_recipient_name)) between 1 and 150)
);
alter table public.customer_payment_settings enable row level security;
revoke all on public.customer_payment_settings from anon, authenticated;
grant select on public.customer_payment_settings to authenticated;
drop policy if exists customer_payment_settings_read on public.customer_payment_settings;
create policy customer_payment_settings_read on public.customer_payment_settings
  for select to authenticated using (auth.uid() is not null);

create table if not exists public.customer_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  transaction_id bigint not null references public.transactions(id),
  auth_id uuid not null references auth.users(id),
  customer_id text not null,
  method text not null check (method in ('gcash', 'shop')),
  status text not null check (status in ('pending', 'pay_at_shop', 'approved', 'rejected', 'superseded')),
  amount numeric(12,2) not null check (amount > 0),
  receipt_path text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  review_note text,
  constraint payment_receipt_required check (
    (method = 'gcash' and receipt_path is not null and status <> 'pay_at_shop') or
    (method = 'shop' and receipt_path is null and status in ('pay_at_shop', 'superseded'))
  )
);
create index if not exists customer_payment_submissions_history
  on public.customer_payment_submissions(transaction_id, created_at desc);
create unique index if not exists customer_payment_one_open_submission
  on public.customer_payment_submissions(transaction_id)
  where status in ('pending', 'pay_at_shop');
alter table public.customer_payment_submissions enable row level security;
revoke all on public.customer_payment_submissions from anon, authenticated;
grant select on public.customer_payment_submissions to authenticated;
drop policy if exists customer_payment_submission_read on public.customer_payment_submissions;
create policy customer_payment_submission_read on public.customer_payment_submissions
  for select to authenticated using (
    auth_id = auth.uid() and exists (
      select 1 from public.customers c where c.id::text = customer_id
        and c.auth_id = auth.uid() and c.deleted_at is null
    )
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('payment-receipts', 'payment-receipts', false, 5242880,
          array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The merchant QR is public; receipts always use the separate private bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('shop-payment-qr', 'shop-payment-qr', true, 5242880,
          array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists shop_payment_qr_insert_guard on storage.objects;
create policy shop_payment_qr_insert_guard on storage.objects as restrictive
  for insert to public with check (bucket_id <> 'shop-payment-qr');
drop policy if exists shop_payment_qr_update_guard on storage.objects;
create policy shop_payment_qr_update_guard on storage.objects as restrictive
  for update to public using (bucket_id <> 'shop-payment-qr')
  with check (bucket_id <> 'shop-payment-qr');
drop policy if exists shop_payment_qr_delete_guard on storage.objects;
create policy shop_payment_qr_delete_guard on storage.objects as restrictive
  for delete to public using (bucket_id <> 'shop-payment-qr');
drop policy if exists customer_receipt_upload on storage.objects;
create policy customer_receipt_upload on storage.objects
  for insert to authenticated with check (
    bucket_id = 'payment-receipts' and auth.uid() is not null
    and split_part(name, '/', 1) = auth.uid()::text
    and name ~ '^[0-9a-f-]{36}/[0-9]+/[0-9a-f-]{36}\.(jpg|png|webp)$'
    and exists (
      select 1 from public.transactions t join public.customers c
        on c.id = t.customer_id where t.id::text = split_part(name, '/', 2)
        and c.auth_id = auth.uid() and c.deleted_at is null
        and t.deleted_at is null and lower(btrim(coalesce(t.payment_status, ''))) <> 'paid'
    )
  );
drop policy if exists customer_receipt_read on storage.objects;
create policy customer_receipt_read on storage.objects
  for select to authenticated using (
    bucket_id = 'payment-receipts' and split_part(name, '/', 1) = auth.uid()::text
  );
-- Restrictive guards keep receipts private and immutable even if an older,
-- unrelated bucket policy grants authenticated users broad Storage access.
drop policy if exists customer_receipt_read_guard on storage.objects;
create policy customer_receipt_read_guard on storage.objects as restrictive
  for select to public using (
    bucket_id <> 'payment-receipts' or split_part(name, '/', 1) = auth.uid()::text
  );
drop policy if exists customer_receipt_update_guard on storage.objects;
create policy customer_receipt_update_guard on storage.objects as restrictive
  for update to public using (bucket_id <> 'payment-receipts')
  with check (bucket_id <> 'payment-receipts');
drop policy if exists customer_receipt_delete_guard on storage.objects;
create policy customer_receipt_delete_guard on storage.objects as restrictive
  for delete to public using (bucket_id <> 'payment-receipts');
-- Evaluate ownership with a fixed definer context so unrelated anonymous
-- uploads do not require permission to query the private billing tables.
-- The predicate reveals only whether this caller owns the specified unpaid bill.
create or replace function public.customer_can_upload_receipt(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and split_part(p_name, '/', 1) = auth.uid()::text
    and p_name ~ '^[0-9a-f-]{36}/[0-9]+/[0-9a-f-]{36}\.(jpg|png|webp)$'
    and exists (
      select 1 from public.transactions t join public.customers c
        on c.id = t.customer_id where t.id::text = split_part(p_name, '/', 2)
        and c.auth_id = auth.uid() and c.deleted_at is null
        and t.deleted_at is null and lower(btrim(coalesce(t.payment_status, ''))) <> 'paid'
    );
$$;
revoke all on function public.customer_can_upload_receipt(text) from public;
grant execute on function public.customer_can_upload_receipt(text) to anon, authenticated;

drop policy if exists customer_receipt_upload_guard on storage.objects;
create policy customer_receipt_upload_guard on storage.objects as restrictive
  for insert to public with check (
    bucket_id <> 'payment-receipts' or public.customer_can_upload_receipt(name)
  );
-- No customer UPDATE or DELETE: receipts stay immutable even after account archival.
-- Trusted staff may clean up unused drafts according to the shop retention policy.

create or replace function public.submit_customer_payment(
  p_transaction_id bigint, p_method text, p_receipt_path text default null,
  p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_auth uuid := auth.uid();
  v_transaction public.transactions%rowtype;
  v_submission public.customer_payment_submissions%rowtype;
  v_balance numeric;
  v_id uuid := coalesce(p_request_id, pg_catalog.gen_random_uuid());
begin
  if v_auth is null then raise exception 'Sign in again before submitting a payment.'; end if;
  if p_method is null or p_method not in ('gcash', 'shop') then
    raise exception 'Choose GCash or Pay at the shop.';
  end if;
  select t.* into v_transaction from public.transactions t
    join public.customers c on c.id = t.customer_id
    where t.id = p_transaction_id and t.deleted_at is null
      and c.auth_id = v_auth and c.deleted_at is null for update of t;
  if not found then raise exception 'This payment is not available for your account.'; end if;

  select * into v_submission from public.customer_payment_submissions where id = v_id;
  if found then
    if v_submission.auth_id <> v_auth or v_submission.transaction_id <> p_transaction_id
       or v_submission.method <> p_method
       or v_submission.receipt_path is distinct from p_receipt_path then
      raise exception 'This payment request could not be confirmed.';
    end if;
    return pg_catalog.to_jsonb(v_submission);
  end if;
  if lower(btrim(coalesce(v_transaction.payment_status, ''))) = 'paid' then
    raise exception 'This transaction has already been paid.';
  end if;
  v_balance := v_transaction.total_amount - case
    when lower(btrim(coalesce(v_transaction.payment_status, ''))) in
      ('partial', 'partially paid', 'partial payment')
    then coalesce(v_transaction.partial_payment_amount, 0) else 0 end;
  if v_balance is null or v_balance <= 0 then
    raise exception 'The shop must set a balance before you can submit a payment.';
  end if;

  select * into v_submission from public.customer_payment_submissions
    where transaction_id = p_transaction_id and status in ('pending', 'pay_at_shop');
  if found and v_submission.status = 'pending' then
    raise exception 'A receipt is already pending review. Refresh payment details.';
  end if;
  if found and p_method = 'shop' then return pg_catalog.to_jsonb(v_submission); end if;

  if p_method = 'gcash' then
    if not exists (select 1 from public.customer_payment_settings where id = 1) then
      raise exception 'GCash is not available yet. You can choose Pay at the shop.';
    end if;
    if p_receipt_path is null or
       p_receipt_path !~ ('^' || v_auth::text || '/' || p_transaction_id::text || '/' || v_id::text || '\.(jpg|png|webp)$') or
       not exists (select 1 from storage.objects where bucket_id = 'payment-receipts' and name = p_receipt_path) then
      raise exception 'Upload your receipt before confirming payment.';
    end if;
  elsif p_receipt_path is not null then
    raise exception 'Pay at the shop does not need a receipt.';
  end if;
  update public.customer_payment_submissions set status = 'superseded'
    where transaction_id = p_transaction_id and status = 'pay_at_shop';
  insert into public.customer_payment_submissions
    (id, transaction_id, auth_id, customer_id, method, status, amount, receipt_path)
    values (v_id, p_transaction_id, v_auth, v_transaction.customer_id::text,
      p_method, case when p_method = 'gcash' then 'pending' else 'pay_at_shop' end,
      v_balance, p_receipt_path) returning * into v_submission;
  return pg_catalog.to_jsonb(v_submission);
end;
$$;
revoke all on function public.submit_customer_payment(bigint, text, text, uuid) from public, anon;
grant execute on function public.submit_customer_payment(bigint, text, text, uuid) to authenticated;

-- Call from a trusted Laravel admin endpoint after its existing admin auth check.
-- Never put the Supabase service role key in Flutter or in browser JavaScript.
create or replace function public.review_customer_payment(
  p_submission_id uuid, p_decision text, p_admin_identity text,
  p_note text default null, p_reference_no text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_submission public.customer_payment_submissions%rowtype;
  v_transaction public.transactions%rowtype;
  v_transaction_id bigint;
  v_balance numeric;
begin
  if nullif(btrim(p_admin_identity), '') is null then raise exception 'An administrator identity is required.'; end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'Choose approved or rejected.';
  end if;
  select transaction_id into v_transaction_id from public.customer_payment_submissions where id = p_submission_id;
  if not found then raise exception 'Payment submission not found.'; end if;
  -- Same lock order as submission avoids racing balance changes or other reviews.
  select * into v_transaction from public.transactions where id = v_transaction_id for update;
  select * into v_submission from public.customer_payment_submissions where id = p_submission_id for update;
  if v_submission.status <> 'pending' or v_submission.method <> 'gcash' then
    raise exception 'Only a pending GCash receipt can be reviewed.';
  end if;
  if p_decision = 'approved' then
    if v_transaction.deleted_at is not null or lower(btrim(coalesce(v_transaction.payment_status, ''))) = 'paid' then
      raise exception 'This transaction is archived or already paid.';
    end if;
    v_balance := v_transaction.total_amount - case
      when lower(btrim(coalesce(v_transaction.payment_status, ''))) in
        ('partial', 'partially paid', 'partial payment')
      then coalesce(v_transaction.partial_payment_amount, 0) else 0 end;
    if v_balance is null or v_balance <= 0 or v_balance <> v_submission.amount then
      raise exception 'The balance changed. Review and reject this receipt before requesting a new one.';
    end if;
    update public.transactions set payment_status = 'Paid', payment_method = 'GCash',
      paid_at = pg_catalog.now(), payment_date = (pg_catalog.now() at time zone 'Asia/Manila')::date,
      partial_payment_amount = null, reference_no = coalesce(nullif(btrim(p_reference_no), ''), reference_no),
      updated_at = pg_catalog.now() where id = v_transaction_id;
  elsif nullif(btrim(p_note), '') is null then
    raise exception 'Add a reason so the customer can correct the receipt.';
  end if;
  update public.customer_payment_submissions set status = p_decision,
    reviewed_at = pg_catalog.now(), reviewed_by = btrim(p_admin_identity),
    review_note = nullif(btrim(p_note), '') where id = p_submission_id returning * into v_submission;
  return pg_catalog.to_jsonb(v_submission);
end;
$$;
revoke all on function public.review_customer_payment(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.review_customer_payment(uuid, text, text, text, text) to service_role;
grant select, insert, update on public.customer_payment_settings to service_role;
grant select on public.customer_payment_submissions to service_role;
commit;