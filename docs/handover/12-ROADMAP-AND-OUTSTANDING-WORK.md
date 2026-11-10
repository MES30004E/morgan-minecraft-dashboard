# Roadmap and outstanding work

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Highest-priority next milestone

**Separately approved Stage A observation connection to the real Crafty server.** Before installation review actual Ubuntu inventory, controller/resource mapping, scoped stats-only Crafty identity, CA trust/SAN, service groups, SSD reserve and archive recovery. Present a concrete updated plan and obtain explicit approval. Zero bindings/snapshots means the physical connection is still absent even though the cloud tests pass.

## Ordered engineering backlog

| Priority | Work | Acceptance / gate |
|---|---|---|
| P0 | Safe owner-only recovery package and full Git history | Handover chapter17, local index, bundle verification, no secret export |
| P1 | Host read-only preflight and Stage A | Real heartbeat/status/count/available CPU/RAM, stale/reconnect/restart recovery, no game commands; separate approval |
| P1 | Archive commissioning/recovery | Verified durable exports/manifests/ACK, encrypted independent key recovery, quota and failure tests on application state |
| P1 | Physical server-specific authorization | Independent test configs/identities; do not use production world for destructive regression |
| P2 | Stage B controls | Explicit approval and game maintenance window; verify allowlist/idempotence/revocation/uncertain handling against Crafty |
| P2 | Console and backup metadata | Privacy review, redaction and observed read-only host paths; no new mounts/schedule changes without approval |
| P2 | Stage C linking/counters | Exact server artifacts/dependencies and socket mounts reviewed; owned test identity; confirmed pairing/unlink; no UUID changes |
| P2 | Expanded device/browser/accessibility automation | Representative CI matrix, stable fixture source, engine coverage/axe/manual keyboard; chapter16 |
| P2 | Public email delivery | Truly free approved provider or explicitly remain Google-only; never bypass verification |
| P3 | Online backup consistency and restore rehearsal | Research actual Crafty save/flush behavior and independent copied-world test; preserve AFK farms and six-hour schedule |
| P3 | Maintenance warnings, scheduling UI, operational alerts | Define granular capabilities/rates/transport/budget; currently absent or partial |
| P3 | Join/session history and avatars | Data model/retention/privacy before collection; first-recorded is not first-ever joined |
| P3 | Technical mods and host reliability | Verify exact Carpet/TIS/cannon/redstone/optimization artifacts, AFK behavior, DHCP, lid/power/battery/thermal recovery; separate approval |
| Optional | Plan, Discord, unofficial/hybrid clients, NAS | Exact compatible artifact/access, threat model, cost and consent review; no platform replacement |

## Known limitations and likely defects to investigate

- No current physical agent, real telemetry, game controls, archive exports or in-game statistics. This is the main integration gap, not a cosmetic dashboard bug.
- CPU/memory/players depend on actual Crafty API contract. Uptime intentionally returns unavailable. Starting/stopping/crashed/backing-up states are not yet an established runtime state contract.
- Manual browser checks cannot prove every storage/network/race/large-list/focus case. CSV/device matrix deliberately preserves Not run cases; add isolated deterministic E2E fixtures before broad visual regression.
- Agent identity uses a dedicated password/session refresh; commissioning must verify revoke/reconnect/backoff on the installed runtime without logging credentials.
- Unlimited long-term replay/security metadata is not promised. Existing caps/rollups require annual quota review and safe forward maintenance.
- Optional external mirrors do not automatically prune with primary retention; destination quotas and recovery checks remain necessary.
- Existing project docs have historical design/deployment snapshots; read decisions and dated validation instead of blindly following an old status paragraph.

Do not prioritize new decorative features, another backend, paid services or manager migration over the physical observation milestone. Preserve all independently traceable requirements in the CSV even when deferred.

## Fresh measured defect HOV-001

Chrome Overview on baseline8d has horizontal page overflow:320CSSpx/client305/scroll352 and360CSSpx/client345/scroll352. All other14 measured width/height combinations had no page-level overflow. This remains **unfixed**, with [raw measurements](browser-coverage.json) and [320px capture](screenshots/overview-320-overflow-8d.jpg). Inspect the control-card header/readiness badge and responsive minimum widths in src/Community.tsx; wrap/reflow content rather than hiding it. No full narrow-device or WCAG pass is claimed. Other views/long fixtures/engines may contain further defects.
