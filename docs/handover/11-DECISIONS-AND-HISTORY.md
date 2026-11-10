# Decisions and implementation history

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Binding decisions and rationale

1. Retain Crafty; integrate through a narrow loopback HTTPS API. MCSManager/Pterodactyl/Pelican are comparison/UX references, not a replacement control plane. Their license/maintenance tradeoffs are in ../software-reuse.md. No source/world migration into a new manager.
2. Static Pages + Supabase fits browser-only/free-tier/CGNAT constraints. No paid domain, new SaaS backend, inbound agent port or arbitrary shell.
3. Google became primary after an earlier Discord-first idea. Email forms remain conditional on real mail delivery; Discord is optional. User consent authorized basic-profile OAuth publication and Owner enrollment historically; the next account must reconnect without reusing session secrets.
4. Website Auth, online-mode player UUID proof, membership approval and game admission remain separate. Submitted usernames cannot prove ownership. Hybrid/offline identities are deferred; no UUID/inventory migration.
5. Existing initial server identity was preserved when multi-server support was added. All resources, scoped workers, journals, archives, endpoints and identity associations are independent. Never conflate game/controller/resource IDs.
6. Durable at-most-once dispatch favors uncertain reconciliation over automatic retry. Revocation after server-lock waits and replay after operational retention were found and fixed with regression tests that fail on the historical baseline.
7. Retention requires verified encrypted local archive acknowledgements and row fingerprints. User approved7d commands/90d audit+backup metadata, local1y/2y/1y, snapshots and optional external mirrors. Failures retain cloud copies; quotas protect SSD and cloud budgets. Important daily security rollups remain.
8. shadcn/Radix/Tailwind reuse superseded earlier bespoke green/forest design. ../design-direction.md is historical, not the current visual authority. Official sidebar-07, restrained neutral dark/light and blue accent are current; MIT/ISC notices are preserved.
9. Read-only Stage A was made explicit after review found the old worker would consume immediately. Local/adapter/DB gates now default off; privileged preexisting service groups and stale fleet display were also corrected. Readiness does not itself grant authority.
10. Crafty actual online count differs from player-name sampling. New nullable count avoids false zero; naive timestamps do not establish uptime. Missing data and gaps remain unavailable.
11. Plan exact official Fabric1.21.1 artifact was not found. Do not substitute a newer game jar. Narrow identity bridge stays; broad analytics is deferred.
12. Handover adds neutral configurable display name and secret/ignore safeguards only. Repository/service/UUID/protocol identities and the personal Minecraft server display name remain stable. All new private operational facts stay outside public Git.

## Reachable Git implementation record at baseline

The following commit subjects were read from the full clone, not reconstructed from memory. The handover commit extends this history; resolve final HEAD in the final report/manifest instructions.

```
6178bf0 2026-11-10T18:30:50+08:00 Initial commit
1f1cecf 2026-11-10T18:32:53+08:00 Add tested durable agent safety core and implementation milestones
fe0ab1a 2026-11-10T18:41:14+08:00 Add deployed RLS authorization migration and database security tests
83fbf74 2026-11-10T18:53:22+08:00 Build Supabase account frontend and GitHub Pages deployment workflow
ee4e523 2026-11-10T19:56:30+08:00 Implement secure community operations, Fabric pairing and archive-gated retention
54fba3d 2026-11-10T20:00:36+08:00 Make concurrent revocation regression portable and test statistics privacy
6d70d3c 2026-11-10T20:19:08+08:00 Complete archive health, verified retention scheduling and reviewed installation plan
3017cc3 2026-11-10T20:22:42+08:00 Show RLS-protected player access details and cover archive foreign keys
c24ceeb 2026-11-10T20:24:48+08:00 Keep regression baseline at its historical migration boundary
9ce3842 2026-11-10T20:26:46+08:00 Keep account connection and mail-delivery states accurate
957b883 2026-11-10T20:30:34+08:00 Record approved Google OAuth production publication
66a4f99 2026-11-10T20:54:47+08:00 Support independent server resources, scoped agent routing and per-server identity verification
9848069 2026-11-10T21:01:10+08:00 Close equivalent-controller routing and suspended-metadata regressions
80006ba 2026-11-10T21:06:23+08:00 Bound multi-server heartbeat queries and align deployed migration history
a8ff695 2026-11-10T21:19:36+08:00 Preserve scoped sign-in bookmarks and expose configurable server capabilities
94f9e05 2026-11-10T22:38:09+08:00 Adopt shadcn control panel and gate Ubuntu observation stage
15d99d6 2026-11-10T22:41:22+08:00 Keep visible fleet telemetry current without polling
366f9ca 2026-11-10T22:47:59+08:00 Preserve actual online counts independently of player names
8d83416 2026-11-10T22:51:35+08:00 Refine mobile density and preserve routes on keyboard skip navigation

```

Public history contains existing operational identifiers/paths and intended publishable routing configuration; this handover minimizes new disclosure but does not claim old history was scrubbed. The initial source has no blanket project license assigned to the user's own code; retain third-party licenses. No destructive history rewrite was performed.

## Conversation limits

Accessible user briefs, this chat and prior release reports were reviewed. Some previous context was summarized and no complete transcript of every earlier setup conversation was available. Requested lid/power/DHCP/technical-mod/online-backup behaviors are preserved as requested/unverified, never invented as prior completed configuration.
