# Deployment, recovery and maintenance

## Cloud deployment

GitHub Actions publishes the static Vite build from `main` after frontend, Python, PostgreSQL authorization and Fabric build checks. `implementation-verification` exercises independent workflows before promotion. Apply schema changes as reviewed forward migrations through the Supabase plugin/CLI; match hosted migration versions. Public configuration contains only the project URL and publishable key. OAuth secrets remain in Supabase's provider configuration; Crafty and archive secrets exist only on Ubuntu after installation.

Google OAuth uses the dedicated Morgan project and only basic profile/email scopes. Owner login and profile editing were tested on the live Pages origin. Google's audience is published and the console shows In production. Homepage and public privacy URL are configured in Google branding. The privacy notice is `/morgan-minecraft-dashboard/privacy.html`. Default Supabase SMTP is restricted and unsuitable for friends; password signup/reset code exists but delivery is **not configured or verified**. Use Google sign-in initially. Do not remove email verification as a workaround. Leaked password detection is a paid Supabase feature and remains unavailable under this free-only deployment.

## Budgets and limits

Supabase Free currently includes 500 MB database, 5 GB egress, 2 million Realtime messages/month and 200 peak Realtime connections. Free projects may pause after inactivity. Confirm limits in the provider console before expanding usage: https://supabase.com/pricing and https://supabase.com/docs/guides/platform/billing-on-supabase . GitHub Pages/Actions use a public repository and no paid domain. Do not enable billable branching or upgrades.

The agent publishes roughly once per minute, with Realtime command wakeups and a bounded 60-second recovery check. It backs off on disconnect; the frontend unsubscribes when hidden. Console/history refresh is explicit instead of downloading on every heartbeat. A 60-second snapshot is about 43,200 updates/month; fan-out to many viewers multiplies messages and egress. Keep console uploads disabled until needed. Statistics export every five minutes is separate; archive batches are bounded and daily. Monitor actual usage rather than treating estimates as guarantees.

Cloud operation limits include per-user/per-server minute limits, 200 server operations/day, an audit row guard, a 400 MB database guard and a 100,000-request replay ledger cap. Guards intentionally fail closed; do not bypass them without reviewing growth. Compact replay tombstones are retained permanently to prevent old IDs being reused after operational logs expire. Important security events retain daily count/hash rollups rather than personal payloads. These structures grow slowly but are not unlimited; review annually.

Nightly cloud housekeeping runs at 18:20 UTC (02:20 Singapore). Commands (7 days), audits (90 days) and backup metadata (90 days) are deleted **only with acknowledged matching full-row fingerprints**. Expired pairing challenges are purged after one extra day. Uncertain commands, memberships, permissions, statistics, worlds and actual backups are preserved. Offline agent/archive failure therefore increases cloud storage rather than losing history; respond to archive health alerts and provider usage warnings promptly.

Local archives use 1 GiB quota with a 64 MiB free-space reserve, encrypted content and authenticated manifests. Commands/backup metadata/snapshots retain a year, audits two years. Pending/unverified exports never auto-expire. Inspect disk usage weekly, test recovery quarterly and keep the recovery key copy away from the SSD. Automatic primary pruning does not prune optional external mirrors. The UI shows archive errors/quota pressure after the agent is installed. There is no separately configured email/push alert service.

## Routine updates and incidents

Review dependency advisories monthly; update pins and lockfiles, run all checks and record the deployed commit. Rehearse a staging restore before major schema changes. Free project hosting and operational archives are not a complete database or Minecraft world backup. Preserve Crafty's existing six-hour archives, and independently test restoring a copied world into an isolated server.

If the control agent is compromised, stop it, revoke `private.agents` registration, revoke its Auth sessions and Crafty token, rotate bridge and archive keys using a reviewed migration plan, and retain old archive keys for old ciphertext. Database privileges stay server-side. If account permissions are wrong, suspend the membership using Owner access; the database rechecks authorization after its server lock. Use another trusted Owner or the Supabase project administrator for lockout recovery.

For ambiguous commands inspect Crafty and the persistent SQLite journal; use the Owner reconciliation form with a factual note. Never automatically retry a command marked uncertain. If Pages breaks, revert to the previous tested source commit and redeploy. Schema rollback uses reviewed forward repairs; never drop production tables to match older UI code. Keep supported old RPCs during compatible rollouts.

## Optional hybrid authentication

Initial deployment requires normal Mojang online authentication. EasyAuth's upstream documentation describes Fabric/premium/offline modes, but this does not establish safe compatibility with this exact server and bridge. Do not toggle online-mode, replace UUIDs, migrate player data or install hybrid authentication in production under this plan. A later project must establish authenticated player attestation, namespace collision protection, operator/whitelist handling, and test copied worlds in isolation before enabling website linking for hybrid identities. No Minecraft gameplay/redstone mechanics are changed by this dashboard module.
