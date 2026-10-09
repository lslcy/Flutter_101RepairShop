-- READ ONLY. Run as a project administrator before migration 202610090002.
-- Results contain counts only: do not post customer emails, phones, IDs or names.
-- All counts must be zero except contact_metadata_conflict_groups (review only).
with policy as (
  select U&'\0009\000a\000b\000c\000d\0020\0085\00a0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200a\2028\2029\202f\205f\3000\feff' as trim_characters
), raw_contacts as (
  select 'customer'::text as source_kind, id::text as source_id,
    case when auth_id is null then 'customer:' || id::text
         else 'auth:' || auth_id::text end as owner_key,
    'email'::text as kind, email::text as raw_value
  from public.customers
  union all
  select 'customer', id::text,
    case when auth_id is null then 'customer:' || id::text
         else 'auth:' || auth_id::text end, 'phone', phone_no
  from public.customers
  union all
  select 'auth', id::text, 'auth:' || id::text, 'email', email from auth.users
  union all
  select 'auth', id::text, 'auth:' || id::text, 'phone',
    case when nullif(btrim(phone), '') is null then null else '+' || ltrim(phone, '+') end
  from auth.users
  union all
  select 'metadata', id::text, 'auth:' || id::text, 'phone',
    raw_user_meta_data ->> 'phone_no' from auth.users
), trimmed_contacts as (
  select raw_contacts.*, btrim(raw_value, policy.trim_characters) as trimmed
  from raw_contacts cross join policy
), phone_separators as (
  select *, regexp_replace(trimmed,
    U&'[\00a0\1680\2000-\200a\2028\2029\202f\205f\3000\feff]', ' ', 'g') as phone_input
  from trimmed_contacts
), compact as (
  select *, regexp_replace(phone_input, '[[:space:]().-]', '', 'g') as compact_phone
  from phone_separators
), international as (
  select *, case when left(compact_phone, 2) = '00'
    then '+' || substr(compact_phone, 3) else compact_phone end as prefixed_phone
  from compact
), philippines as (
  select *, case
    when prefixed_phone ~ '^09[0-9]{9}$' then '+63' || substr(prefixed_phone, 2)
    when prefixed_phone ~ '^9[0-9]{9}$' then '+63' || prefixed_phone
    when prefixed_phone ~ '^639[0-9]{9}$' then '+' || prefixed_phone
    else prefixed_phone end as candidate_phone
  from international
), normalized as (
  select *, case
    when kind = 'email' then nullif(lower(trimmed), '')
    when phone_input ~ '^[+0-9[:space:]().-]+$'
      and candidate_phone ~ '^\+[1-9][0-9]{7,14}$'
      and (left(candidate_phone, 3) <> '+63' or candidate_phone ~ '^\+639[0-9]{9}$')
      then candidate_phone
    else null end as canonical_value
  from philippines
), duplicate_customer_email as (
  select canonical_value from normalized
    where source_kind = 'customer' and kind = 'email' and canonical_value is not null
    group by canonical_value having count(*) > 1
), duplicate_customer_phone as (
  select canonical_value from normalized
    where source_kind = 'customer' and kind = 'phone' and canonical_value is not null
    group by canonical_value having count(*) > 1
), duplicate_customer_auth as (
  select auth_id from public.customers where auth_id is not null
    group by auth_id having count(*) > 1
), conflicting_owners as (
  select kind, canonical_value from normalized
    where source_kind <> 'metadata' and canonical_value is not null
    group by kind, canonical_value having count(distinct owner_key) > 1
), conflicting_metadata as (
  select distinct m.canonical_value from normalized m join normalized n
    on m.kind = n.kind and m.canonical_value = n.canonical_value
    where m.source_kind = 'metadata' and n.source_kind <> 'metadata'
      and m.owner_key <> n.owner_key
)
select 'duplicate_customer_auth_groups' as check_name,
       (select count(*) from duplicate_customer_auth) as problem_count
union all select 'duplicate_customer_email_groups', count(*) from duplicate_customer_email
union all select 'duplicate_customer_phone_groups', count(*) from duplicate_customer_phone
union all select 'cross_account_email_conflict_groups', count(*) from conflicting_owners where kind = 'email'
union all select 'cross_account_phone_conflict_groups', count(*) from conflicting_owners where kind = 'phone'
union all select 'invalid_customer_phone_rows', count(*) from normalized
  where source_kind = 'customer' and kind = 'phone' and nullif(trimmed, '') is not null and canonical_value is null
union all select 'invalid_auth_phone_rows', count(*) from normalized
  where source_kind = 'auth' and kind = 'phone' and nullif(trimmed, '') is not null and canonical_value is null
union all select 'contact_metadata_conflict_groups', count(*) from conflicting_metadata
order by check_name;