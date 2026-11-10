# Frontend, UX and state handling

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Actual source

src/main.tsx owns Auth/session/account forms and PKCE return-route preservation. src/Fleet.tsx loads permitted resources, remembers only permitted selection and subscribes to visible fleet snapshots. src/Community.tsx loads server-specific views/permissions and handles idempotent request IDs, readiness, command queue feedback and reconciliation. src/servers.ts validates strict UUID/resource routes and bounds per-view queries. src/domain.ts handles freshness/durations; src/telemetry.ts preserves missing readings and gaps. Linking, Statistics and ServerConfiguration are separate views.

The MIT shadcn sidebar-07 adaptation is src/components/DashboardShell.tsx. Upstream primitives live in src/components/ui; notices/source hashes are retained in THIRD_PARTY_NOTICES.md and docs/ui-source-manifest.json. ConsolePanel filters/copies loaded lines and controls follow scrolling; it is not an arbitrary command terminal. MetricCharts is lazy loaded. Server controls/player operations are allowlisted and disabled unless readiness/lifecycle/capability conditions hold; backend authorization remains authoritative.

## Routing and account behavior

Routes use `#server/UUID/view` plus `#servers` and `#account`. Strict OAuth return routes reject arbitrary URLs; a valid incoming bookmark is restored after Google login. Local storage records theme and per-user permitted last server; storage failures must not confer permissions. Existing profile display names and personal server display names are preserved. Skip-to-content focuses main-content without changing the hash; only one main landmark exists.

## UI promises and limits

Neutral zinc dark theme, blue interactive accent, semantic status labels/dots, optional light mode, modest cards and consistent spacing. Do not use invented trend data, oversized marketing panels, emoji navigation, gradients or decorative controls. An offline agent does not imply an offline game. Unknown/stale/error/loading are distinct. Member views should never expose console/audit or metadata merely because a button is hidden.

Read-only backup metadata is not backup restore/download or scheduling. Restricted operations live on Overview/Players; no unrestricted console input exists. In-app notices are implemented; remote alerts are not. Player initials currently replace third-party avatar requests; actual Minecraft avatar sourcing remains a privacy-dependent gap. Broader device/long-content/keyboard coverage is documented in chapter16; a successful build is not a visual acceptance test.

## Branding configuration

src/branding.ts exposes displayName/APP_NAME. `VITE_APP_DISPLAY_NAME` is a **public build-time setting**, default Minecraft Console. Trimmed nonempty names up to 80 characters without control characters are accepted. Invalid/missing values use the neutral default. Never put secrets in VITE_* variables. Changing this name does not rename repositories, Supabase resources, Minecraft server names, UUIDs, migration/service paths, Java package names or archive protocol identifiers. See [branding inventory](15-BRANDING-AND-UI-REQUIREMENTS.md).
