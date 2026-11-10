# Neutral branding and UI requirements

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Explicit, limited change

The display name defaults to **Minecraft Console** and can be set with public build-time `VITE_APP_DISPLAY_NAME`. src/branding.ts validates trimmed length1–80 and rejects control characters. tests/branding.test.ts first failed on missing implementation, then passed. App header/sidebar/footer and document title use APP_NAME; static HTML/privacy text uses the neutral default. Static privacy content is not a fully parameterized branding system. No gameplay/server/resource identifier was renamed.

```bash
# Public string only, during a local build. Never put a secret in VITE_*.
VITE_APP_DISPLAY_NAME='Community Panel' npm run build
```

GitHub Pages deploys its default unless an approved build-time value is configured. No GitHub variable or provider setting was changed for customization. The user's actual Minecraft server name remains untouched and may contain their personal name; account display names are also user data, not product branding to overwrite.

## Occurrence inventory and safe replacement policy

| Location | Occurrence | Decision |
|---|---|---|
| src/main.tsx and src/components/DashboardShell.tsx | Morgan Control / community/footer label | Replaced with configurable APP_NAME |
| index.html and public/privacy.html | Personal product title/copy | Neutral default; keep legal/privacy substance |
| package.json, README and historical docs | Project/release identity | Preserve history; new handover uses neutral product language |
| GitHub repository URL/Pages base | morgan-minecraft-dashboard | Do not rename; URLs/OAuth/deep links depend on it |
| Supabase project name/reference | Existing project metadata | Do not recreate/rename for branding without reviewed migration |
| /opt, /etc, /var/lib, systemd unit, environment names | Existing proposed morgan agent namespace | Preserve compatibility and encrypted-state/key paths |
| Java package/protocol identifiers | community.morgan / signed protocol identifiers | Preserve binary/protocol compatibility |
| Server/account display names | Real user-selected values | No change without approval |

A full grep inventory is in source-inventory.json/branding-occurrences.txt. Some old UI design docs are historical and conflict with the current neutral zinc/blue/shadcn layout; chapter11 records that supersession. Do not rewrite stable security-critical code purely to remove an identifier string.

## Visual requirements still binding

Professional hosting-panel density; established shadcn sidebar07/Radix foundations; accessible actions/forms/dialogs, consistent spacing/type and semantic states. No decorative controls, excessive gradients, arbitrary color/emoji schemes, fake analytics or oversized marketing cards. Light/dark must persist; actual resource selection and scoped permissions must survive resizing, browser history and OAuth. Tables/logs must remain usable at narrow widths instead of hiding functionality to avoid overflow. Screenshots prove only the captured state; continue the interaction/edge-case plan.

## Captured source baseline (personal branding is historical)

These safe screenshots depict the deployed8d baseline before this handover's neutral branding publication, not a synthetic fixture or the future branded release: [desktop dark](screenshots/desktop-dark-8d.jpg), [desktop light](screenshots/desktop-light-8d.jpg), [mobile dark](screenshots/mobile-dark-8d.jpg), [mobile navigation](screenshots/mobile-navigation-8d.jpg), [console](screenshots/console-8d.jpg). New neutral branding must be checked after Pages deployment. Remaining visual work includes HOV-001 at320/360, full browser/long-content coverage and any future configurable privacy/legal copy review.

## Published neutral UI

[Current neutral branding capture](screenshots/neutral-branding-ab0.jpg) was taken after code commitab0cd97 passed Pages deployment. The real server name and account identity were preserved. Google/Supabase administrative resource names and all technical identifiers remain unchanged; this is a product display-name setting, not a provider/resource rename.
