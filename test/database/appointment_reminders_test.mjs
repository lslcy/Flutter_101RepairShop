import assert from 'node:assert/strict';
import { createDatabase, readProjectFile } from './helpers.mjs';

const db = await createDatabase({ migrate: false, signupTrigger: false });
let passed = 0;
try {
  await db.exec(`create table public.appointments (
    id serial primary key, title text, appointment_date date, time_slot text, status text
  ); insert into public.appointments(title, appointment_date, time_slot, status)
    values ('Existing repair', '2026-10-11', '8:00 AM - 9:00 AM', 'Pending');`);
  const migration = await readProjectFile('supabase/migrations/202610090004_appointment_reminders.sql');
  await db.exec(migration);
  assert.equal((await db.query('select reminder_minutes from public.appointments')).rows[0].reminder_minutes, null);
  console.log('PASS existing appointments keep reminders off'); passed++;
  for (const minutes of [1, 5, 15, 60, 1440, 10080]) {
    await db.query('update public.appointments set reminder_minutes = $1', [minutes]);
    assert.equal((await db.query('select reminder_minutes from public.appointments')).rows[0].reminder_minutes, minutes);
    console.log(`PASS reminder leadtime ${minutes}`); passed++;
  }
  for (const minutes of [-1, 0, 10081]) {
    await assert.rejects(db.query('update public.appointments set reminder_minutes = $1', [minutes]),
      error => error.code === '23514');
    console.log(`PASS rejects invalid reminder leadtime ${minutes}`); passed++;
  }
  await db.exec(migration);
  assert.equal((await db.query('select title, reminder_minutes from public.appointments')).rows[0].reminder_minutes, 10080);
  console.log('PASS reapplying migration preserves existing rows and valid preference'); passed++;
  console.log(`${passed} reminder migration checks passed.`);
} finally { await db.close(); }