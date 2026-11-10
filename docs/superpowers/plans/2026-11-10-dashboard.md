# Morgan Minecraft Dashboard Implementation Plan

**Goal:** Secure browser-based community and server management without disrupting Minecraft.
**Architecture:** Static React client → Supabase Auth and authorized database RPCs → durable command queue → outbound Ubuntu agent → local verified-TLS Crafty API. A separate Fabric module proves online-mode UUID ownership.
**Tech Stack:** React, TypeScript, Vite, PostgreSQL, Python, Java 21 / Fabric 1.21.1.
**Spec:** ../../requirements.md

## Global constraints
Free services only. No Ubuntu installation before separate approval. Keep online-mode=true. No arbitrary shell commands. No privileged browser keys. No invented metrics.

## Review focus
Expired commands; concurrent duplicate delivery; ambiguous Crafty responses after crashes; revoked membership with an old JWT; pairing-code theft and brute force.

## Milestones
1. Cloud eligibility and isolated repository. Inspect connected resources; create only a $0 project in the user-selected organization; create a new public repository for free Pages. Verify provider responses.
2. Agent safety core (`agent/control.py`, `agent/tests/test_control.py`). Write failing tests for expiry, strict action schemas, replay and crash recovery. Implement SQLite journal and typed operation validation. Run full unit suite. Never retry ambiguous execution automatically.
3. Database (`supabase/migrations`, `supabase/tests`). Generate migrations with CLI. Tables: profiles, servers, memberships, roles, permissions, role_permissions, identities, pairing_challenges, commands, audit_events, snapshots, backups, player_stats. RLS on all exposed tables. Identity ownership uses immutable UUIDs. Test role matrix and cross-user/cross-server denial using real PostgreSQL roles.
4. Auth and frontend (`src/auth`, `src/dashboard`, `src/admin`). Google primary; verified email/password secondary. PKCE callbacks on the Pages base path; pending accounts receive no operational permissions. Test recovery, OAuth errors, stale agent, inaccessible data and mobile navigation. No dashboard simulation data.
5. Crafty adapter and agent transport. Verify documented 4.11 API endpoints; pinned local CA; scoped agent credential; retry read-only operations with bounded backoff. Test against a fake HTTP server and then an explicitly approved installation. Start/stop dispatch must reconcile ambiguous outcomes.
6. Fabric integration (`fabric/`). Server-only commands /register, /link, /verify, /profile, /unlink; private feedback; single-use cryptographic challenges; local authenticated agent channel; fail closed when online-mode is false. Test protocol and challenge races separately; compile against exact pinned Minecraft/Fabric versions. No gameplay mixins.
7. Deployment and operations. CI executes frontend, Python, SQL and Java checks before Pages deployment. Configure Google provider without publishing secrets. Evaluate free SMTP without disabling verification. Document installation, rollback, recovery, retention and quota budgets. Verify a read-only end-to-end heartbeat before enabling controls.

## Execution record
- User explicitly approved implementation and opted out of further design gates.
- Workspace initially empty. GitHub connector has no repository-creation endpoint; browser fallback is authorized.
- Supabase organization selection pending because project-creation tool explicitly requires it.
- Ubuntu untouched. No claim of deployed or end-to-end operation until verified.
