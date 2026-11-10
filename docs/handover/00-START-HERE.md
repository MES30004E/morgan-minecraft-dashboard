# Start here — recover the project without this chat

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Canonical resources and current boundary

Repository: https://github.com/MES30004E/morgan-minecraft-dashboard . Frontend: https://mes30004e.github.io/morgan-minecraft-dashboard/ . Source baseline inspected: `8d83416bca89623ce6ea8307e35ececb81a20c1b`. Do not assume it remains HEAD: `git ls-remote origin refs/heads/main` and inspect the new commit/diff. Public repository identity is intentionally unchanged despite neutral product branding.

Read [requirements](01-COMPLETE-REQUIREMENTS.md), [status matrix](02-FEATURE-STATUS-MATRIX.md), [architecture](03-ARCHITECTURE.md), [roadmap](12-ROADMAP-AND-OUTSTANDING-WORK.md), then [next-session prompt](13-NEW-CODEX-SESSION-PROMPT.md). There are **191** traceable feature requirements. The detailed fault/compatibility matrix is separate from feature completion. All chapters are indexed below.

**The cloud/UI exist; the Ubuntu agent is not installed.** Inspection during this handover found zero agent bindings, zero game commands, zero snapshots and zero metric samples. Two dashboard configurations exist (one active and a prior soft-removed validation resource). Supabase is ACTIVE_HEALTHY with 15 migrations and about 14.5 MiB database usage. Unknown status is correct; never insert fake telemetry to make screenshots look complete.

Crafty remains the authoritative process manager. No Ubuntu installation, credentials, Docker mounts, mods, server properties, game restart, backup schedule, routing or world-file changes are authorized by this handover. Stage A observation requires separate approval. Stage B control requires separate approval and a game maintenance window. Stage C mods/socket integration and Stage D physical multi-server checks remain separate.

## Recover a development checkout

```bash
git clone https://github.com/MES30004E/morgan-minecraft-dashboard.git
cd morgan-minecraft-dashboard
git log -1 --oneline
node --version  # CI uses Node 24
npm ci --ignore-scripts
npm test
npm run build
```

Python requires 3.11+ (CI 3.12), hash-pinned dependencies; Java/Fabric requires Java 21 and Gradle 8.12. See exact commands in [testing](09-TESTING-AND-VERIFICATION.md). Dependencies and caches are recreatable; they are not the backup of record.

## Public versus private recovery

Public code, migrations, docs and reachable history are in GitHub and a full local clone/Git bundle. The protected local operational index is **outside this repository**. No password, session cookie, SSH key, OAuth secret, service-role key, Crafty token or archive master key was exported. The next ChatGPT account must reconnect GitHub/Supabase and authenticate independently; no previous account or browser session is required for public recovery. Use [connections checklist](14-CONNECTIONS-AND-SECRETS-CHECKLIST.md), and supply only the minimum necessary private facts manually.

## Document index

- [01-COMPLETE-REQUIREMENTS.md](01-COMPLETE-REQUIREMENTS.md)
- [02-FEATURE-STATUS-MATRIX.md](02-FEATURE-STATUS-MATRIX.md)
- [03-ARCHITECTURE.md](03-ARCHITECTURE.md)
- [04-SUPABASE-AND-DATABASE.md](04-SUPABASE-AND-DATABASE.md)
- [05-FRONTEND-AND-UX.md](05-FRONTEND-AND-UX.md)
- [06-UBUNTU-INFRASTRUCTURE.md](06-UBUNTU-INFRASTRUCTURE.md)
- [07-AGENT-AND-FABRIC.md](07-AGENT-AND-FABRIC.md)
- [08-SECURITY-AND-THREAT-MODEL.md](08-SECURITY-AND-THREAT-MODEL.md)
- [09-TESTING-AND-VERIFICATION.md](09-TESTING-AND-VERIFICATION.md)
- [10-DEPLOYMENT-AND-RECOVERY.md](10-DEPLOYMENT-AND-RECOVERY.md)
- [11-DECISIONS-AND-HISTORY.md](11-DECISIONS-AND-HISTORY.md)
- [12-ROADMAP-AND-OUTSTANDING-WORK.md](12-ROADMAP-AND-OUTSTANDING-WORK.md)
- [13-NEW-CODEX-SESSION-PROMPT.md](13-NEW-CODEX-SESSION-PROMPT.md)
- [14-CONNECTIONS-AND-SECRETS-CHECKLIST.md](14-CONNECTIONS-AND-SECRETS-CHECKLIST.md)
- [15-BRANDING-AND-UI-REQUIREMENTS.md](15-BRANDING-AND-UI-REQUIREMENTS.md)
- [16-DEVICE-BROWSER-AND-EDGE-CASE-TESTING.md](16-DEVICE-BROWSER-AND-EDGE-CASE-TESTING.md)
- [17-HANDOVER-VALIDATION.md](17-HANDOVER-VALIDATION.md)
- [Machine-readable feature traceability](feature-traceability.csv)
- [Public project manifest](project-manifest.json)
- [Source inventory](source-inventory.json)

Dates, fixtures, deployed state and physical observations are distinct evidence classes. See final validation for tests actually rerun; historical results alone are not fresh verification.
