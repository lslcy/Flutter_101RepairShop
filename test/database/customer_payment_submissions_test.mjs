import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import {
  createDatabase, createUser, customerFor, readProjectFile, signInAs,
} from './helpers.mjs';

const denied = (operation) => assert.rejects(operation, { code: '42501' });
const rejected = (operation, message) => assert.rejects(operation, (error) => {
  assert.match(error.message, message);
  return true;
});

// Match the relevant Supabase grants and ownership RLS. The storage API's
// MIME/size validation is not reproduced here; its configured bucket limits
// are checked separately. Preexisting broad permissive policies deliberately
// allow every public Storage operation, exercising restrictive guards.
async function createPaymentDatabase(idType) {
  const db = await createDatabase({ idType });
  await db.exec(`
    create role service_role bypassrls;
    create schema storage;
    create table storage.buckets (
      id text primary key,
      name text not null,
      public boolean not null default false,
      file_size_limit bigint,
      allowed_mime_types text[]
    );
    create table storage.objects (
      id uuid primary key default gen_random_uuid(),
      bucket_id text not null references storage.buckets(id),
      name text not null,
      unique (bucket_id, name)
    );
    create table public.transactions (
      id bigint primary key,
      customer_id ${idType} not null references public.customers(id),
      total_amount numeric(12,2),
      partial_payment_amount numeric(12,2),
      payment_status text,
      payment_method text,
      paid_at timestamptz,
      payment_date date,
      reference_no text,
      updated_at timestamptz not null default now(),
      deleted_at timestamptz
    );
    alter table public.customers enable row level security;
    alter table public.transactions enable row level security;
    alter table storage.objects enable row level security;
    grant usage on schema public, auth, storage to authenticated, anon, service_role;
    grant select on public.customers, public.transactions to authenticated;
    grant select, insert, update, delete on storage.objects to anon, authenticated;
    grant select on storage.buckets to authenticated;
    insert into storage.buckets (id, name) values ('legacy-images', 'legacy-images');
    create policy fixture_legacy_storage_read on storage.objects
      for select to public using (true);
    create policy fixture_legacy_storage_insert on storage.objects
      for insert to public with check (true);
    create policy fixture_legacy_storage_update on storage.objects
      for update to public using (true) with check (true);
    create policy fixture_legacy_storage_delete on storage.objects
      for delete to public using (true);
    create policy fixture_customer_read on public.customers
      for select to authenticated using (auth_id = auth.uid() and deleted_at is null);
    create policy fixture_transaction_read on public.transactions
      for select to authenticated using (
        exists (select 1 from public.customers c where c.id = customer_id and c.auth_id = auth.uid())
      );
  `);
  await db.exec(await readProjectFile('supabase/migrations/202610090005_customer_payment_submissions.sql'));
  return db;
}

async function resetPayments(db) {
  await db.exec(`
    reset role;
    select set_config('request.jwt.claim.sub', '', false);
    truncate public.customer_payment_submissions, public.transactions,
      storage.objects, public.customers, auth.users,
      repairshop_private.customer_identity_sources,
      repairshop_private.customer_identity_claims;
    delete from public.customer_payment_settings;
  `);
}

async function fixture(db, { settings = true, status = 'Unpaid', partial = null, total = 1000 } = {}) {
  const user = await createUser(db, { email: 'payer@example.test' });
  const other = await createUser(db, { email: 'other@example.test' });
  const customer = await customerFor(db, user);
  const otherCustomer = await customerFor(db, other);
  await db.query(`
    insert into public.transactions (id, customer_id, total_amount, partial_payment_amount, payment_status)
      values (1, $1, $2, $3, $4), (2, $5, 2000, null, 'Unpaid')
  `, [customer.id, total, partial, status, otherCustomer.id]);
  if (settings) await db.exec(`
    insert into public.customer_payment_settings values
      (1, 'https://example.test/merchant-qr.png', 'Repair Shop');
  `);
  return { user, other, customer, otherCustomer };
}

function receipt(user, transaction = 1, request = randomUUID(), extension = 'png') {
  return { request, path: `${user}/${transaction}/${request}.${extension}` };
}

async function upload(db, path, bucket = 'payment-receipts') {
  return db.query('insert into storage.objects (bucket_id, name) values ($1, $2) returning name', [bucket, path]);
}

async function submit(db, { transaction = 1, method = 'gcash', path = null, request = randomUUID() } = {}) {
  return (await db.query(`
    select public.submit_customer_payment($1::bigint, $2::text, $3::text, $4::uuid) as submission
  `, [transaction, method, path, request])).rows[0].submission;
}

async function serviceRole(db) {
  await db.exec('reset role; set role service_role');
}

async function review(db, submission, { decision = 'approved', admin = 'admin:7', note = null, reference = null } = {}) {
  return (await db.query(`
    select public.review_customer_payment($1::uuid, $2::text, $3::text, $4::text, $5::text) as submission
  `, [submission.id, decision, admin, note, reference])).rows[0].submission;
}

async function transaction(db, id = 1) {
  return (await db.query('select * from public.transactions where id = $1', [id])).rows[0];
}

async function makePending(db, user, transactionId = 1) {
  await signInAs(db, user);
  const evidence = receipt(user, transactionId);
  await upload(db, evidence.path);
  return submit(db, { transaction: transactionId, ...evidence });
}

for (const idType of ['uuid', 'text']) {
  test(`customer payment submission security with ${idType} customer IDs`, async (t) => {
    const db = await createPaymentDatabase(idType);
    t.after(() => db.close());
    const scenario = (name, body) => t.test(name, async () => {
      await resetPayments(db);
      await body();
    });

    await scenario('receipts use a private 5MB image-only bucket', async () => {
      const bucket = (await db.query("select * from storage.buckets where id = 'payment-receipts'")).rows[0];
      assert.equal(bucket.public, false);
      assert.equal(Number(bucket.file_size_limit), 5242880);
      assert.deepEqual(bucket.allowed_mime_types, ['image/jpeg', 'image/png', 'image/webp']);
    });

    await scenario('merchant QR storage allows reads but rejects customer and anonymous writes despite broad policies', async () => {
      const { user } = await fixture(db);
      const bucket = (await db.query("select * from storage.buckets where id = 'shop-payment-qr'")).rows[0];
      assert.equal(bucket.public, true);
      assert.equal(Number(bucket.file_size_limit), 5242880);
      assert.deepEqual(bucket.allowed_mime_types, ['image/jpeg', 'image/png', 'image/webp']);
      await upload(db, 'gcash/merchant.png', 'shop-payment-qr');
      for (const role of ['authenticated', 'anon']) {
        await db.exec('reset role');
        await signInAs(db, role === 'anon' ? null : user, role);
        assert.equal((await db.query("select name from storage.objects where bucket_id = 'shop-payment-qr'")).rows[0].name, 'gcash/merchant.png');
        await denied(upload(db, 'gcash/replaced.png', 'shop-payment-qr'));
        assert.deepEqual((await db.query("update storage.objects set name = 'gcash/replaced.png' where bucket_id = 'shop-payment-qr' returning id")).rows, []);
        assert.deepEqual((await db.query("delete from storage.objects where bucket_id = 'shop-payment-qr' returning id")).rows, []);
        await upload(db, `${role}-avatar.png`, 'legacy-images');
        await denied(db.query("update storage.objects set bucket_id = 'shop-payment-qr' where name = $1", [`${role}-avatar.png`]));
      }
      await db.exec('reset role');
      assert.equal((await db.query("select name from storage.objects where bucket_id = 'shop-payment-qr'")).rows[0].name, 'gcash/merchant.png');
    });

    await scenario('payment migration can be reapplied while preserving pending receipts and merchant settings', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await db.exec('reset role');
      await db.exec(await readProjectFile('supabase/migrations/202610090005_customer_payment_submissions.sql'));
      const stored = (await db.query('select * from public.customer_payment_submissions where id = $1', [pending.id])).rows[0];
      assert.equal(stored.status, 'pending');
      assert.equal(stored.receipt_path, pending.receipt_path);
      assert.equal((await db.query('select gcash_recipient_name from public.customer_payment_settings where id = 1')).rows[0].gcash_recipient_name, 'Repair Shop');
      assert.equal((await db.query('select count(*)::int as count from storage.objects where name = $1', [pending.receipt_path])).rows[0].count, 1);
    });

    await scenario('choosing the shop keeps the authoritative balance unpaid', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      const choice = await submit(db, { method: 'shop' });
      assert.equal(choice.method, 'shop');
      assert.equal(choice.status, 'pay_at_shop');
      assert.equal(choice.amount, 1000);
      assert.equal(choice.receipt_path, null);
      const financial = await transaction(db);
      assert.equal(financial.payment_status, 'Unpaid');
      assert.equal(financial.paid_at, null);
    });

    await scenario('a GCash receipt becomes pending without recording money as paid', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      assert.equal(pending.status, 'pending');
      assert.equal(pending.method, 'gcash');
      assert.equal(pending.amount, 1000);
      assert.equal(pending.auth_id, user);
      const financial = await transaction(db);
      assert.equal(financial.payment_status, 'Unpaid');
      assert.equal(financial.payment_method, null);
      assert.equal(financial.paid_at, null);
      assert.equal(financial.payment_date, null);
    });

    await scenario('partial bills submit only their outstanding balance', async () => {
      const { user } = await fixture(db, { status: 'Partial', partial: 250 });
      const pending = await makePending(db, user);
      assert.equal(pending.amount, 750);
      assert.equal((await transaction(db)).partial_payment_amount, '250.00');
      assert.equal((await transaction(db)).payment_status, 'Partial');
    });

    await scenario('customers cannot submit or read another customer payment', async () => {
      const { user, other } = await fixture(db);
      const pending = await makePending(db, user);
      await signInAs(db, other);
      await rejected(submit(db, { method: 'shop' }), /not available for your account/);
      assert.deepEqual((await db.query('select * from public.customer_payment_submissions')).rows, []);
      assert.deepEqual((await db.query('select * from storage.objects where name = $1', [pending.receipt_path])).rows, []);
    });

    await scenario('anonymous and missing-auth callers cannot submit', async () => {
      await fixture(db);
      await signInAs(db, null, 'anon');
      await denied(submit(db, { method: 'shop' }));
      await signInAs(db, null);
      await rejected(submit(db, { method: 'shop' }), /Sign in again/);
    });

    await scenario('customers have no direct submission writes or admin review permission', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await denied(db.query('update public.customer_payment_submissions set status = $1 where id = $2', ['approved', pending.id]));
      await denied(db.query('delete from public.customer_payment_submissions where id = $1', [pending.id]));
      await denied(db.query(`insert into public.customer_payment_submissions
        (transaction_id, auth_id, customer_id, method, status, amount)
        values (1, $1, 'customer', 'shop', 'pay_at_shop', 1000)`, [user]));
      await denied(review(db, pending));
      await denied(db.exec("update public.transactions set payment_status = 'Paid' where id = 1"));
      await denied(db.exec("update public.customer_payment_settings set gcash_recipient_name = 'Other recipient'"));
    });

    await scenario('settings can be read by authenticated customers only', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      assert.equal((await db.query('select gcash_recipient_name from public.customer_payment_settings')).rows[0].gcash_recipient_name, 'Repair Shop');
      await signInAs(db, null, 'anon');
      await denied(db.query('select * from public.customer_payment_settings'));
    });

    await scenario('GCash requires a previously uploaded matching receipt', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      const evidence = receipt(user);
      await rejected(submit(db, evidence), /Upload your receipt/);
      assert.deepEqual((await db.query('select * from public.customer_payment_submissions')).rows, []);
    });

    await scenario('receipt path must match customer, transaction, request and supported extension', async () => {
      const { user, other } = await fixture(db);
      const evidence = receipt(user);
      await signInAs(db, user);
      await upload(db, evidence.path);
      for (const path of [
        `${other}/1/${evidence.request}.png`,
        `${user}/2/${evidence.request}.png`,
        `${user}/1/${randomUUID()}.png`,
        `${user}/1/${evidence.request}.pdf`,
        `${user}/1/../${evidence.request}.png`,
      ]) await rejected(submit(db, { ...evidence, path }), /Upload your receipt/);
      await rejected(submit(db, { method: 'shop', path: evidence.path }), /does not need a receipt/);
    });

    await scenario('storage rejects another folder, another bill, paid bills and archived bills', async () => {
      const { user, other } = await fixture(db);
      await signInAs(db, user);
      await denied(upload(db, receipt(other).path));
      await denied(upload(db, receipt(user, 2).path));
      await denied(upload(db, receipt(user, 1, randomUUID(), 'pdf').path));
      await db.exec('reset role');
      await db.exec("update public.transactions set payment_status = 'Paid' where id = 1");
      await signInAs(db, user);
      await denied(upload(db, receipt(user).path));
      await db.exec('reset role');
      await db.exec("update public.transactions set payment_status = 'Unpaid', deleted_at = now() where id = 1");
      await signInAs(db, user);
      await denied(upload(db, receipt(user).path));
    });

    await scenario('customers cannot replace or delete either draft or attached receipts', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      const evidence = receipt(user);
      await upload(db, evidence.path);
      const edit = () => db.query('update storage.objects set name = $1 where name = $2 returning id', [receipt(user).path, evidence.path]);
      const remove = () => db.query('delete from storage.objects where name = $1 returning id', [evidence.path]);
      assert.deepEqual((await edit()).rows, []);
      assert.deepEqual((await remove()).rows, []);
      await submit(db, evidence);
      assert.deepEqual((await edit()).rows, []);
      assert.deepEqual((await remove()).rows, []);
      assert.equal((await db.query('select * from storage.objects where name = $1', [evidence.path])).rows.length, 1);
    });

    await scenario('archiving a customer cannot expose attached evidence to deletion through RLS', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await db.exec('reset role');
      await db.query('update public.customers set deleted_at = now() where auth_id = $1', [user]);
      await signInAs(db, user);
      assert.deepEqual((await db.query('select * from public.customer_payment_submissions')).rows, []);
      assert.deepEqual((await db.query('delete from storage.objects where name = $1 returning id', [pending.receipt_path])).rows, []);
      await db.exec('reset role');
      assert.equal((await db.query('select * from storage.objects where name = $1', [pending.receipt_path])).rows.length, 1);
    });


    await scenario('receipt guards preserve unrelated Storage permissions', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      await upload(db, 'legacy-avatar.png', 'legacy-images');
      assert.equal((await db.query("select name from storage.objects where bucket_id = 'legacy-images'")).rows[0].name, 'legacy-avatar.png');
      const edited = await db.query("update storage.objects set name = 'updated-avatar.png' where bucket_id = 'legacy-images' returning name");
      assert.equal(edited.rows[0].name, 'updated-avatar.png');
      const removed = await db.query("delete from storage.objects where bucket_id = 'legacy-images' returning name");
      assert.equal(removed.rows[0].name, 'updated-avatar.png');
    });

    await scenario('broad legacy update policies cannot move an existing object into the receipt bucket', async () => {
      const { user } = await fixture(db);
      const evidence = receipt(user);
      await signInAs(db, user);
      await upload(db, evidence.path, 'legacy-images');
      await denied(db.query("update storage.objects set bucket_id = 'payment-receipts' where name = $1", [evidence.path]));
      assert.equal((await db.query('select bucket_id from storage.objects where name = $1', [evidence.path])).rows[0].bucket_id, 'legacy-images');
    });

    await scenario('broad legacy policies cannot expose, replace, delete or move another customer receipt', async () => {
      const { user, other } = await fixture(db);
      const pending = await makePending(db, user);
      await signInAs(db, other);
      assert.deepEqual((await db.query('select * from storage.objects where name = $1', [pending.receipt_path])).rows, []);
      assert.deepEqual((await db.query('update storage.objects set name = $1 where name = $2 returning id', [receipt(other).path, pending.receipt_path])).rows, []);
      assert.deepEqual((await db.query("update storage.objects set bucket_id = 'legacy-images' where name = $1 returning id", [pending.receipt_path])).rows, []);
      assert.deepEqual((await db.query('delete from storage.objects where name = $1 returning id', [pending.receipt_path])).rows, []);
      await denied(upload(db, pending.receipt_path));
      await db.exec('reset role');
      const stored = (await db.query('select bucket_id, name from storage.objects where name = $1', [pending.receipt_path])).rows[0];
      assert.equal(stored.bucket_id, 'payment-receipts');
      assert.equal(stored.name, pending.receipt_path);
    });

    await scenario('broad public Storage policies cannot expose or mutate private receipts anonymously', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await signInAs(db, null, 'anon');
      assert.deepEqual((await db.query('select * from storage.objects where name = $1', [pending.receipt_path])).rows, []);
      assert.deepEqual((await db.query('update storage.objects set name = $1 where name = $2 returning id', ['anonymous.png', pending.receipt_path])).rows, []);
      assert.deepEqual((await db.query('delete from storage.objects where name = $1 returning id', [pending.receipt_path])).rows, []);
      await denied(upload(db, receipt(user).path));
      await db.exec('reset role');
      assert.equal((await db.query('select * from storage.objects where name = $1', [pending.receipt_path])).rows.length, 1);
    });
    await scenario('exact retries return the same submission and incompatible ID reuse is rejected', async () => {
      const { user, other } = await fixture(db);
      await signInAs(db, user);
      const evidence = receipt(user);
      await upload(db, evidence.path);
      const pending = await submit(db, evidence);
      assert.deepEqual(await submit(db, evidence), pending);
      await rejected(submit(db, { ...evidence, method: 'shop', path: null }), /request could not be confirmed/);
      await rejected(submit(db, { ...evidence, path: receipt(user).path }), /request could not be confirmed/);
      await signInAs(db, other);
      await rejected(submit(db, { method: 'shop', transaction: 2, request: evidence.request }), /request could not be confirmed/);
      await db.exec('reset role');
      assert.equal((await db.query('select count(*)::int as count from public.customer_payment_submissions')).rows[0].count, 1);
    });

    await scenario('only one receipt remains pending and shop retries do not duplicate choices', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      const shop = await submit(db, { method: 'shop' });
      assert.deepEqual(await submit(db, { method: 'shop' }), shop);
      const evidence = receipt(user);
      await upload(db, evidence.path);
      const pending = await submit(db, evidence);
      await rejected(submit(db, { method: 'shop' }), /already pending review/);
      await rejected(submit(db, { ...receipt(user) }), /already pending review/);
      const history = (await db.query('select status from public.customer_payment_submissions order by created_at')).rows;
      assert.deepEqual(history.map((row) => row.status), ['superseded', 'pending']);
      assert.equal(pending.status, 'pending');
    });

    await scenario('trusted approval marks the unchanged outstanding balance Paid', async () => {
      const { user } = await fixture(db, { status: 'Partial', partial: 250 });
      const pending = await makePending(db, user);
      await serviceRole(db);
      const approved = await review(db, pending, { reference: '  GCASH-REF-42  ' });
      assert.equal(approved.status, 'approved');
      assert.equal(approved.reviewed_by, 'admin:7');
      assert.ok(approved.reviewed_at);
      await db.exec('reset role');
      const financial = await transaction(db);
      assert.equal(financial.payment_status, 'Paid');
      assert.equal(financial.payment_method, 'GCash');
      assert.equal(financial.partial_payment_amount, null);
      assert.equal(financial.reference_no, 'GCASH-REF-42');
      assert.ok(financial.paid_at);
      assert.ok(financial.payment_date);
    });

    await scenario('changed balances cannot be approved and preserve financial state', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await db.exec('reset role');
      await db.exec('update public.transactions set total_amount = 1200 where id = 1');
      await serviceRole(db);
      await rejected(review(db, pending), /balance changed/);
      await db.exec('reset role');
      assert.equal((await transaction(db)).payment_status, 'Unpaid');
      assert.equal((await db.query('select status from public.customer_payment_submissions where id = $1', [pending.id])).rows[0].status, 'pending');
    });

    await scenario('rejection requires a reason and permits a corrected new receipt', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await serviceRole(db);
      await rejected(review(db, pending, { decision: 'rejected', note: ' ' }), /Add a reason/);
      const declined = await review(db, pending, { decision: 'rejected', note: '  Receipt is unreadable.  ' });
      assert.equal(declined.status, 'rejected');
      assert.equal(declined.review_note, 'Receipt is unreadable.');
      await signInAs(db, user);
      const evidence = receipt(user);
      await upload(db, evidence.path);
      const corrected = await submit(db, evidence);
      assert.equal(corrected.status, 'pending');
      assert.notEqual(corrected.id, pending.id);
      assert.equal((await transaction(db)).payment_status, 'Unpaid');
      assert.equal((await db.query('select * from public.customer_payment_submissions')).rows.length, 2);
    });

    await scenario('reviews require admin identity and cannot repeat or approve a shop choice', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await serviceRole(db);
      await rejected(review(db, pending, { admin: ' ' }), /administrator identity is required/);
      await rejected(review(db, pending, { decision: 'paid' }), /Choose approved or rejected/);
      await review(db, pending);
      await rejected(review(db, pending), /Only a pending GCash receipt/);
    });

    await scenario('paid and archived transactions cannot accept new payment choices or approval', async () => {
      const { user } = await fixture(db);
      const pending = await makePending(db, user);
      await db.exec('reset role');
      await db.exec('update public.transactions set deleted_at = now() where id = 1');
      await signInAs(db, user);
      await rejected(submit(db, { method: 'shop' }), /not available for your account/);
      await serviceRole(db);
      await rejected(review(db, pending), /archived or already paid/);
      await db.exec('reset role');
      await db.exec("update public.transactions set deleted_at = null, payment_status = 'Paid' where id = 1");
      await signInAs(db, user);
      await rejected(submit(db, { method: 'shop' }), /already been paid/);
      await serviceRole(db);
      await rejected(review(db, pending), /archived or already paid/);
    });

    await scenario('archived customers cannot submit additional choices', async () => {
      const { user } = await fixture(db);
      await db.query('update public.customers set deleted_at = now() where auth_id = $1', [user]);
      await signInAs(db, user);
      await rejected(submit(db, { method: 'shop' }), /not available for your account/);
    });

    await scenario('missing GCash settings still allow Pay at the shop', async () => {
      const { user } = await fixture(db, { settings: false });
      await signInAs(db, user);
      await rejected(submit(db, receipt(user)), /GCash is not available yet/);
      assert.equal((await submit(db, { method: 'shop' })).status, 'pay_at_shop');
    });

    await scenario('unknown, zero, negative and fully covered balances reject submission', async () => {
      const { user } = await fixture(db);
      for (const [total, partial, status] of [[null, null, 'Unpaid'], [0, null, 'Unpaid'], [-1, null, 'Unpaid'], [1000, 1000, 'Partial']]) {
        await db.exec('reset role');
        await db.query('update public.transactions set total_amount = $1, partial_payment_amount = $2, payment_status = $3 where id = 1', [total, partial, status]);
        await signInAs(db, user);
        await rejected(submit(db, { method: 'shop' }), /shop must set a balance/);
      }
    });

    await scenario('invalid methods and shop reviews cannot alter financial state', async () => {
      const { user } = await fixture(db);
      await signInAs(db, user);
      for (const method of [null, '', 'cash', 'Paid', 'GCash']) {
        await rejected(submit(db, { method }), /Choose GCash or Pay at the shop/);
      }
      const shop = await submit(db, { method: 'shop' });
      await serviceRole(db);
      await rejected(review(db, shop), /Only a pending GCash receipt/);
      await db.exec('reset role');
      assert.equal((await transaction(db)).payment_status, 'Unpaid');
    });
  });
}

// PGlite uses one database session. The idempotency/one-open-submission checks
// above execute real SQL and constraints, but do not simulate simultaneous
// independent connections, live Supabase Storage HTTP, or Laravel admin auth.