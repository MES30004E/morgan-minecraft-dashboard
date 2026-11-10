# Testing and verification — exact commands and evidence

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Toolchain and fresh local results

CI uses Node24, Python3.12, PostgreSQL17, Java21, Gradle8.12. Python requirements.in pins supabase2.34.1 and cryptography50.0.2; install requirements.lock with hashes. No Docker or Minecraft process is required for frontend/Python/Java unit tests. macOS/Linux can use their existing approved runtimes; cloud runners recreate dependencies. The JDK/Gradle binaries are not the source backup and should be reinstalled from official vendors if missing.

Baseline before this handover had9 frontend tests. One requested branding test was first observed failing, then passed after minimal implementation: **10 frontend tests** now pass. Fresh **65 Python tests** pass. Fresh build/type-check, Java and CI evidence must be read from chapter17 and reports; do not turn a pending job into a pass. The previous source release CI42838407976 passed all existing workflows; that is historical evidence, not the fresh handover run.

```bash
# Frontend (macOS, Linux, cloud; Node24)
npm ci --ignore-scripts
npm test
npx --no-install tsc --noEmit
npm run build
npm audit
# Python, inside a local checkout; never a service install
python3.12 -m venv .venv
.venv/bin/python -m pip install --require-hashes -r agent/requirements.lock
PYTHONPATH=agent .venv/bin/python -m unittest discover -s agent/tests -v
# Fabric, approved local Java21/Gradle8.12 toolchain
gradle -p fabric test build --no-daemon --no-watch-fs
# Handover static consistency
python3 deploy/validate-handover.py
# Secret scan: official pinned Gitleaks8.30.1, no actual secret values in logs
gitleaks git . --log-opts=--all --config .gitleaks.toml --redact=100
git diff --cached --name-only
```

There is no standalone ESLint script/config currently; TypeScript is a type check, not a lint pass. No committed automated browser-E2E/axe/visual-baseline suite exists yet. Current browser checks use connected Chrome tools; proposed Playwright/axe coverage is explicitly planned in chapter16. Do not claim `npm run lint`, E2E or axe passes when scripts do not exist.

## Ephemeral database checks only

Use a disposable PostgreSQL17 database and never production for bootstrap/race fixtures. CI .github/workflows/database-tests.yml runs full authorization and the historical-bug baselines; Pages also gates deployment on all suites and the race test. Environment below is for an isolated locally created DB, never the Supabase production host:

```bash
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=dashboard_test
# Set PGPASSWORD privately for your disposable DB, if required.
psql -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap.sql
for migration in supabase/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -f "$migration"; done
for suite in supabase/tests/*.sql; do
  [ "$suite" = supabase/tests/bootstrap.sql ] || psql -v ON_ERROR_STOP=1 -f "$suite"
done
bash supabase/tests/revocation-race.sh
```

The9 suites are access_control, operations, pairing, archiving, replay, statistics, health, multi_server, observation. They use rolled-back fixtures; the concurrency shell test needs its own disposable DB. The regression-baseline job stops before replay_and_revocation_hardening and proves the old bugs fail. This handover only reads live Supabase state; fresh write-based DB tests run in ephemeral CI, preserving the live-service approval boundary.

## Scope and failures

Python tests exercise command envelope validation, at-most-once journal, ambiguous failure/recovery, wrong-server binding, read-only defaults, preflight identity/group checks, local socket replay, backup scans, archive crypto/interruptions/manifests/ACK/quota. SQL tests prove RLS/capability separation, pending/revoked users, cross-server isolation, role locks, pairing single-use/privacy, replay after retention and host gate denial. Java has2 protocol tests; it does not launch Minecraft or verify every in-game statistic/mod combination.

Initial unconfigured Gitleaks scan flagged2 reviewed public/synthetic values; a final clean scan uses narrowly documented exceptions. The Passport raw checkout generated AppleDouble pack-index warnings; canonical local clone uses internal Mac storage and external preservation uses a Git bundle. Record actual browser/layout failures and pending coverage in chapter16/17, not just successful screenshots.
