-- Optional reminders selected by a customer when booking.
-- NULL keeps reminders off for all existing appointments.
begin;

alter table public.appointments
  add column if not exists reminder_minutes integer;

alter table public.appointments
  drop constraint if exists appointments_reminder_minutes_check;
alter table public.appointments
  add constraint appointments_reminder_minutes_check
  check (reminder_minutes is null or reminder_minutes between 1 and 10080);

comment on column public.appointments.reminder_minutes is
  'Minutes before the time-slot start in Asia/Manila; NULL disables the reminder. Delivery is scheduled locally on signed-in customer devices.';

-- Reconcile staff status/time changes while the customer app is connected.
-- Existing customer RLS still limits which appointments the client can receive.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'appointments'
    ) then
    alter publication supabase_realtime add table public.appointments;
  end if;
end;
$$;

commit;