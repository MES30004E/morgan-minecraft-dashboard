# Handover validation and acceptance record

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Verification boundary

This chapter is updated with final results before publication. Local and cloud facts were inspected on10Nov2026; source baseline is8d83416. The final handover commit contains this file, so its own SHA is resolved with git rev-parse HEAD and recorded in the final/local release report rather than a self-referential manifest hash.

## Acceptance evidence

- Full internal-Mac clone has all19 reachable baseline commits and both origin branches. Remote main was verified through the connected GitHub service; no unrelated repository/project was modified.
- All18 requested Markdown chapters, feature CSV and project manifest are required by deploy/validate-handover.py. Additional source inventory, coverage counts, edge-case CSV, test reports and safe screenshots support recovery.
- Feature inventory preserves all explicit A–G bullets plus prior identity/multi-server/archive/safety/avatar requirements. Each field keeps code/test/deployment/operational distinctions and remaining work.
- Fresh frontend10tests and Python65tests passed. Java/build/CI/browser/secret scan results are in verification-results.json and final local reports. Pending values are not passes; the final report must resolve them or state gaps.
- Gitleaks initial2findings were the intentional publishable key and synthetic fixture; exact scoped exceptions were reviewed. Full-history scan subsequently passed. Canary gate passed. Final staged-tree scan and artifact inspection are required before push.
- Private operational notes are outside Git, owner-only, with no exported long-lived secret values. Internal realpaths did not resolve into known cloud-sync roots; unknown third-party sync/OS compromise remains a limitation. The Passport raw checkout's AppleDouble index issue was identified; a verified Git bundle is the recommended external preservation form.
- No Ubuntu installation/service start/Crafty credential/mod/network/world/schedule/game operation was performed or authorized by this handover. Live physical Minecraft status was not reverified.

## Known gaps that must survive transfer

No actual agent, live telemetry/control, real local archive export, in-game linking/counters or independent physical second-server validation. No new first-login/expired-state/provider-outage/multi-account lifecycle validation on production. No committed Playwright/axe suite, full WCAG certification, actual Firefox/WebKit/iOS/Android hardware coverage, complete long-content/network/storage failure suite or independent world restore. No full production DB/Auth/world/key backup was taken. Existing public operational identifiers remain in history; no history rewrite or actual credential rotation was necessary/performed.

## Reproduce validation

```bash
python3 deploy/validate-handover.py
git status --short
git diff --cached --stat
git diff --cached --name-only
git check-ignore -v private/example.txt .env.local agent-state/test.db local-exports/test.json
gitleaks git . --log-opts=--all --redact=100 --config .gitleaks.toml
git fsck --full
```

CI additionally validates all9SQL suites, concurrent revocation/historical-baseline failures and Java protocol build. Inspect actual workflow links/conclusions after publication; source-level success is not physical integration. The local bundle must pass git bundle verify and a fresh temporary clone/fsck; its SHA-256 is stored outside the bundle in SHA256SUMS. Private files must be absent from git ls-files and pushed-tree checks. Review filesystem modes and the private index manually before any transfer.

## Fresh measured defect HOV-001

Chrome Overview on baseline8d has horizontal page overflow:320CSSpx/client305/scroll352 and360CSSpx/client345/scroll352. All other14 measured width/height combinations had no page-level overflow. This remains **unfixed**, with [raw measurements](browser-coverage.json) and [320px capture](screenshots/overview-320-overflow-8d.jpg). Inspect the control-card header/readiness badge and responsive minimum widths in src/Community.tsx; wrap/reflow content rather than hiding it. No full narrow-device or WCAG pass is claimed. Other views/long fixtures/engines may contain further defects.


## Fresh local verification completed

Frontend10/10, Python65/65, TypeScript/Vite build, Java21 Gradle build with2protocol tests, npm audit0known vulnerabilities, structural/link/source/migration validation and git diff --check passed. Full19commit history passed reviewed Gitleaks; canary detection passed. Prior Pages artifact13773914286 was downloaded via the connected GitHub tool, its published SHA256 verified, only5static files inspected and extracted contents scanned clean; no env, private, state, key or database entries. Fresh ephemeral CI results are still pending this handover's publication and must be checked against the final SHA; they are not claimed complete in advance.

## Post-publication code verification

Code commit `ab0cd97ee3050603eae8edb52bae6bbef1cb4d81` passed all5fresh workflows: [frontend/Pages](https://github.com/MES30004E/morgan-minecraft-dashboard/actions/runs/42849183893), [database9suites/concurrency/baselines](https://github.com/MES30004E/morgan-minecraft-dashboard/actions/runs/42849183770), [Python](https://github.com/MES30004E/morgan-minecraft-dashboard/actions/runs/42849183537), [Java](https://github.com/MES30004E/morgan-minecraft-dashboard/actions/runs/42849183521), [secret/structure](https://github.com/MES30004E/morgan-minecraft-dashboard/actions/runs/42849184116). Pages deployment completed, and the live neutral title/sidebar/footer plus unchanged actual server name/Owner state were inspected. Post-publication320/360/390/768/1440CSSpx checks retain HOV-001 at320/360; no unsupported compatibility claim is made.

The20commit source/history bundle passed checksum verification, git bundle verify, fresh temporary clone, git fsck and handover validator at exact code commitab0cd97. Private files remain outside Git,0700directory/0600files. A metadata-only documentation followup records these results; it does not change application/agent/schema behavior. Final current SHA and renewed bundle checksum are recorded in the owner-only/local release report and GitHub history.
