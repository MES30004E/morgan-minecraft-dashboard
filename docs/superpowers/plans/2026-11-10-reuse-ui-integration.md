# Reuse, professional UI and staged integration implementation plan

> Execute inline using Superpowers executing-plans, TDD for behavior/security changes, one independent whole-change review before release.

Goal: retain Crafty and the verified multi-server security core, adopt upstream accessible UI components, and prepare a genuinely read-only Stage A without installing anything on Ubuntu.
Spec: user brief supplied 10 Nov 2026; decisions and primary sources in docs/software-reuse.md.

Constraints: same repository/Supabase project/free services; no live Crafty credentials, Ubuntu services, mounts, world changes, restarts, network changes or mod installation. Unknown Docker mappings, service identity and certificate facts stay unknown. Existing authentication, routes, permissions, journals and archive gate remain.

- [ ] Audit: complete six-project comparison, exact Plan artifact check, installation code review and source/notice manifest. Lock official shadcn sidebar-07 and compact console patterns.
- [ ] Stage A safety: write failing Python/SQL read-only tests; add default-off local control flag, adapter and worker guards, host-admin database control gate, readiness reporting, corrected installer/preflight and read-only host inventory script. Test control fixtures explicitly opt in; original revocation/replay tests remain intact.
- [ ] Bounded telemetry: add RLS-protected 15-minute real readings, maximum one day of active samples, no polling or fabricated chart data. Test writer and cross-server denial; add actual-value chart preparation tests.
- [ ] UI: official shadcn registry components/Radix/Tailwind and notices; restructure into compact fleet/server/account pages with responsive sidebar/selector, accessible confirmation dialogs, terminal log filtering/copy, player profiles, real-data charts, backups and scoped access/settings. Preserve strict routes/OAuth return handling.
- [ ] Review and verify: frontend/Python/database/Java tests, npm audit, independent review, cloud migration/deploy, desktop/390px browser screenshots, real OAuth/routes/permission-menu smoke checks. Report live vs simulated boundaries.
- [ ] Handoff: corrected pinned Stage A installation commands, credential/certificate/mount preflight requirements, rollback and separate Stage B/C approval steps; stop before Ubuntu deployment.

Review focus: readonly bypass through legacy RPCs; stale selection/permission data; mixed-mode multiple servers; metrics or console usage growth; installation ownership/paths and unexpected existing service users; offline-network recovery without repeated execution.

Ledger: initial audit found current service starts a command consumer immediately; Stage A must fail closed in Python and PostgreSQL. Supplied Crafty GitHub URL is 404; canonical GitLab identified. No verified Plan Fabric 1.21.1 artifact found; do not install a newer incompatible build. Application builders were inspected but no replacement project was created.

Verification checkpoint: independent review found stale fleet age and unexpected service groups; both fixed. 9 frontend and 64 Python tests pass, Java 21 Gradle test/build succeeds, npm audit reports zero known vulnerabilities. All 9 SQL suites passed with proposed schema in a rolled-back transaction. Applied hosted migration 20261110143649; no agent bindings/commands enabled. Browser deployment QA remains before completion.

Final API contract check: Crafty online counts are independent of names. Added nullable RLS-protected count, batched scoped ingestion and missing-value handling; Python RED→GREEN and extended SQL suite RED→GREEN passed. 65 Python tests now pass. Reviewer confirmed no authority regression. Hosted migration 20261110144701 applied; all9SQL suites passed again after apply.
