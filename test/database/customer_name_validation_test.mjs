import assert from 'node:assert/strict';
import { createDatabase, createUser, customerFor, readProjectFile, resetData } from './helpers.mjs';

const db = await createDatabase();
let passed = 0;
async function check(title, body) {
  await resetData(db);
  await body();
  passed++;
  console.log(`PASS ${title}`);
}
async function valid(value) {
  return (await db.query('select repairshop_private.customer_name_is_valid($1) as valid', [value])).rows[0].valid;
}
async function rejected(query, parameters, code = '23514') {
  await assert.rejects(db.query(query, parameters), error => error.code === code);
}
try {
  await db.exec(await readProjectFile('supabase/migrations/202610090003_customer_name_validation.sql'));
  for (const value of ['Alex', 'José', 'Jose\u0301', 'María-José', "O'Neill", 'D’Angelo', 'Ñez', '李明', '김민수', 'أحمد', 'अनिल', 'J. P.', 'A'.repeat(100)]) {
    await check(`accepts valid Unicode name ${passed + 1}`, async () => assert.equal(await valid(value), true));
  }
  for (const value of [null, '', ' ', '123', 'Alex12', 'Alex🙂', '<script>', "';drop table", '---', '.', '\u0301Alex', 'A \u0301', 'Alex\nReyes', 'Alex\tReyes', 'Alex\u0085Reyes', 'A'.repeat(101), 'Alex\u200d']) {
    await check(`rejects invalid name ${passed + 1}`, async () => assert.equal(await valid(value), false));
  }
  await check('normalizes surrounding and repeated Unicode whitespace', async () => {
    const result = await db.query('select repairshop_private.normalize_customer_name($1) as name', ['\u00a0 José  Luis \u00a0']);
    assert.equal(result.rows[0].name, 'José Luis');
  });
  await check('signup rejects invalid metadata without creating an account', async () => {
    await assert.rejects(createUser(db, {email:'name@example.test', metadata:{first_name:'Alex123',last_name:'Reyes'}}), error => error.code === '23514');
    assert.equal((await db.query('select count(*)::int as total from auth.users')).rows[0].total, 0);
    assert.equal((await db.query('select count(*)::int as total from repairshop_private.customer_identity_claims')).rows[0].total, 0);
  });
  await check('Google and phone signup allow missing metadata names until completion', async () => {
    const user = await createUser(db, {phone:'639171234567', verifiedPhone:true});
    assert.equal((await customerFor(db,user)).first_name, null);
  });
  await check('different customers may use the same full name', async () => {
    for (const email of ['first@example.test','second@example.test']) {
      await createUser(db, {email,metadata:{first_name:'Alex',last_name:'Reyes'}});
    }
    assert.equal((await db.query('select count(*)::int as total from public.customers')).rows[0].total, 2);
  });
  await check('invalid direct profile edit preserves the existing name', async () => {
    const user = await createUser(db, {email:'existing@example.test',metadata:{first_name:'Alex',last_name:'Reyes'}});
    await rejected('update public.customers set first_name=$1 where auth_id=$2', ['Alex77',user]);
    assert.equal((await customerFor(db,user)).first_name, 'Alex');
  });
  await check('profile edits normalize names without using names for uniqueness', async () => {
    const user = await createUser(db, {email:'edit@example.test',metadata:{first_name:'Alex',last_name:'Reyes'}});
    await db.query('update public.customers set first_name=$1 where auth_id=$2', [' José  Luis ',user]);
    assert.equal((await customerFor(db,user)).first_name, 'José Luis');
  });
  await check('verified profile RPC validates names and keeps address required', async () => {
    const user = await createUser(db, {phone:'639171234567',verifiedPhone:true});
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
    await rejected('select public.complete_customer_profile($1,$2,$3)', ['Alex3','Reyes','10 Mabini Street']);
    await rejected('select public.complete_customer_profile($1,$2,$3)', ['Alex','Reyes',' '],'22023');
    await db.query('select public.complete_customer_profile($1,$2,$3)', [' José  Luis ','D’Angelo',' 10 Mabini Street ']);
    const saved=await customerFor(db,user);
    assert.equal(saved.first_name,'José Luis');
    assert.equal(saved.last_name,'D’Angelo');
    assert.equal(saved.address,'10 Mabini Street');
  });
  await check('unverified profile cannot be completed', async () => {
    const user = await createUser(db, {email:'pending@example.test'});
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
    await rejected('select public.complete_customer_profile($1,$2,$3)', ['Alex','Reyes','10 Mabini Street'],'42501');
  });
  await check('name migration can be installed again without changing existing values', async () => {
    const user=await createUser(db,{email:'repeat@example.test',metadata:{first_name:'Alex',last_name:'Reyes'}});
    await db.exec(await readProjectFile('supabase/migrations/202610090003_customer_name_validation.sql'));
    assert.equal((await customerFor(db,user)).first_name,'Alex');
  });
  console.log(`${passed} database name checks passed.`);
} finally {
  await db.close();
}