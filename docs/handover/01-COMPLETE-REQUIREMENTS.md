# Complete requirements and provenance

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Binding constraints

Use only existing free GitHub Pages, Supabase Free, existing hardware/Crafty and playit services. Friends need a browser and a compatible Minecraft client, with no VPN, compulsory Discord app or client mod. No public SSH/Crafty/RCON, inbound agent listener, Docker socket, arbitrary shell, frontend privileged credentials or invented data. Do not create another repository or Supabase project. Preserve worlds, player UUIDs, inventories, current backups and technical redstone behavior.

## Evidence provenance and precedence

This inventory uses the initial dashboard request, accessible website-first/Google implementation brief, multi-server brief, approved archive-retention extension, reuse/redesign/staged-integration brief, this complete handover request, current Git history/source/tests/migrations and existing release reports. Some earlier assistant turns survive only as a summarized conversation; no complete chat export or inaccessible earlier host-setup conversation was available. Missing facts remain Unknown. The new handover request explicitly introduces/refines host-operation, Orbital Strike Cannon, UI compatibility and branding requirements; they are not retroactively claimed implemented.

Google supersedes an earlier Discord-first idea. Email remains secondary with public SMTP unconfigured; Discord is optional future work. Website authentication, game identity proof, membership approval and in-game admission are separate. Initial game identity assumes online-mode=true; unofficial/hybrid clients require a separate threat model and approved UUID-preserving migration. No offline-mode switch is authorized.

## Exhaustive inventories

[feature-traceability.csv](feature-traceability.csv) contains every A–G feature enumerated in the handover brief and additional requirements recovered from earlier requests. Each row records requested/designed/code/unit/integration/deployed/live/E2E separately, source paths, symbols, dependencies, permissions, risks and remaining work. Infrastructure facts are external dependencies, not magically implemented by dashboard source. An external user-reported setup is not counted as a fresh end-to-end test.

Infrastructure includes continuous hosting, reboot recovery, Ethernet/Wi-Fi, DHCP, CGNAT/playit, lid/power/battery/thermal behavior, monitoring/alerts and budgets. Minecraft includes Java/Fabric versions, exact technical-mod compatibility, AFK farms, redstone/Orbital Strike Cannon, mod optimization, MOTD/icon, maintenance warnings and world preservation. The web covers multi-server routes, health/graphs, console, controls, backups/schedules, accounts/ACL/audit, notifications, accessibility and all devices. Auth/identity/statistics/archives/security are detailed in their chapters and each CSV row.

## Acceptance rules

Implemented ≠ tested ≠ deployed ≠ connected ≠ operational. A compiled mod does not prove gameplay compatibility. First-recorded statistics do not prove first-ever join or full join history. Backup metadata is not backup creation/restore or proven world consistency. A 390px viewport is not an iPhone. No broad device or WCAG conformance claim is made. Retain all unimplemented requests in the roadmap instead of deleting or silently downgrading them.
