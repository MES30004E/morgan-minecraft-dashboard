# Device, browser, accessibility and edge-case testing

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Coverage vocabulary

Actual available-browser checks are recorded in browser-coverage.json and chapter17. All widths use **CSS viewport emulation in desktop Chrome**, not physical iPhone/Android/tablet hardware. No Firefox/WebKit/Safari-engine test is claimed unless a corresponding fresh result exists. Historical live UI checks covered1440×1000 and390×844, dark/light, mobile sheet/selector, dialog cancellation, existing Google return, account, empty console/backups and audit. The handover expands targeted layout checks and keeps unrun interactions explicit.

## Required layout matrix

| CSS width | Representative height | Purpose |
|---|---|---|
|320|640|Very narrow reflow; touch targets and long identity/address labels|
|360|740|Compact Android layout emulation|
|375|667|Compact iPhone layout emulation|
|390|844|Modern mobile layout|
|414|896|Large compact phone|
|430|932|Large phone|
|600|800|Small tablet; before desktop sidebar|
|768|1024|Portrait tablet/breakpoint|
|820|1180|Medium tablet|
|1024|768|Landscape tablet/small laptop|
|1280|720|Short laptop|
|1440|1000|Desktop baseline|
|1920|1080|Full HD|
|2560|1440|Wide desktop and bounded content width|

Also test844×390 mobile landscape,1024×600 short landscape,639/640/641 and767/768/769 breakpoint boundaries. Rotation/resizing must not lose permitted selection or leave an inaccessible modal. Verify browser zoom and200% text resizing manually; a narrower viewport alone does not establish those results. Safe areas/mobile browser chrome need actual hardware review. Every size is required in the plan; only rows with measured results in the coverage artifact are claimed executed.

## Browser/CI matrix and resource budget

Current engine: connected desktop Google Chrome. Planned representative PR job: pinned Playwright Chromium at360×740 and1280×720, deterministic local fixture API responses, core routes/controls-disabled/auth redirects, keyboard dialogs and axe-core on signed-out/approved/pending states. No overlap with Node's pure unit tests: reuse the app and node runner for domain tests; use Playwright only for browser interaction/visual testing. A scheduled or manual expanded run adds Firefox/WebKit at390/768/1440 and the full14-width Chromium layout sweep. Actual macOS Safari, iOS Safari and Android Chrome are periodic manual targets; record hardware/OS/browser versions, not simulated device names.

No current package.json E2E/axe scripts or screenshot-comparison baselines exist; do not run imaginary scripts or call the plan implemented. Next automation task should pin current upstream Playwright/axe versions, add local synthetic fixture routes with no production tokens, create named test projects and review baseline screenshots before enabling comparisons. Exact current runnable commands remain chapter9. Budget PR jobs for2 Chromium sizes and short smoke set, DB/Python/security first; expanded screenshots manual/scheduled, retention7days, no billable runners/services. Public Actions cost assumptions must be rechecked for the account; do not turn on paid minutes.

## Layout and visual acceptance

Check document.scrollWidth <= clientWidth (allow scrollbar interpretation), then inspect visible controls and scroll containers: no clipped actions, overlapping names, inaccessible navigation, hidden buttons, unreadable tables or charts. Horizontal scrolling inside a labelled table/log viewport is acceptable; clipping entire functionality is not. Test long server/user/domain names, empty description,0/1/many servers/endpoints/players, thousands of long Unicode/formatting-code log lines, resizing chart axes and preserving console scroll/follow. These need stable isolated fixtures; do not seed production with attractive fake data.

Capture dark/light desktop/mobile, portrait/landscape tablets, expanded/collapsed sidebar, selector, console, players, backups, activity, permissions, settings, dialogs, loading, error, empty and stale states. Store safe baselines by engine/viewport/theme with approved diffs; source/metadata artifacts need hashes and no real session material. A screenshot is not an interaction test.

## Accessibility acceptance (target WCAG2.2AA, no conformance claim)

Manual keyboard: Tab/Shift-Tab order, visible focus, skip target without route mutation, activate menu/selector, open dialog, focus trap, Escape/cancel, restored trigger focus, accessible form error/status announcements, labels and meaningful headings/one main landmark. Test contrast with an actual analyzer, color-independent status text, touch targets, reduced motion,200% text and reflow320px. Automated axe checks are planned; a zero-violation axe result would not prove complete WCAG conformance. Existing shadcn primitives reduce but do not eliminate application obligations.

## Full fault/edge matrix

[edge-case-matrix.csv](edge-case-matrix.csv) preserves **148** individually named cases across Auth, permissions, multi-server, Minecraft states, remote safety, telemetry/Realtime, console, backups and frontend resilience. They are conservatively marked Not run as complete E2E; chapter9 describes partial unit/SQL coverage, which is not promoted to a complete scenario pass.

Acceptance details: auth failures preserve safe routes/no privilege; pending/rejected/revoked roles deny protected RPCs even with forged frontend metadata; stale previous-server responses never overwrite current context. Unknown/disconnected agent never implies offline game. Double/concurrent/expired/wrong-server commands are rejected or reconciled without blind replay. Gaps/null/invalid count values stay missing; empty names with nonzero count remain correct. Hidden tabs unsubscribe and provider failures back off without request storms. Console remains read-only/redacted and never emits a command in observation mode. Archive failure/checksum/key/disk/ACK problems retain cloud evidence and preserve unresolved commands. Network/storage/API/null/theme/back-forward failures must be accessible and recoverable.

Use ephemeral databases, local adapters and owned test identities. Live Auth consent or service mutation and physical game tests need separate approval; no actual world is a destructive regression fixture. Backup creation/restoration/online-farm consistency and shutdown warning tests are blocked until approved host research. Preserve the existing six-hour schedule.

## Failure reporting

Record browser version, viewport/zoom/theme/state, expected/actual result, screenshot and safe console/network diagnostics, source commit and reproducibility. Do not log token-bearing URLs or full browser/session storage. Existing historical honest unknown states are not defects. Initial canary/branding RED failures are expected test gates, not unresolved production bugs. Fresh unexpected failures must remain in final validation even if most sizes pass.

## Fresh measured defect HOV-001

Chrome Overview on baseline8d has horizontal page overflow:320CSSpx/client305/scroll352 and360CSSpx/client345/scroll352. All other14 measured width/height combinations had no page-level overflow. This remains **unfixed**, with [raw measurements](browser-coverage.json) and [320px capture](screenshots/overview-320-overflow-8d.jpg). Inspect the control-card header/readiness badge and responsive minimum widths in src/Community.tsx; wrap/reflow content rather than hiding it. No full narrow-device or WCAG pass is claimed. Other views/long fixtures/engines may contain further defects.
