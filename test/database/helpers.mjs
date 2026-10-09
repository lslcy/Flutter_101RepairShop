import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const projectRoot = new URL('../../', import.meta.url);
let PGlite;
try {
  ({ PGlite } = await import(new URL(
    'build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js',
    projectRoot,
  )));
} catch (error) {
  throw new Error(
    'Install the local SQL test dependency first: npm install --prefix build/sql-validation @electric-sql/pglite',
    { cause: error },
  );
}

export const migrationPaths = [
  'supabase/migrations/202610090001_complete_customer_profile.sql',
  'supabase/migrations/202610090002_customer_account_uniqueness.sql',
];

export function readProjectFile(path) {
  return readFile(new URL(path, projectRoot), 'utf8');
}

export async function applyMigrations(db) {
  for (const path of migrationPaths) await db.exec(await readProjectFile(path));
}

// This mock provides only the Supabase objects used by the production migrations.
// The signup trigger creates a fresh customer; it never merges unverified contacts.
export async function createDatabase({ idType = 'uuid', migrate = true, signupTrigger = true } = {}) {
  if (!['uuid', 'text'].includes(idType)) throw new Error('Unsupported customer ID fixture type.');
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create role supabase_auth_admin;
    create schema auth;
    create table auth.users (
      id uuid primary key default gen_random_uuid(),
      email text,
      phone text,
      raw_user_meta_data jsonb not null default '{}'::jsonb,
      email_confirmed_at timestamptz,
      phone_confirmed_at timestamptz
    );
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create table public.customers (
      id ${idType} primary key default gen_random_uuid()${idType === 'text' ? '::text' : ''},
      auth_id uuid,
      first_name text,
      last_name text,
      email text,
      phone_no text,
      address text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      deleted_at timestamptz
    );
    create function public.handle_new_user() returns trigger
      language plpgsql security definer set search_path = '' as $$
    begin
      insert into public.customers
        (auth_id, email, phone_no, first_name, last_name, address)
      values
        (new.id, new.email,
         coalesce(new.raw_user_meta_data ->> 'phone_no',
                  case when nullif(new.phone, '') is not null then '+' || ltrim(new.phone, '+') end),
         new.raw_user_meta_data ->> 'first_name',
         new.raw_user_meta_data ->> 'last_name',
         new.raw_user_meta_data ->> 'address');
      return new;
    end;
    $$;
  `);
  if (signupTrigger) await db.exec(`
    create trigger handle_new_user after insert on auth.users
      for each row execute function public.handle_new_user();
  `);
  if (migrate) await applyMigrations(db);
  return db;
}

export async function resetData(db) {
  await db.exec(`
    reset role;
    select set_config('request.jwt.claim.sub', '', false);
    truncate public.customers, auth.users,
      repairshop_private.customer_identity_sources,
      repairshop_private.customer_identity_claims;
  `);
}

export async function createUser(db, {
  email = null, phone = null, metadata = {}, verifiedEmail = false, verifiedPhone = false,
} = {}) {
  const result = await db.query(`
    insert into auth.users
      (email, phone, raw_user_meta_data, email_confirmed_at, phone_confirmed_at)
    values ($1, $2, $3::jsonb,
      case when $4 then now() end,
      case when $5 then now() end)
    returning id
  `, [email, phone, JSON.stringify(metadata), verifiedEmail, verifiedPhone]);
  return result.rows[0].id;
}

export async function customerFor(db, authId) {
  return (await db.query('select * from public.customers where auth_id = $1', [authId])).rows[0];
}

export async function claims(db) {
  return (await db.query(`
    select kind, canonical_value, owner_key
      from repairshop_private.customer_identity_claims
      order by kind, canonical_value
  `)).rows;
}

export async function signInAs(db, authId, role = 'authenticated') {
  if (!['authenticated', 'anon', 'supabase_auth_admin'].includes(role)) throw new Error('Unsupported role.');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [authId ?? '']);
  await db.exec(`set role ${role}`);
}

export const rootDirectory = fileURLToPath(projectRoot);
