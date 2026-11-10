# Python agent and Fabric bridge

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Python entry points and safety

agent/main.py: serve authenticates the dedicated identity, creates scoped server loops, batches metrics, backs off/reconnects and handles graceful shutdown. server_loop partitions state/journal/archive roots, publishes bounded health, optionally scans backup metadata/uploads console and starts the bridge only when explicitly enabled. Read-only mode skips command recovery/dispatch, console/backup/bridge later-stage paths. agent/server_config.py validates local mappings and rejects duplicate/equivalent Crafty targets and unsafe legacy state layouts.

agent/control.py: validate accepts only start, stop, restart, kick, ban, pardon, whitelist_add/remove, canonical IDs, unexpired finite timestamps and exact safe username arguments. Journal uses SQLite WAL plus synchronous FULL; dispatch marks uncertain before a side effect and completed after accepted execution. Worker checks scoped returned commands and claim tokens, fences stale authorization and does not execute when execute_enabled is false. Crafty uses loopback verified HTTPS only, refuses redirects, limits response size, redacts known credential/pairing lines and defaults read_only=true.

A crash after Crafty accepts but before journal completion stays uncertain; an owner must inspect Crafty and record evidence with resolve_uncertain. Never clear the journal or blindly enqueue the same action to force a retry. Expired/duplicate/wrong-server commands must fail closed. Existing recovery APIs and request tombstones survive operational record retention.

## Fabric protocol and exact artifact

fabric/build.gradle pins Minecraft1.21.1, Fabric Loader0.20.1, Fabric API0.116.18+1.21.1, Java21, Loom1.9.2, Gradle8.12 and JUnit5.11.4. IdentityBridge implements /register, /link, /verify, /profile and confirmed /unlink; game UUID comes from the authenticated server player, not website input. It refuses non-online-mode identities. BridgeProtocol authenticates messages/responses with per-server secrets, nonces and timestamps over a Unix socket; the Python gateway bounds messages/concurrency and protects replay state. No client mod is required by design.

Statistics read existing counters at join/disconnect and every6000ticks (~5min only at20TPS). They include playtime ticks, deaths, mob kills, aggregate blocks mined, advancement counts and observation times. This is not a full analytics/session engine, exact first-ever join history or verified gameplay integration. No mixins/redstone mechanics were added, but that does not establish runtime compatibility with every technical mod or cannon.

Two Java protocol tests/build passed historically; fresh results are recorded in chapter9/17. No Fabric module or dependency was installed on Ubuntu. Exact Plan Fabric1.21.1 publisher query found no compatible artifact during prior review; do not substitute newer game-version jars. Plan broader analytics is deferred; retain narrow secure account-linking bridge if later integrating another provider.

## Installation boundary

Stage A has no bridge key/group/socket/mount. Stage B needs private/local control approval and maintenance window. Stage C requires reviewed per-server directory/group IDs, socket/key sharing only to that Minecraft instance, a hardened systemd drop-in and exact Docker mount paths; never expose archive keys, full agent state/config or Docker socket. Validate a trusted test identity after an approved backup/maintenance restart. Stage D physical independent server validation is still pending.
