import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyMigrations, claims, createDatabase, createUser, customerFor,
  readProjectFile, resetData, signInAs,
} from './helpers.mjs';

const duplicate = (operation, contact) => assert.rejects(operation, (error) => {
  assert.equal(error.code, '23505');
  if (contact) assert.match(error.message, new RegExp(`This ${contact}.*already associated`));
  return true;
});
const denied = (operation) => assert.rejects(operation, { code: '42501' });
const owner = (id) => `auth:${id}`;

for (const idType of ['uuid', 'text']) {
  test(`customer identity enforcement with ${idType} customer IDs`, async (t) => {
    const db = await createDatabase({ idType });
    t.after(() => db.close());
    const scenario = async (name, body) => t.test(name, async () => {
      await resetData(db);
      await body();
    });

    await scenario('normalizes Philippine and international phones and email case', async () => {
      const variants = [
        '09171234567', '9171234567', '639171234567', '+639171234567',
        '  +63 (917) 123-4567  ', '00639171234567', '09\u00a0171234567',
        '\u008509171234567\u0085',
      ];
      for (const phone of variants) {
        assert.equal((await db.query(
          'select repairshop_private.customer_phone_key($1) as value', [phone],
        )).rows[0].value, '+639171234567');
      }
      assert.equal((await db.query(
        'select repairshop_private.customer_phone_key($1) as value', ['+1 (415) 555-2671'],
      )).rows[0].value, '+14155552671');
      for (const phone of [null, '', '   ', '\u0085', '123', '+6309171234567', '0917abc4567', '++639171234567']) {
        assert.equal((await db.query(
          'select repairshop_private.customer_phone_key($1) as value', [phone],
        )).rows[0].value, null);
      }
      assert.equal((await db.query(
        'select repairshop_private.customer_email_key($1) as value', ['  Mixed.Case@Example.COM '],
      )).rows[0].value, 'mixed.case@example.com');
      for (const whitespace of ['\u00a0', '\ufeff', '\u2003', '\u202f']) {
        assert.equal((await db.query(
          'select repairshop_private.customer_email_key($1) as value',
          [`${whitespace}Mixed.Case@Example.COM${whitespace}`],
        )).rows[0].value, 'mixed.case@example.com');
      }
    });

    await scenario('blocks reused email at Auth signup and customer insertion', async () => {
      const first = await createUser(db, { email: ' First@Example.COM ' });
      assert.equal((await customerFor(db, first)).email, 'first@example.com');
      await duplicate(createUser(db, { email: 'first@example.com' }), 'email');
      await duplicate(createUser(db, { email: '\u00a0FIRST@example.com\ufeff' }), 'email');
      await duplicate(db.query(
        'insert into public.customers (email) values ($1)', ['FIRST@example.com'],
      ), 'email');
      assert.equal((await db.query('select count(*)::integer as count from auth.users')).rows[0].count, 1);
      assert.equal((await db.query('select count(*)::integer as count from public.customers')).rows[0].count, 1);
    });

    await scenario('blocks reused phone in signup metadata and actual Auth phone', async () => {
      const first = await createUser(db, {
        email: 'first@example.com', metadata: { phone_no: '09171234567' },
      });
      assert.equal((await customerFor(db, first)).phone_no, '+639171234567');
      for (const phone of ['+639171234567', '639171234567', '9171234567', '00639171234567', '09\u00a0171234567']) {
        await duplicate(createUser(db, {
          email: 'second@example.com', metadata: { phone_no: phone },
        }), 'phone number');
        await duplicate(db.query(
          'insert into public.customers (phone_no) values ($1)', [phone],
        ), 'phone number');
      }
      await duplicate(createUser(db, { email: 'second@example.com', phone: '639171234567' }), 'phone number');
      assert.equal((await db.query('select count(*)::integer as count from auth.users')).rows[0].count, 1);
    });

    await scenario('rejects invalid new phone numbers atomically', async () => {
      await assert.rejects(createUser(db, {
        email: 'first@example.com', metadata: { phone_no: 'invalid phone' },
      }), { code: '22023' });
      await assert.rejects(createUser(db, {
        email: 'first@example.com', phone: '123',
      }), { code: '22023' });
      assert.deepEqual(await claims(db), []);
      assert.equal((await db.query('select count(*)::integer as count from auth.users')).rows[0].count, 0);
    });

    await scenario('permits repeated empty phones and different people with the same name', async () => {
      const name = { first_name: 'Maria', last_name: 'Santos', phone_no: '' };
      const first = await createUser(db, { email: 'first@example.com', metadata: name });
      const second = await createUser(db, { email: 'second@example.com', metadata: { ...name, phone_no: '  ' } });
      const third = await createUser(db, { email: 'third@example.com', metadata: { ...name, phone_no: '\u0085' } });
      assert.equal((await customerFor(db, first)).phone_no, null);
      assert.equal((await customerFor(db, second)).phone_no, null);
      assert.equal((await customerFor(db, third)).phone_no, null);
      assert.equal((await customerFor(db, first)).first_name, (await customerFor(db, second)).first_name);
      assert.equal((await claims(db)).filter((claim) => claim.kind === 'phone').length, 0);
    });

    await scenario('allows own profile updates but enforces one row for each Auth identity', async () => {
      const first = await createUser(db, {
        email: 'first@example.com', phone: '639171234567', verifiedPhone: true,
      });
      const customer = await customerFor(db, first);
      await db.query('update public.customers set email = $1, phone_no = $2 where id = $3',
        [' FIRST@example.com ', '09171234567', customer.id]);
      await signInAs(db, first);
      await db.query('select public.complete_customer_profile($1, $2, $3)',
        ['Maria', 'Santos', 'Updated address']);
      await db.exec('reset role');
      const updated = await customerFor(db, first);
      assert.equal(updated.id, customer.id);
      assert.equal(updated.address, 'Updated address');
      assert.equal(updated.phone_no, '+639171234567');
      await duplicate(db.query('insert into public.customers (auth_id) values ($1)', [first]));
    });

    await scenario('rejects duplicate profile edits and keeps saved contacts and claims', async () => {
      const first = await createUser(db, {
        email: 'first@example.com', metadata: { phone_no: '09171234567' },
      });
      const second = await createUser(db, {
        email: 'second@example.com', metadata: { phone_no: '09181234567' },
      });
      const before = await customerFor(db, second);
      const beforeClaims = await claims(db);
      await duplicate(db.query('update public.customers set email = $1 where auth_id = $2',
        [' FIRST@EXAMPLE.COM ', second]), 'email');
      await duplicate(db.query('update public.customers set phone_no = $1 where auth_id = $2',
        ['+639171234567', second]), 'phone number');
      assert.deepEqual(await customerFor(db, second), before);
      assert.deepEqual(await claims(db), beforeClaims);
      assert.ok(await customerFor(db, first));
    });

    await scenario('rejects duplicate Auth email, phone and metadata edits', async () => {
      await createUser(db, { email: 'first@example.com', phone: '639171234567' });
      const second = await createUser(db, { email: 'second@example.com', phone: '639181234567' });
      const before = (await db.query('select * from auth.users where id = $1', [second])).rows[0];
      await duplicate(db.query('update auth.users set email = $1 where id = $2',
        ['FIRST@example.com', second]), 'email');
      await duplicate(db.query('update auth.users set phone = $1 where id = $2',
        ['639171234567', second]), 'phone number');
      await duplicate(db.query("update auth.users set raw_user_meta_data = $1::jsonb where id = $2",
        [JSON.stringify({ phone_no: '09171234567' }), second]), 'phone number');
      assert.deepEqual((await db.query('select * from auth.users where id = $1', [second])).rows[0], before);
    });

    await scenario('allows name edits with stale signup phone metadata but rejects a new reused phone', async () => {
      const first = await createUser(db, {
        email: 'first@example.com', metadata: { first_name: 'Maria', phone_no: '09171234567' },
      });
      await db.query('update public.customers set phone_no = $1 where auth_id = $2',
        ['09181234567', first]);
      await createUser(db, { email: 'second@example.com', metadata: { phone_no: '09171234567' } });
      await createUser(db, { email: 'third@example.com', metadata: { phone_no: '09191234567' } });
      const updatedMetadata = { first_name: 'Mariana', phone_no: '09171234567' };
      await db.query('update auth.users set raw_user_meta_data = $1::jsonb where id = $2',
        [JSON.stringify(updatedMetadata), first]);
      await db.query('update auth.users set email = $1 where id = $2', ['updated@example.com', first]);
      await duplicate(db.query('update auth.users set raw_user_meta_data = $1::jsonb where id = $2',
        [JSON.stringify({ ...updatedMetadata, phone_no: '09191234567' }), first]), 'phone number');
      assert.deepEqual((await db.query('select raw_user_meta_data from auth.users where id = $1', [first]))
        .rows[0].raw_user_meta_data, updatedMetadata);
      assert.equal((await customerFor(db, first)).phone_no, '+639181234567');
    });

    await scenario('keeps archived identifiers reserved', async () => {
      const first = await createUser(db, {
        email: 'first@example.com', metadata: { phone_no: '09171234567' },
      });
      await db.query('update public.customers set deleted_at = now() where auth_id = $1', [first]);
      await duplicate(createUser(db, { email: 'FIRST@example.com' }), 'email');
      await duplicate(createUser(db, {
        email: 'second@example.com', metadata: { phone_no: '+639171234567' },
      }), 'phone number');
      await duplicate(db.query('insert into public.customers (auth_id) values ($1)', [first]));
      assert.equal((await claims(db)).length, 2);
    });

    await scenario('does not automatically claim an unowned customer or reassign an account', async () => {
      const legacy = (await db.query(`
        insert into public.customers (email, phone_no) values ($1, $2) returning id
      `, ['legacy@example.com', '09171234567'])).rows[0].id;
      await duplicate(createUser(db, { email: 'LEGACY@example.com' }), 'email');
      await duplicate(createUser(db, {
        email: 'new@example.com', metadata: { phone_no: '+639171234567' },
      }), 'phone number');
      const fresh = await createUser(db, { email: 'fresh@example.com' });
      await denied(db.query('update public.customers set auth_id = $1 where id = $2', [fresh, legacy]));
      await denied(db.query(`update public.customers set id = gen_random_uuid()${idType === 'text' ? '::text' : ''}
        where auth_id = $1`, [fresh]));
      await denied(db.query('update auth.users set id = gen_random_uuid() where id = $1', [fresh]));
      assert.equal((await db.query('select auth_id from public.customers where id = $1', [legacy])).rows[0].auth_id, null);
    });

    await scenario('releases claims only after the final owning source is removed', async () => {
      const first = await createUser(db, { email: 'first@example.com', phone: '639171234567' });
      await db.query('delete from public.customers where auth_id = $1', [first]);
      assert.equal((await claims(db)).length, 2);
      await duplicate(createUser(db, { email: 'FIRST@example.com' }), 'email');
      await db.query('delete from auth.users where id = $1', [first]);
      assert.deepEqual(await claims(db), []);
      const reused = await createUser(db, { email: 'first@example.com', phone: '639171234567' });
      await db.query('delete from auth.users where id = $1', [reused]);
      assert.equal((await claims(db)).length, 2);
      await duplicate(createUser(db, { email: 'first@example.com' }), 'email');
      await db.query('delete from public.customers where auth_id = $1', [reused]);
      assert.deepEqual(await claims(db), []);
      assert.deepEqual((await db.query('select * from repairshop_private.customer_identity_sources')).rows, []);
    });

    await scenario('retains an old contact while either owning table still uses it', async () => {
      const first = await createUser(db, { email: 'old@example.com' });
      await db.query('update auth.users set email = $1 where id = $2', ['new@example.com', first]);
      await duplicate(createUser(db, { email: 'old@example.com' }), 'email');
      assert.equal((await claims(db)).length, 2);
      await db.query('update public.customers set email = $1 where auth_id = $2', ['new@example.com', first]);
      assert.deepEqual(await claims(db), [
        { kind: 'email', canonical_value: 'new@example.com', owner_key: owner(first) },
      ]);
      await createUser(db, { email: 'old@example.com' });
    });

    await scenario('locks removed claims before a fresh final-source check and leaves no orphan reservations', async () => {
      // PGlite runs one PostgreSQL session. Inspect the installed locking order
      // here; separate concurrent transaction waits require a PostgreSQL server.
      const definition = (await db.query(`
        select pg_get_functiondef(
          'repairshop_private.replace_customer_identity_sources(text,text,text,text,text)'::regprocedure
        ) as definition
      `)).rows[0].definition;
      assert.match(definition, /from removed_sources order by kind, canonical_value/i);
      const lockStart = definition.indexOf('perform 1 from repairshop_private.customer_identity_claims');
      const cleanupStart = definition.indexOf('delete from repairshop_private.customer_identity_claims', lockStart);
      assert.ok(lockStart >= 0 && cleanupStart > lockStart);
      assert.match(definition.slice(lockStart, cleanupStart), /for update\s*;/i);
      assert.match(definition.slice(cleanupStart), /and not exists/i);

      const first = await createUser(db, { email: 'old@example.com', phone: '639171234567' });
      await db.query('update auth.users set email = $1, phone = $2 where id = $3',
        ['auth-new@example.com', '639181234567', first]);
      await db.query('update public.customers set email = $1, phone_no = $2 where auth_id = $3',
        ['customer-new@example.com', '09191234567', first]);
      await createUser(db, { email: 'OLD@example.com', phone: '639171234567' });
      assert.deepEqual((await db.query(`
        select claims.kind, claims.canonical_value
          from repairshop_private.customer_identity_claims as claims
          left join repairshop_private.customer_identity_sources as sources
            on sources.kind = claims.kind and sources.canonical_value = claims.canonical_value
          group by claims.kind, claims.canonical_value
          having count(sources.source_id) = 0
      `)).rows, []);
    });

    await scenario('does not reserve unverified metadata without a customer contact', async () => {
      await db.exec('alter table auth.users disable trigger handle_new_user');
      try {
        await createUser(db, { email: 'first@example.com', metadata: { phone_no: '09171234567' } });
      } finally {
        await db.exec('alter table auth.users enable trigger handle_new_user');
      }
      assert.equal((await claims(db)).filter((claim) => claim.kind === 'phone').length, 0);
      await createUser(db, { email: 'second@example.com', metadata: { phone_no: '09171234567' } });
      assert.equal((await claims(db)).filter((claim) => claim.kind === 'phone').length, 1);
    });

    await scenario('Auth hook checks contacts and only Auth administrators may call it', async () => {
      await createUser(db, { email: 'first@example.com', metadata: { phone_no: '09171234567' } });
      const event = { user: {
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', email: 'second@example.com',
        user_metadata: { phone_no: '+639171234567' },
      } };
      await signInAs(db, null, 'supabase_auth_admin');
      const result = (await db.query('select public.check_customer_account_creation($1::jsonb) as result',
        [JSON.stringify(event)])).rows[0].result;
      assert.equal(result.error.http_code, 400);
      assert.match(result.error.message, /phone number.*already associated/);
      await db.exec('reset role');
      for (const role of ['anon', 'authenticated']) {
        await signInAs(db, null, role);
        await denied(db.query('select public.check_customer_account_creation($1::jsonb)', [JSON.stringify(event)]));
        await denied(db.query('select * from repairshop_private.customer_identity_claims'));
        await denied(db.query('select repairshop_private.customer_email_key($1)', ['first@example.com']));
        await db.exec('reset role');
      }
      await signInAs(db, null, 'anon');
      await denied(db.query('select public.complete_customer_profile($1,$2,$3)', ['Maria', 'Santos', 'Address']));
      await db.exec('reset role');
    });

    await scenario('installs unique constraints and preserves stored sources on repeat migration', async () => {
      await createUser(db, { email: 'first@example.com', phone: '639171234567' });
      const beforeClaims = await claims(db);
      const beforeSources = (await db.query(`
        select * from repairshop_private.customer_identity_sources
          order by source_kind, source_id, kind, canonical_value
      `)).rows;
      await applyMigrations(db);
      assert.deepEqual(await claims(db), beforeClaims);
      assert.deepEqual((await db.query(`
        select * from repairshop_private.customer_identity_sources
          order by source_kind, source_id, kind, canonical_value
      `)).rows, beforeSources);
      const indexes = (await db.query(`
        select indexname, indexdef from pg_indexes where schemaname = 'public'
          and indexname in ('customers_one_auth_account_idx',
            'customers_unique_email_key_idx', 'customers_unique_phone_key_idx')
      `)).rows;
      assert.equal(indexes.length, 3);
      for (const index of indexes) assert.match(index.indexdef, /CREATE UNIQUE INDEX/);
      const constraints = (await db.query(`
        select c.contype, cl.relname from pg_constraint c join pg_class cl on cl.oid = c.conrelid
          join pg_namespace n on n.oid = cl.relnamespace
          where n.nspname = 'repairshop_private'
      `)).rows;
      assert.ok(constraints.some((c) => c.relname === 'customer_identity_claims' && c.contype === 'p'));
      assert.ok(constraints.some((c) => c.relname === 'customer_identity_sources' && c.contype === 'f'));
      assert.equal((await db.query(`
        select count(*)::integer as count from pg_trigger where not tgisinternal
          and tgname in ('enforce_customer_account_identity','release_customer_account_identity',
            'enforce_auth_customer_identity','release_auth_customer_identity')
      `)).rows[0].count, 4);
    });
  });
}

test('read-only audit reports counts for existing conflicts without customer details', async (t) => {
  const db = await createDatabase({ migrate: false, signupTrigger: false });
  t.after(() => db.close());
  const first = await createUser(db, {
    email: 'Owner@Example.com', phone: '639171234567', metadata: { phone_no: '09181234567' },
  });
  const second = await createUser(db, {
    email: 'other@example.com', metadata: { phone_no: '09171234567' },
  });
  await createUser(db, { email: 'invalid-auth@example.com', phone: '123' });
  await db.query(`
    insert into public.customers (auth_id, email, phone_no) values
      ($1, 'owner@example.com', '09171234567'),
      ($2, '\u00a0OWNER@EXAMPLE.COM\ufeff', '+639171234567'),
      ($1, 'third@example.com', '123')
  `, [first, second]);
  const results = (await db.query(await readProjectFile('supabase/audits/customer_account_uniqueness.sql'))).rows;
  const expected = {
    duplicate_customer_auth_groups: 1,
    duplicate_customer_email_groups: 1,
    duplicate_customer_phone_groups: 1,
    cross_account_email_conflict_groups: 1,
    cross_account_phone_conflict_groups: 1,
    invalid_customer_phone_rows: 1,
    invalid_auth_phone_rows: 1,
    contact_metadata_conflict_groups: 1,
  };
  assert.equal(results.length, Object.keys(expected).length);
  for (const row of results) {
    assert.deepEqual(Object.keys(row).sort(), ['check_name', 'problem_count']);
    assert.equal(Number(row.problem_count), expected[row.check_name]);
  }
  const output = JSON.stringify(results);
  for (const identifyingValue of ['Owner@Example.com', 'owner@example.com', '09171234567', first, second]) {
    assert.ok(!output.includes(identifyingValue));
  }
  await assert.rejects(applyMigrations(db), /Duplicate customer auth IDs exist/);
  await db.exec('rollback');
  assert.equal((await db.query("select to_regnamespace('repairshop_private') as schema")).rows[0].schema, null);
  assert.equal((await db.query('select count(*)::integer as count from public.customers')).rows[0].count, 3);
});

for (const idType of ['uuid', 'text']) {
  test(`backfills existing identities with ${idType} customer IDs and safely repeats`, async (t) => {
    const db = await createDatabase({ idType, migrate: false });
    t.after(() => db.close());
    const first = await createUser(db, {
      email: ' First@Example.COM ', phone: '639171234567',
      metadata: { phone_no: '09171234567' },
    });
    const beforeCustomer = await customerFor(db, first);
    await applyMigrations(db);
    const beforeClaims = await claims(db);
    assert.equal(beforeClaims.length, 2);
    assert.equal((await db.query('select count(*)::integer as count from repairshop_private.customer_identity_sources')).rows[0].count, 4);
    await applyMigrations(db);
    assert.deepEqual(await claims(db), beforeClaims);
    assert.deepEqual(await customerFor(db, first), beforeCustomer);
    assert.equal((await db.query('select count(*)::integer as count from repairshop_private.customer_identity_sources')).rows[0].count, 4);
    await duplicate(createUser(db, { email: 'first@example.com' }), 'email');
  });
}

test('cross-owner conflicts abort installation without merging or revealing contacts', async (t) => {
  const db = await createDatabase({ migrate: false, signupTrigger: false });
  t.after(() => db.close());
  await createUser(db, { email: 'private-owner@example.com' });
  const other = await createUser(db, { email: 'other@example.com' });
  await db.query('insert into public.customers (auth_id, email) values ($1,$2)',
    [other, 'PRIVATE-OWNER@example.com']);
  await assert.rejects(applyMigrations(db), (error) => {
    assert.equal(error.code, '23505');
    assert.match(error.message, /This email.*already associated/);
    assert.ok(!error.message.includes('private-owner@example.com'));
    return true;
  });
  await db.exec('rollback');
  assert.equal((await db.query("select to_regnamespace('repairshop_private') as schema")).rows[0].schema, null);
  assert.equal((await db.query('select count(*)::integer as count from public.customers')).rows[0].count, 1);
  assert.equal((await db.query('select count(*)::integer as count from auth.users')).rows[0].count, 2);
});
