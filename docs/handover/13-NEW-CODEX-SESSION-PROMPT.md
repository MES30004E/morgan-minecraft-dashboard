# Copy this prompt into the new Codex account

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

```text
Continue the existing Minecraft server dashboard project without the previous ChatGPT account or conversation.

Canonical repository: https://github.com/MES30004E/morgan-minecraft-dashboard
Live Pages: https://mes30004e.github.io/morgan-minecraft-dashboard/
Last source baseline before the handover: 8d83416bca89623ce6ea8307e35ececb81a20c1b.
That is a reference, not a fixed current HEAD. Inspect git remote HEAD, handover commit, local status and CI before editing. Do not create another repository or Supabase project.

First read every docs/handover/ chapter starting with 00-START-HERE.md, feature-traceability.csv, project-manifest.json, source-inventory.json and final validation. Read existing docs/integration-audit.md, ubuntu-installation.md, multi-server.md, archives.md, maintenance.md, cloud-status.md and software-reuse.md. Historical design docs may be superseded. Preserve the complete feature backlog, source/history, journals, archive behavior and recovery instructions. Implemented, unit-tested, integration-tested, deployed and operational are separate statuses.

Architecture is React/TypeScript/Vite + GitHub Pages, Supabase Auth/Postgres/RLS/RPC/Realtime, outbound Python agent, existing Crafty Docker process manager and optional server-side Fabric1.21.1 identity bridge. No hosted middleware app or new manager is needed. Keep free tiers only. Use existing upstream shadcn/Radix/Tailwind/Lucide/Recharts with notices. Neutral APP_NAME is configurable publicly at build time; do not rename the GitHub repo, services, UUIDs, migration paths or the user's actual server display name.

Connect GitHub and Supabase using this account's own plugins and explicit owner login/consent. Do not copy old cookies/tokens, use an old Owner password, request service-role keys for the frontend/agent or assume previous browser/SSH/file access transfers. Verify only the existing Minecraft Supabase project and its15 recorded migrations (then inspect any newer migrations). Read-only cloud counts at handover were zero bindings/commands/snapshots/metric samples, two server configs and active nightly verified retention. Recheck actual current counts and RLS before claiming live state. Public email SMTP was not configured; Google is primary. Never bypass email verification.

Private operational notes and a private index exist outside the Git tree in the owner's local protected folder, if that handover location is available. Ask for only the minimal facts needed, never upload the entire folder automatically, and never collect/export passwords, SSH keys, OAuth/client secrets, service-role keys, Crafty tokens, session material or archive master keys without separate approval and encryption. Verify local paths/modes and sync risks. Public Git must contain only sanitized code/docs/fixtures. A Git bundle is source history, not a backup of live Auth/database/worlds/keys.

Highest-priority next engineering milestone is Stage A observation-only connection to the actual Ubuntu/Crafty server. This handover DID NOT authorize host installation, service starts, new live Crafty credentials, Docker/mount changes, mods, server properties, game restart, backup schedule changes, network routing or world writes. Revalidate actual host inventory, controller/resource mapping, numeric service groups, stats-only token model, CA provenance/SAN, disk reserve and archive-key recovery. Prepare a concrete reviewed plan and obtain explicit approval before any host-changing action.

Keep local controls_enabled=false and private binding control_enabled=false for Stage A. Worker/adapter/legacy+scoped DB gates must stay fail closed. A heartbeat does not authorize control. Stage B needs separate control approval and a maintenance window for stop/restart. Stage C needs approved exact Fabric API/mod/socket/key/group/mount changes; online-mode stays true, UUIDs/inventories unchanged. Stage D physical second-server validation is separate. No verified exact Plan Fabric1.21.1 artifact was found; do not substitute a newer jar. Never invent game online status or statistics.

Recreate pinned development dependencies and run actual tests. Baseline had9 frontend and65Python tests plus9SQL suites/concurrency and2Java protocol tests; branding adds one frontend test. Use the current validation chapter for actual final results. Run ephemeral PostgreSQL17 fixtures, not production bootstrap; live-service tests need separate approval and isolated identities. Read the full device/browser/fault matrix and record gaps/failures. A viewport is not physical mobile testing; build success is not deployed or operational success.

Preserve granular server-specific permissions, revocation locking, unique request replay ledger, command expiry/claim tokens, at-most-once journal and uncertain reconciliation. No arbitrary shell, Docker socket, inbound agent Internet listener, public SSH/Crafty/RCON or privileged browser secrets. Archive before deletion: verified encrypted local records, counts/checksums/manifests and authenticated ACK/fingerprint; unresolved commands survive. Retain approved TTLs/quotas and separate encrypted recovery copies.

Report findings and concrete changes concisely. Continue autonomously on safe repository/cloud inspection and preparation, but stop at the explicit Ubuntu approval boundary. Do not treat this prompt as permission to operate the live Minecraft server. Never silently discard unimplemented features or claim full operational completion from fixtures.
```

The prompt intentionally contains no private host addresses, personal email, passwords or session material. Provide private operational facts only as needed after the new session's identity/access is established. Use [connections checklist](14-CONNECTIONS-AND-SECRETS-CHECKLIST.md) and [recovery](10-DEPLOYMENT-AND-RECOVERY.md).
