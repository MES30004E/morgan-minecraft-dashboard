#!/usr/bin/env bash
set -euo pipefail
# Committed fixtures are permitted only in the disposable CI database.
if [[ "${CI:-}" != true || "${PGDATABASE:-}" != dashboard_test ]]; then
  printf 'This test runs only in the isolated CI database.\n' >&2
  exit 1
fi
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id,email) values
('f1000000-0000-4000-8000-000000000001','race-owner-a@example.invalid'),
('f1000000-0000-4000-8000-000000000002','race-owner-b@example.invalid'),
('f1000000-0000-4000-8000-000000000003','race-member@example.invalid');
insert into public.servers(id,name,gameplay_address) values('f2000000-0000-4000-8000-000000000001','Race fixture','example.invalid');
insert into public.roles(id,server_id,name) values('f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','Owner');
insert into public.role_permissions values('f3000000-0000-4000-8000-000000000001','access.manage');
insert into public.memberships values
('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','approved'),
('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000001','approved'),
('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000003',null,'pending');
SQL
race_dir=$(mktemp -d)
trap 'rm -rf "$race_dir"' EXIT
PGAPPNAME=morgan_race_holder psql -v ON_ERROR_STOP=1 >"$race_dir/holder" 2>&1 <<'SQL' &
begin;
select id from public.servers where id='f2000000-0000-4000-8000-000000000001' for update;
update public.memberships set state='suspended' where user_id='f1000000-0000-4000-8000-000000000002';
select pg_sleep(8);
commit;
SQL
holder=$!
ready=false
for attempt in {1..60}; do
  if [[ $(psql -Atc "select count(*) from pg_stat_activity where application_name='morgan_race_holder' and wait_event='PgSleep'") == 1 ]]; then ready=true; break; fi
  sleep 0.05
done
[[ "$ready" == true ]]
PGAPPNAME=morgan_race_waiter psql -v ON_ERROR_STOP=1 >"$race_dir/waiter" 2>&1 <<'SQL' &
set role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000002',false);
select public.manage_member('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000003','approved','f3000000-0000-4000-8000-000000000001');
SQL
waiter=$!
blocked=false
for attempt in {1..60}; do
  if [[ $(psql -Atc "select count(*) from pg_stat_activity where application_name='morgan_race_waiter' and wait_event_type='Lock'") == 1 ]]; then blocked=true; break; fi
  sleep 0.05
done
[[ "$blocked" == true ]]
wait "$holder"
if wait "$waiter"; then
  printf 'Revoked owner performed a privileged operation.\n' >&2
  exit 1
fi
if ! grep -Eq 'Authorization revoked|Forbidden' "$race_dir/waiter"; then
  cat "$race_dir/waiter" >&2
  exit 1
fi
[[ $(psql -Atc "select state from public.memberships where user_id='f1000000-0000-4000-8000-000000000003'") == pending ]]
printf 'Concurrent permission revocation enforced.\n'
