# Feature status matrix and evidence semantics

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Machine-readable matrix

The complete matrix is [feature-traceability.csv](feature-traceability.csv), with **191** independent feature rows and 22 evidence fields. [coverage-summary.json](coverage-summary.json) reports strictly counted fields; “Yes” is counted only when a field starts with Yes. Partial, historical, external and unknown statuses are not promoted to Yes. Counts are overlapping evidence dimensions, not mutually exclusive completion buckets. Every row retains remaining validation or work.

| Subsystem | Code | Test evidence | Deployment / operational boundary |
|---|---|---|---|
| Google account and approved server membership | Implemented | Historical real OAuth; current browser session and SQL fixtures | Cloud live; first/new-account edge cases not all rerun |
| Email/password | Forms and Supabase calls | Route/code tests only | Public mail delivery not configured |
| Roles, granular grants, multi-server isolation | Implemented | 9 SQL suites + concurrency CI, Python scoped tests | Cloud live; physical second-server control unverified |
| Server telemetry and count | Implemented | Snapshot/parser/missing-value/RLS fixtures | No real agent uploads; uptime intentionally unavailable |
| Start/stop/restart/moderation | Implemented | Queue/journal/failure/revocation fixtures | No game command has been executed |
| Console | Read-only bounded opt-in | Redaction and permission fixtures; historical empty UI | No real logs uploaded |
| Backup/schedule UI | Metadata viewer only | Scan fixtures; actual six-hour Crafty schedule historically observed | No backup CRUD/schedule manager or proven online-world restore |
| Identity bridge/statistics | Implemented narrow Fabric module | Java protocol and SQL privacy/pairing fixtures | Not installed in Minecraft |
| Archive-gated retention | Implemented | Encryption/fault/ACK/quota tests | Cloud cron live; no Ubuntu archive service/export yet |
| Broad browser/accessibility coverage | Plan plus available Chrome checks | See exact per-case results | No claim of Firefox/WebKit or physical mobile verification |

## Important gaps

Live status remains Unknown because there are zero bindings/snapshots. Operational alert delivery is not implemented; in-app notices are not push/email monitoring. Complete join/session history and Minecraft avatars are not implemented. Exact Carpet/TIS/Orbital Strike Cannon and optimization compatibility, safe online backups, lid/power/battery/thermal settings, DHCP reservations and physical recovery need host research/approval. Rich starting/stopping/restarting/crashed/backing-up states are not an established runtime contract (current adapter maps online/offline/unknown). See [roadmap](12-ROADMAP-AND-OUTSTANDING-WORK.md).

## Reading source references

CSV paths are repository-relative; functions/RPCs identify the relevant subsystem and do not imply every behavior has an individual unit test. “SQL fixtures” means authenticated-role/JWT-claim fixture execution, not a real friend's Google login. Existing historical docs may describe earlier design states; [decisions/history](11-DECISIONS-AND-HISTORY.md) explains supersession without deleting them.
