-- Review audits/customer_account_uniqueness.sql first. Apply with administrator
-- access; existing duplicates abort the whole transaction, without data cleanup.
-- Requires 202610090001_complete_customer_profile.sql and an external-auth-safe
-- handle_new_user trigger. Customer IDs may be UUID or text; auth_id must be UUID.
begin;

create schema if not exists repairshop_private;
revoke all on schema repairshop_private from public, anon, authenticated;

-- Dart String.trim() whitespace, including Unicode spaces, NEL and BOM.
create or replace function repairshop_private.customer_trim_contact(p_value text)
returns text language sql immutable parallel safe set search_path = ''
as $$ select pg_catalog.btrim(p_value,
  U&'\0009\000a\000b\000c\000d\0020\0085\00a0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200a\2028\2029\202f\205f\3000\feff') $$;

create or replace function repairshop_private.customer_email_key(p_value text)
returns text language sql immutable parallel safe set search_path = ''
as $$ select nullif(pg_catalog.lower(repairshop_private.customer_trim_contact(p_value)), '') $$;

-- Match the Flutter PhoneNumber policy; no guessing other countries' prefixes.
create or replace function repairshop_private.customer_phone_key(p_value text)
returns text language plpgsql immutable parallel safe set search_path = ''
as $$
declare v_value text := repairshop_private.customer_trim_contact(p_value);
begin
  -- Dart RegExp \s also accepts these non-ASCII separators inside a phone.
  v_value := pg_catalog.regexp_replace(v_value,
    U&'[\00a0\1680\2000-\200a\2028\2029\202f\205f\3000\feff]', ' ', 'g');
  if v_value is null or v_value = '' or
     v_value !~ '^[+0-9[:space:]().-]+$' then return null; end if;
  v_value := pg_catalog.regexp_replace(v_value, '[[:space:]().-]', '', 'g');
  if pg_catalog.left(v_value, 2) = '00' then
    v_value := '+' || pg_catalog.substr(v_value, 3);
  end if;
  if v_value ~ '^09[0-9]{9}$' then
    v_value := '+63' || pg_catalog.substr(v_value, 2);
  elsif v_value ~ '^9[0-9]{9}$' then
    v_value := '+63' || v_value;
  elsif v_value ~ '^639[0-9]{9}$' then
    v_value := '+' || v_value;
  end if;
  if v_value !~ '^\+[1-9][0-9]{7,14}$' then return null; end if;
  if pg_catalog.left(v_value, 3) = '+63' and
     v_value !~ '^\+639[0-9]{9}$' then return null; end if;
  return v_value;
end;
$$;

-- Prevent writes racing the initial audit/backfill/index installation.
lock table auth.users, public.customers in share row exclusive mode;

do $$
begin
  if exists (select 1 from public.customers where auth_id is not null
             group by auth_id having count(*) > 1) then
    raise exception 'Duplicate customer auth IDs exist. Run the account audit and resolve them before installing.';
  end if;
  if exists (select 1 from public.customers
             where repairshop_private.customer_email_key(email) is not null
             group by repairshop_private.customer_email_key(email)
             having count(*) > 1) then
    raise exception 'Duplicate customer emails exist. Run the account audit and resolve them before installing.';
  end if;
  if exists (select 1 from public.customers
             where repairshop_private.customer_phone_key(phone_no) is not null
             group by repairshop_private.customer_phone_key(phone_no)
             having count(*) > 1) then
    raise exception 'Duplicate customer phone numbers exist. Run the account audit and resolve them before installing.';
  end if;
  if exists (select 1 from public.customers
             where nullif(repairshop_private.customer_trim_contact(phone_no), '') is not null
               and repairshop_private.customer_phone_key(phone_no) is null) then
    raise exception 'Unsupported customer phone formats exist. Run the account audit and correct them before installing.';
  end if;
  if exists (select 1 from auth.users
             where nullif(repairshop_private.customer_trim_contact(phone), '') is not null
               and repairshop_private.customer_phone_key('+' || pg_catalog.ltrim(phone, '+')) is null) then
    raise exception 'Unsupported auth phone formats exist. Run the account audit and correct them before installing.';
  end if;
end;
$$;

create unique index if not exists customers_one_auth_account_idx
  on public.customers (auth_id) where auth_id is not null;
create unique index if not exists customers_unique_email_key_idx
  on public.customers (repairshop_private.customer_email_key(email))
  where repairshop_private.customer_email_key(email) is not null;
create unique index if not exists customers_unique_phone_key_idx
  on public.customers (repairshop_private.customer_phone_key(phone_no))
  where repairshop_private.customer_phone_key(phone_no) is not null;

-- One shared unique key serializes both tables' writes. SELECT-only checks cannot
-- stop two accounts concurrently claiming the same normalized contact.
create table if not exists repairshop_private.customer_identity_claims (
  kind text not null check (kind in ('email', 'phone')),
  canonical_value text not null,
  owner_key text not null,
  primary key (kind, canonical_value)
);
create table if not exists repairshop_private.customer_identity_sources (
  source_kind text not null check (source_kind in ('auth', 'customer')),
  source_id text not null,
  kind text not null,
  canonical_value text not null,
  primary key (source_kind, source_id, kind, canonical_value),
  foreign key (kind, canonical_value)
    references repairshop_private.customer_identity_claims (kind, canonical_value)
    on delete restrict
);
alter table repairshop_private.customer_identity_claims enable row level security;
alter table repairshop_private.customer_identity_sources enable row level security;
revoke all on all tables in schema repairshop_private from public, anon, authenticated;

create or replace function repairshop_private.replace_customer_identity_sources(
  p_source_kind text, p_source_id text, p_owner_key text,
  p_email text, p_phone text
) returns void language plpgsql security definer set search_path = ''
as $$
declare v_contact record; v_old record; v_accepted text;
begin
  -- Claims are acquired in deterministic order; conflicting owners never merge.
  for v_contact in
    select kind, canonical_value from (values
      ('email'::text, p_email), ('phone'::text, p_phone)
    ) as contacts(kind, canonical_value)
    where canonical_value is not null order by kind, canonical_value
  loop
    insert into repairshop_private.customer_identity_claims as claims
      (kind, canonical_value, owner_key)
    values (v_contact.kind, v_contact.canonical_value, p_owner_key)
    on conflict (kind, canonical_value) do update
      set owner_key = claims.owner_key
      where claims.owner_key = excluded.owner_key
    returning owner_key into v_accepted;
    if not found then
      if v_contact.kind = 'email' then
        raise exception 'This email is already associated with a customer account.'
          using errcode = '23505', constraint = 'customer_email_reserved';
      else
        raise exception 'This phone number is already associated with a customer account.'
          using errcode = '23505', constraint = 'customer_phone_reserved';
      end if;
    end if;
    insert into repairshop_private.customer_identity_sources
      (source_kind, source_id, kind, canonical_value)
    values (p_source_kind, p_source_id, v_contact.kind, v_contact.canonical_value)
    on conflict do nothing;
  end loop;

  for v_old in
    with removed_sources as (
      delete from repairshop_private.customer_identity_sources
      where source_kind = p_source_kind and source_id = p_source_id
        and not ((kind = 'email' and canonical_value = p_email) is true or
                 (kind = 'phone' and canonical_value = p_phone) is true)
      returning kind, canonical_value
    )
    select kind, canonical_value from removed_sources order by kind, canonical_value
  loop
    -- Serialize cleanup when both owning rows drop the same contact. The
    -- following DELETE takes a fresh READ COMMITTED snapshot after any wait,
    -- so the final remover sees the other source's committed deletion.
    perform 1 from repairshop_private.customer_identity_claims as claims
    where claims.kind = v_old.kind and claims.canonical_value = v_old.canonical_value
    for update;
    -- FK protects against concurrent source inserts even if a query snapshot
    -- misses them. Archived customer rows keep their source and reservation.
    delete from repairshop_private.customer_identity_claims as claims
    where claims.kind = v_old.kind and claims.canonical_value = v_old.canonical_value
      and not exists (select 1 from repairshop_private.customer_identity_sources as sources
        where sources.kind = claims.kind and sources.canonical_value = claims.canonical_value);
  end loop;
end;
$$;

-- Seed current identities. Any cross-owner conflict raises a fixed message and
-- rolls back all schema changes; no identifying values appear in the exception.
do $$
declare v_user record; v_customer record;
begin
  for v_user in select id, email, phone from auth.users order by id loop
    perform repairshop_private.replace_customer_identity_sources(
      'auth', v_user.id::text, 'auth:' || v_user.id::text,
      repairshop_private.customer_email_key(v_user.email),
      repairshop_private.customer_phone_key('+' || pg_catalog.ltrim(v_user.phone, '+')));
  end loop;
  for v_customer in select id, auth_id, email, phone_no from public.customers order by id loop
    perform repairshop_private.replace_customer_identity_sources(
      'customer', v_customer.id::text,
      case when v_customer.auth_id is null then 'customer:' || v_customer.id::text
           else 'auth:' || v_customer.auth_id::text end,
      repairshop_private.customer_email_key(v_customer.email),
      repairshop_private.customer_phone_key(v_customer.phone_no));
  end loop;
end;
$$;

create or replace function repairshop_private.enforce_customer_account_identity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_email text; v_phone text;
begin
  if tg_op = 'DELETE' then
    perform repairshop_private.replace_customer_identity_sources(
      'customer', old.id::text, '', null, null);
    return old;
  end if;
  if tg_op = 'UPDATE' and (new.id is distinct from old.id or
                          new.auth_id is distinct from old.auth_id) then
    raise exception 'Customer accounts cannot be reassigned. Contact the shop.'
      using errcode = '42501';
  end if;
  v_email := repairshop_private.customer_email_key(new.email);
  v_phone := repairshop_private.customer_phone_key(new.phone_no);
  if nullif(repairshop_private.customer_trim_contact(new.phone_no), '') is not null and v_phone is null then
    raise exception 'Enter a valid phone number.' using errcode = '22023';
  end if;
  perform repairshop_private.replace_customer_identity_sources(
    'customer', new.id::text,
    case when new.auth_id is null then 'customer:' || new.id::text
         else 'auth:' || new.auth_id::text end, v_email, v_phone);
  new.email := v_email;
  new.phone_no := v_phone;
  return new;
end;
$$;

drop trigger if exists enforce_customer_account_identity on public.customers;
create trigger enforce_customer_account_identity
  before insert or update of id, auth_id, email, phone_no on public.customers
  for each row execute function repairshop_private.enforce_customer_account_identity();
drop trigger if exists release_customer_account_identity on public.customers;
create trigger release_customer_account_identity
  after delete on public.customers
  for each row execute function repairshop_private.enforce_customer_account_identity();

create or replace function repairshop_private.enforce_auth_customer_identity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_contact_phone text; v_phone text; v_email text;
begin
  if tg_op = 'DELETE' then
    perform repairshop_private.replace_customer_identity_sources(
      'auth', old.id::text, '', null, null);
    return old;
  end if;
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception 'Customer accounts cannot be reassigned. Contact the shop.'
      using errcode = '42501';
  end if;
  v_email := repairshop_private.customer_email_key(new.email);
  v_phone := repairshop_private.customer_phone_key('+' || pg_catalog.ltrim(new.phone, '+'));
  if nullif(repairshop_private.customer_trim_contact(new.phone), '') is not null and v_phone is null then
    raise exception 'Enter a valid phone number.' using errcode = '22023';
  end if;
  -- Signup metadata is a proposed contact, not a verified Auth phone. Check
  -- a newly supplied value; unchanged metadata may describe an old contact.
  if tg_op = 'INSERT' or
     (new.raw_user_meta_data ->> 'phone_no') is distinct from
     (old.raw_user_meta_data ->> 'phone_no') then
    v_contact_phone := repairshop_private.customer_phone_key(new.raw_user_meta_data ->> 'phone_no');
    if nullif(repairshop_private.customer_trim_contact(new.raw_user_meta_data ->> 'phone_no'), '') is not null
       and v_contact_phone is null then
      raise exception 'Enter a valid phone number.' using errcode = '22023';
    end if;
    -- The customer insert atomically claims the actual stored contact.
    if exists (select 1 from repairshop_private.customer_identity_claims
      where kind = 'phone' and canonical_value = v_contact_phone
        and owner_key <> 'auth:' || new.id::text) then
      raise exception 'This phone number is already associated with a customer account.'
        using errcode = '23505', constraint = 'customer_phone_reserved';
    end if;
  end if;
  perform repairshop_private.replace_customer_identity_sources(
    'auth', new.id::text, 'auth:' || new.id::text, v_email, v_phone);
  return new;
end;
$$;

drop trigger if exists enforce_auth_customer_identity on auth.users;
create trigger enforce_auth_customer_identity
  before insert or update of id, email, phone, raw_user_meta_data on auth.users
  for each row execute function repairshop_private.enforce_auth_customer_identity();
drop trigger if exists release_auth_customer_identity on auth.users;
create trigger release_auth_customer_identity
  after delete on auth.users
  for each row execute function repairshop_private.enforce_auth_customer_identity();

-- Optional supported Auth hook: configure Authentication > Hooks > Before User
-- Created to this function. Trigger constraints still enforce updates and races.
create or replace function public.check_customer_account_creation(event jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user jsonb := event -> 'user'; v_owner text;
        v_contact record; v_email text; v_phone text; v_contact_phone text;
begin
  v_owner := 'auth:' || (v_user ->> 'id');
  if v_owner is null then
    return pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'http_code', 400, 'message', 'Account details could not be verified.'));
  end if;
  v_email := repairshop_private.customer_email_key(v_user ->> 'email');
  v_phone := repairshop_private.customer_phone_key('+' || pg_catalog.ltrim(v_user ->> 'phone', '+'));
  v_contact_phone := repairshop_private.customer_phone_key(coalesce(
    v_user -> 'user_metadata' ->> 'phone_no',
    v_user -> 'raw_user_meta_data' ->> 'phone_no'));
  for v_contact in
    select kind, canonical_value from (values
      ('email'::text, v_email), ('phone'::text, v_phone), ('phone'::text, v_contact_phone)
    ) as contacts(kind, canonical_value) where canonical_value is not null
  loop
    if exists (select 1 from repairshop_private.customer_identity_claims
      where kind = v_contact.kind and canonical_value = v_contact.canonical_value
        and owner_key <> v_owner) then
      return pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'http_code', 400, 'message', case when v_contact.kind = 'email'
          then 'This email is already associated with a customer account.'
          else 'This phone number is already associated with a customer account.' end));
    end if;
  end loop;
  return '{}'::jsonb;
end;
$$;

revoke all on all functions in schema repairshop_private from public, anon, authenticated;
revoke all on function public.check_customer_account_creation(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.check_customer_account_creation(jsonb) to supabase_auth_admin;

commit;
