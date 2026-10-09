import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import {
  createDatabase, createUser, customerFor, readProjectFile, signInAs,
} from './helpers.mjs';

const migrationPath = 'supabase/migrations/202610090006_customer_notifications.sql';
const denied = (operation) => assert.rejects(operation, { code: '42501' });

async function createNotificationDatabase(idType) {
  const db = await createDatabase({ idType });
  await db.exec(`
    create table public.appointments (
      id bigint primary key, customer_id ${idType} not null references public.customers(id),
      appointment_date date, time_slot text, status text, title text, notes text
    );
    create table public.service_reports (
      id bigint primary key, customer_id ${idType} not null references public.customers(id),
      status text, remarks text, deleted_at timestamptz
    );
    create table public.transactions (
      id bigint primary key, customer_id ${idType} not null references public.customers(id),
      payment_status text, payment_method text, deleted_at timestamptz
    );
    create table public.customer_payment_submissions (
      id uuid primary key, transaction_id bigint not null references public.transactions(id),
      customer_id text not null, auth_id uuid not null references auth.users(id),
      method text, status text, review_note text
    );
    -- The real staff notification shape remains separate and private.
    create table public.notifications (
      id uuid primary key, type text, notifiable_type text,
      notifiable_id bigint, data text, read_at timestamptz
    );
    alter table public.notifications enable row level security;
    grant select on public.notifications to authenticated;
    create policy fixture_staff_only on public.notifications
      for select to authenticated using (false);
    insert into public.notifications values
      (gen_random_uuid(), 'StaffAlert', 'App\\Models\\User', 7, 'staff only', null);
    grant usage on schema public, auth to authenticated, anon;
    grant select on public.customers, public.appointments,
      public.service_reports, public.transactions to authenticated;
    alter table public.customers enable row level security;
    alter table public.appointments enable row level security;
    alter table public.service_reports enable row level security;
    alter table public.transactions enable row level security;
    create policy fixture_customer_read on public.customers for select to authenticated
      using (auth_id = auth.uid() and deleted_at is null);
    create policy fixture_appointment_read on public.appointments for select to authenticated
      using (exists (select 1 from public.customers c where c.id = customer_id and c.auth_id = auth.uid()));
    create policy fixture_report_read on public.service_reports for select to authenticated
      using (exists (select 1 from public.customers c where c.id = customer_id and c.auth_id = auth.uid()));
    create policy fixture_transaction_read on public.transactions for select to authenticated
      using (exists (select 1 from public.customers c where c.id = customer_id and c.auth_id = auth.uid()));
  `);
  await db.exec(await readProjectFile(migrationPath));
  return db;
}

async function fixture(db) {
  await db.exec(`
    reset role;
    select set_config('request.jwt.claim.sub', '', false);
    truncate public.customer_notifications, public.customer_payment_submissions,
      public.transactions, public.service_reports, public.appointments,
      public.customers, auth.users, repairshop_private.customer_identity_sources,
      repairshop_private.customer_identity_claims restart identity;
  `);
  const user = await createUser(db, { email: 'owner@example.test' });
  const other = await createUser(db, { email: 'other@example.test' });
  const customer = await customerFor(db, user);
  const otherCustomer = await customerFor(db, other);
  await db.query(`
    insert into public.appointments values
      (1, $1, '2099-10-12', '8:00 AM - 9:00 AM', 'Pending', 'Private appliance', 'private notes'),
      (2, $2, '2099-10-13', '9:00 AM - 10:00 AM', 'Pending', 'Other appliance', 'other notes');
  `, [customer.id, otherCustomer.id]);
  await db.query(`insert into public.service_reports (id, customer_id, status, remarks)
    values (1, $1, 'Pending', 'owner@example.test'), (2, $2, 'Pending', 'other private remarks')`,
  [customer.id, otherCustomer.id]);
  await db.query(`insert into public.transactions (id, customer_id, payment_status)
    values (1, $1, 'Unpaid'), (2, $2, 'Unpaid')`, [customer.id, otherCustomer.id]);
  await db.exec('truncate public.customer_notifications restart identity');
  return { user, other, customer, otherCustomer };
}

async function inbox(db) {
  return (await db.query('select * from public.customer_notifications order by id')).rows;
}

async function pending(db, { user, customer, transactionId = 1, note = 'private review content' }) {
  const id = randomUUID();
  await db.query(`insert into public.customer_payment_submissions
    (id, transaction_id, customer_id, auth_id, method, status, review_note)
    values ($1, $2, $3, $4, 'gcash', 'pending', $5)`, [id, transactionId, customer.id, user, note]);
  return id;
}

for (const idType of ['uuid', 'text']) {
  test(`customer notification security with ${idType} customer IDs`, async (t) => {
    const db = await createNotificationDatabase(idType);
    t.after(() => db.close());
    const scenario = (name, body) => t.test(name, async () => {
      const data = await fixture(db);
      await body(data);
    });

    await scenario('appointment changes notify only their linked customer', async ({ user, other }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await signInAs(db, user);
      const rows = await inbox(db);
      assert.equal(rows.length, 1);
      assert.equal(rows[0].title, 'Appointment confirmed');
      assert.equal(Number(rows[0].appointment_id), 1);
      assert.equal(rows[0].is_read, false);
      await signInAs(db, other);
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('schedule changes notify, unrelated and identical writes do not', async () => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await db.exec("update public.appointments set status = ' Confirmed ' where id = 1");
      await db.exec("update public.appointments set notes = 'new private notes' where id = 1");
      assert.equal((await inbox(db)).length, 1);
      await db.exec("update public.appointments set appointment_date = '2099-10-15', time_slot = '10:00 AM - 11:00 AM' where id = 1");
      const rows = await inbox(db);
      assert.equal(rows.length, 2);
      assert.equal(rows[1].title, 'Appointment rescheduled');
      assert.doesNotMatch(JSON.stringify(rows), /private notes|Private appliance/);
    });

    await scenario('consecutive reschedules each notify while repeated values do not', async () => {
      await db.exec("update public.appointments set appointment_date = '2099-10-15' where id = 1");
      await db.exec("update public.appointments set time_slot = '10:00 AM - 11:00 AM' where id = 1");
      await db.exec("update public.appointments set time_slot = '10:00 AM - 11:00 AM' where id = 1");
      const rows = await inbox(db);
      assert.equal(rows.length, 2);
      assert.deepEqual(rows.map((row) => row.title), ['Appointment rescheduled', 'Appointment rescheduled']);
    });

    await scenario('repair status inserts and changes omit freeform private content', async ({ customer }) => {
      await db.query(`insert into public.service_reports (id, customer_id, status, remarks)
        values (3, $1, 'In Progress', 'private address owner@example.test')`, [customer.id]);
      await db.exec("update public.service_reports set status = 'Completed' where id = 3");
      await db.exec("update public.service_reports set status = 'Completed', remarks = 'more private data' where id = 3");
      const rows = await inbox(db);
      assert.equal(rows.length, 2);
      assert.equal(rows[0].type, 'repair');
      assert.equal(Number(rows[0].report_id), 3);
      assert.match(rows[1].message, /completed/);
      assert.doesNotMatch(JSON.stringify(rows), /private address|example\.test|private data/);
    });

    await scenario('unknown staff status text never copies into a notification', async () => {
      await db.exec("update public.service_reports set status = 'Call customer at +639123456789' where id = 1");
      await db.exec("update public.service_reports set status = 'Email owner@example.test' where id = 1");
      const rows = await inbox(db);
      assert.equal(rows.length, 2);
      assert.doesNotMatch(JSON.stringify(rows), /639123456789|example\.test/);
    });

    await scenario('marking read is the only customer write', async ({ user }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await signInAs(db, user);
      const row = (await inbox(db))[0];
      assert.equal((await db.query('update public.customer_notifications set is_read = true where id = $1 returning is_read', [row.id])).rows[0].is_read, true);
      for (const statement of [
        "update public.customer_notifications set title = 'Forged'",
        "update public.customer_notifications set message = 'Forged'",
        "update public.customer_notifications set user_id = gen_random_uuid()",
        "update public.customer_notifications set customer_id = 'other'",
        "update public.customer_notifications set appointment_id = 2",
        "update public.customer_notifications set created_at = now()",
        'delete from public.customer_notifications',
      ]) await denied(db.exec(statement));
      await denied(db.query(`insert into public.customer_notifications
        (user_id, customer_id, title, type, event_key) values ($1, 'other', 'Forged', 'info', 'fake')`, [user]));
      await denied(db.query(`select repairshop_private.add_customer_notification
        ('other', 'fake', 'Forged', 'Forged', 'info')`));
    });

    await scenario('another customer cannot mark an owner entry read', async ({ other }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      const id = (await inbox(db))[0].id;
      await signInAs(db, other);
      assert.deepEqual((await db.query('update public.customer_notifications set is_read = true where id = $1 returning id', [id])).rows, []);
      await db.exec('reset role');
      assert.equal((await inbox(db))[0].is_read, false);
    });

    await scenario('anonymous and missing identity reads expose no inbox', async () => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await signInAs(db, null, 'anon');
      await denied(inbox(db));
      await signInAs(db, null);
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('archived customers lose reads and receive no new updates', async ({ user }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await db.query('update public.customers set deleted_at = now() where auth_id = $1', [user]);
      await db.exec("update public.appointments set status = 'Cancelled' where id = 1");
      assert.equal((await inbox(db)).length, 1);
      await signInAs(db, user);
      assert.deepEqual(await inbox(db), []);
      assert.deepEqual((await db.query('update public.customer_notifications set is_read = true returning id')).rows, []);
    });

    await scenario('archived source rows stop updates and hide stale links', async ({ user }) => {
      await db.exec("update public.service_reports set status = 'In Progress' where id = 1");
      await db.exec("update public.service_reports set status = 'Completed', deleted_at = now() where id = 1");
      await db.exec("update public.transactions set payment_status = 'Paid', deleted_at = now() where id = 1");
      assert.equal((await inbox(db)).length, 1);
      await signInAs(db, user);
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('reassigning a source cannot reveal old account notifications', async ({ user, other, otherCustomer }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await db.query('update public.appointments set customer_id = $1 where id = 1', [otherCustomer.id]);
      await signInAs(db, user);
      assert.deepEqual(await inbox(db), []);
      await signInAs(db, other);
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('unlinked customer identities receive no notification', async () => {
      const legacy = (await db.query(`insert into public.customers (first_name, last_name)
        values ('Legacy', 'Customer') returning id`)).rows[0];
      await db.query(`insert into public.appointments (id, customer_id, status)
        values (3, $1, 'Pending')`, [legacy.id]);
      await db.exec("update public.appointments set status = 'Confirmed' where id = 3");
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('pending and rejected receipts link to payments without review notes', async (data) => {
      const id = await pending(db, data);
      await db.query("update public.customer_payment_submissions set status = 'rejected', review_note = 'private email owner@example.test' where id = $1", [id]);
      const rows = await inbox(db);
      assert.deepEqual(rows.map((row) => row.title), ['Payment submitted', 'Payment receipt needs attention']);
      assert.equal(Number(rows[1].transaction_id), 1);
      assert.doesNotMatch(JSON.stringify(rows), /private email|example\.test|private review/);
    });

    await scenario('receipt approval creates exactly one payment confirmation', async (data) => {
      const id = await pending(db, data);
      await db.exec('begin');
      await db.exec("update public.transactions set payment_status = 'Paid', payment_method = 'GCash' where id = 1");
      await db.query("update public.customer_payment_submissions set status = 'approved' where id = $1", [id]);
      await db.exec('commit');
      await db.exec("update public.transactions set payment_status = ' Paid ' where id = 1");
      const rows = await inbox(db);
      assert.deepEqual(rows.map((row) => row.title), ['Payment submitted', 'Payment confirmed']);
    });

    await scenario('staff payment reversals allow a later genuine payment confirmation', async () => {
      await db.exec("update public.transactions set payment_status = 'Paid' where id = 1");
      await db.exec("update public.transactions set payment_status = 'Unpaid' where id = 1");
      await db.exec("update public.transactions set payment_status = 'Paid' where id = 1");
      await db.exec("update public.transactions set payment_status = ' Paid ' where id = 1");
      const rows = await inbox(db);
      assert.equal(rows.length, 2);
      assert.deepEqual(rows.map((row) => row.title), ['Payment confirmed', 'Payment confirmed']);
    });

    await scenario('mismatched receipt auth and ownership never route to another inbox', async (data) => {
      await pending(db, { ...data, user: data.other });
      await pending(db, { ...data, transactionId: 2 });
      assert.deepEqual(await inbox(db), []);
    });

    await scenario('multiple appointment updates in one transaction keep only the final body', async () => {
      await db.exec('begin');
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await db.exec("update public.appointments set status = 'Cancelled' where id = 1");
      await db.exec('commit');
      const rows = await inbox(db);
      assert.equal(rows.length, 1);
      assert.equal(rows[0].title, 'Appointment cancelled');
    });

    await scenario('reapplying preserves read state and staff notification schema and policy', async ({ user }) => {
      await db.exec("update public.appointments set status = 'Confirmed' where id = 1");
      await db.exec('update public.customer_notifications set is_read = true');
      await db.exec(await readProjectFile(migrationPath));
      assert.equal((await inbox(db))[0].is_read, true);
      assert.equal((await db.query('select count(*) from public.notifications')).rows[0].count, 1);
      assert.equal((await db.query(`select data_type from information_schema.columns
        where table_schema = 'public' and table_name = 'notifications' and column_name = 'id'`)).rows[0].data_type, 'uuid');
      assert.equal((await db.query("select count(*) from pg_policies where tablename = 'notifications' and policyname = 'fixture_staff_only'")).rows[0].count, 1);
      await signInAs(db, user);
      assert.deepEqual((await db.query('select * from public.notifications')).rows, []);
    });
  });
}
