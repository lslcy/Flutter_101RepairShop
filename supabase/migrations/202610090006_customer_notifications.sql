-- Customer inbox, separate from Laravel's polymorphic staff notifications.
-- Apply after the customer payment submission migration. No history is backfilled.
begin;

create table if not exists public.customer_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id text not null,
  title text not null,
  message text,
  type text not null check (type in ('info', 'appointment', 'repair', 'payment')),
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  appointment_id bigint references public.appointments(id) on delete cascade,
  report_id bigint references public.service_reports(id) on delete cascade,
  transaction_id bigint references public.transactions(id) on delete cascade,
  event_key text not null,
  constraint customer_notification_one_target check (
    num_nonnulls(appointment_id, report_id, transaction_id) <= 1
  ),
  constraint customer_notification_event unique (user_id, event_key)
);
create index if not exists customer_notifications_inbox
  on public.customer_notifications(user_id, created_at desc, id desc);
alter table public.customer_notifications enable row level security;

-- Column grants prevent altering the recipient, body, timestamps or links.
revoke all on public.customer_notifications from public, anon, authenticated;
revoke all on sequence public.customer_notifications_id_seq from public, anon, authenticated;
grant select on public.customer_notifications to authenticated;
grant update (is_read) on public.customer_notifications to authenticated;

drop policy if exists customer_notification_read on public.customer_notifications;
create policy customer_notification_read on public.customer_notifications
  for select to authenticated using (
    user_id = auth.uid() and exists (
      select 1 from public.customers c
      where c.id::text = customer_notifications.customer_id
        and c.auth_id = auth.uid() and c.deleted_at is null
        and (appointment_id is null or exists (
          select 1 from public.appointments a
          where a.id = appointment_id and a.customer_id = c.id
            and to_jsonb(a)->>'deleted_at' is null
        ))
        and (report_id is null or exists (
          select 1 from public.service_reports r
          where r.id = report_id and r.customer_id = c.id and r.deleted_at is null
        ))
        and (transaction_id is null or exists (
          select 1 from public.transactions t
          where t.id = transaction_id and t.customer_id = c.id and t.deleted_at is null
        ))
    )
  );
drop policy if exists customer_notification_mark_read on public.customer_notifications;
create policy customer_notification_mark_read on public.customer_notifications
  for update to authenticated using (
    user_id = auth.uid() and exists (
      select 1 from public.customers c
      where c.id::text = customer_notifications.customer_id
        and c.auth_id = auth.uid() and c.deleted_at is null
    )
  ) with check (
    user_id = auth.uid() and exists (
      select 1 from public.customers c
      where c.id::text = customer_notifications.customer_id
        and c.auth_id = auth.uid() and c.deleted_at is null
    )
  );

create schema if not exists repairshop_private;
revoke all on schema repairshop_private from public, anon, authenticated;

-- Only trusted source-table triggers call this function. Recipients come from
-- the customer's linked Supabase identity, never a name, email or phone match.
create or replace function repairshop_private.add_customer_notification(
  p_customer_id text, p_event_key text, p_title text, p_message text,
  p_type text, p_appointment_id bigint default null,
  p_report_id bigint default null, p_transaction_id bigint default null,
  p_expected_auth uuid default null
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_auth uuid;
begin
  select c.auth_id into v_auth from public.customers c
    join auth.users u on u.id = c.auth_id
    where c.id::text = p_customer_id and c.deleted_at is null
      and (p_expected_auth is null or c.auth_id = p_expected_auth);
  if v_auth is null then return; end if;

  insert into public.customer_notifications
    (user_id, customer_id, title, message, type, appointment_id,
     report_id, transaction_id, event_key)
    values (v_auth, p_customer_id, p_title, p_message, p_type,
      p_appointment_id, p_report_id, p_transaction_id, p_event_key)
    on conflict (user_id, event_key) do update set
      title = excluded.title, message = excluded.message,
      is_read = false, created_at = pg_catalog.now();
end;
$$;
revoke all on function repairshop_private.add_customer_notification(
  text, text, text, text, text, bigint, bigint, bigint, uuid
) from public, anon, authenticated;

create or replace function repairshop_private.notify_customer_source_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_new jsonb := pg_catalog.to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then pg_catalog.to_jsonb(old) else '{}'::jsonb end;
  v_status text;
  v_old_status text;
  v_title text;
  v_message text;
  v_customer_id text := v_new->>'customer_id';
  v_id bigint;
  v_event text;
  v_schedule_changed boolean;
begin
  -- Appointments currently have no deleted_at; tolerate it if introduced later.
  if v_new->>'deleted_at' is not null then return new; end if;
  v_status := lower(btrim(coalesce(v_new->>'status', '')));
  v_old_status := lower(btrim(coalesce(v_old->>'status', '')));
  v_event := tg_table_name || ':' || (v_new->>'id') || ':' || pg_catalog.txid_current()::text;

  if tg_table_name = 'appointments' then
    v_schedule_changed := v_new->>'appointment_date' is distinct from v_old->>'appointment_date'
      or v_new->>'time_slot' is distinct from v_old->>'time_slot';
    if v_status = v_old_status and not v_schedule_changed then return new; end if;
    if v_status is distinct from v_old_status then
      v_title := case v_status
        when 'confirmed' then 'Appointment confirmed'
        when 'cancelled' then 'Appointment cancelled'
        when 'completed' then 'Appointment completed'
        else 'Appointment updated' end;
    else
      v_title := 'Appointment rescheduled';
    end if;
    v_message := 'Open your appointment to view its latest status, date and time.';
    perform repairshop_private.add_customer_notification(
      v_customer_id, v_event, v_title, v_message, 'appointment',
      p_appointment_id => (v_new->>'id')::bigint);
  elsif tg_table_name = 'service_reports' then
    if tg_op = 'UPDATE' and v_status = v_old_status then return new; end if;
    v_title := 'Repair updated';
    v_message := case v_status
      when 'pending' then 'Your repair is pending. Open your repair for details.'
      when 'in progress' then 'Your repair is in progress. Open your repair for details.'
      when 'completed' then 'Your repair is completed. Open your repair for details.'
      when 'cancelled' then 'Your repair is cancelled. Open your repair for details.'
      else 'Your repair status has changed. Open your repair for the latest update.' end;
    perform repairshop_private.add_customer_notification(
      v_customer_id, v_event, v_title, v_message, 'repair',
      p_report_id => (v_new->>'id')::bigint);
  elsif tg_table_name = 'transactions' then
    v_status := lower(btrim(coalesce(v_new->>'payment_status', '')));
    v_old_status := lower(btrim(coalesce(v_old->>'payment_status', '')));
    if v_status <> 'paid' or v_status = v_old_status then return new; end if;
    perform repairshop_private.add_customer_notification(
      v_customer_id, v_event, 'Payment confirmed',
      'The shop has confirmed your payment. View your payment history for details.',
      'payment', p_transaction_id => (v_new->>'id')::bigint);
  elsif tg_table_name = 'customer_payment_submissions' then
    if tg_op = 'UPDATE' and v_status = v_old_status then return new; end if;
    -- Approved receipts already produce one Payment confirmed entry through
    -- the authoritative transaction's Paid change in review_customer_payment.
    if v_status not in ('pending', 'rejected') then return new; end if;
    v_id := (v_new->>'transaction_id')::bigint;
    select t.customer_id::text into v_customer_id from public.transactions t
      where t.id = v_id and t.deleted_at is null
        and t.customer_id::text = v_new->>'customer_id';
    if v_customer_id is null then return new; end if;
    v_title := case v_status when 'pending' then 'Payment submitted'
      else 'Payment receipt needs attention' end;
    v_message := case v_status when 'pending'
      then 'Your GCash receipt is awaiting shop review.'
      else 'The shop could not approve your receipt. Open your payments to view the reason and submit a corrected receipt.' end;
    perform repairshop_private.add_customer_notification(
      v_customer_id, v_event, v_title, v_message, 'payment',
      p_transaction_id => v_id, p_expected_auth => (v_new->>'auth_id')::uuid);
  end if;
  return new;
end;
$$;
revoke all on function repairshop_private.notify_customer_source_change()
  from public, anon, authenticated;

drop trigger if exists customer_appointment_update on public.appointments;
create trigger customer_appointment_update
  after update of status, appointment_date, time_slot on public.appointments
  for each row execute function repairshop_private.notify_customer_source_change();
drop trigger if exists customer_repair_update on public.service_reports;
create trigger customer_repair_update
  after insert or update of status on public.service_reports
  for each row execute function repairshop_private.notify_customer_source_change();
drop trigger if exists customer_transaction_paid on public.transactions;
create trigger customer_transaction_paid
  after insert or update of payment_status on public.transactions
  for each row execute function repairshop_private.notify_customer_source_change();
drop trigger if exists customer_payment_review_update on public.customer_payment_submissions;
create trigger customer_payment_review_update
  after insert or update of status on public.customer_payment_submissions
  for each row execute function repairshop_private.notify_customer_source_change();

-- Realtime follows the table's ownership RLS; publication alone grants no reads.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'customer_notifications'
    ) then
    alter publication supabase_realtime add table public.customer_notifications;
  end if;
end;
$$;

commit;
