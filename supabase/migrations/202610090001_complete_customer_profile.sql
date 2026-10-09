-- Install in the Supabase SQL editor before enabling external sign-in.
-- This does not change existing signup triggers or attach accounts by email/phone.
-- The existing handle_new_user trigger must accept phone users (email may be null)
-- and Google users (first_name/last_name/address metadata may be absent).
begin;

create or replace function public.complete_customer_profile(
  p_first_name text,
  p_last_name text,
  p_address text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user auth.users%rowtype;
  v_customer public.customers%rowtype;
  v_new_id public.customers.id%type;
  v_verified_phone text;
begin
  if auth.uid() is null then
    raise exception 'Sign in before saving your profile.' using errcode = '42501';
  end if;
  select * into v_user from auth.users where id = auth.uid();
  if not found or
      (v_user.email_confirmed_at is null and v_user.phone_confirmed_at is null) then
    raise exception 'Verify your email or phone before saving your profile.'
      using errcode = '42501';
  end if;
  if nullif(btrim(p_first_name), '') is null or
      nullif(btrim(p_last_name), '') is null or
      nullif(btrim(p_address), '') is null then
    raise exception 'Your name and address are required.' using errcode = '22023';
  end if;

  if v_user.phone_confirmed_at is not null and nullif(v_user.phone, '') is not null then
    v_verified_phone := '+' || pg_catalog.ltrim(v_user.phone, '+');
  end if;

  -- Serialize concurrent first-time requests for this verified auth identity.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user.id::text, 0));
  select * into v_customer from public.customers
    where auth_id = v_user.id and deleted_at is null
    order by created_at asc limit 1 for update;
  if found then
    update public.customers
      set first_name = btrim(p_first_name), last_name = btrim(p_last_name),
          address = btrim(p_address),
          phone_no = coalesce(v_verified_phone, phone_no),
          updated_at = pg_catalog.now()
      where id = v_customer.id and auth_id = v_user.id and deleted_at is null;
  else
    -- A phone-only customer has no email. The customers.email column must
    -- allow NULL; do not generate a fake email or merge a different account.
    -- Decode UUID into the existing ID column type (UUID or text).
    select id into v_new_id from pg_catalog.jsonb_populate_record(
      null::public.customers,
      pg_catalog.jsonb_build_object('id', pg_catalog.gen_random_uuid()::text));
    insert into public.customers
      (id, auth_id, first_name, last_name, email, phone_no, address,
       created_at, updated_at)
    values
      (v_new_id, v_user.id, btrim(p_first_name), btrim(p_last_name),
       nullif(v_user.email, ''), v_verified_phone, btrim(p_address),
       pg_catalog.now(), pg_catalog.now());
  end if;
end;
$$;

-- Only this validated operation bypasses the customers INSERT policy.
-- Never grant direct INSERT access or a service-role key to the mobile app.
revoke all on function public.complete_customer_profile(text, text, text)
  from public, anon;
grant execute on function public.complete_customer_profile(text, text, text)
  to authenticated;

commit;