# Security and threat model

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Assets and attackers

Protect worlds/inventories, service control, account/UUID ownership, permissions, journals, audit integrity, archive confidentiality/recovery keys and private operational topology. Consider anonymous/signed-in nonmembers, malicious members, revoked admins, compromised browsers, network attackers, poisoned local mappings, leaked agent identity, untrusted log content and accidental cross-server routing. Host root or an attacker holding agent/archive keys can exceed the application boundary; OS permissions and encryption do not repair a compromised account.

## Enforced controls

- Human capabilities: server-scoped approved membership; database-side checks under the server lock. Editable user metadata and UI role state confer no trust. Owner self-change protections and concurrent revocation regression remain.
- Agent: distinct confirmed Auth identity, explicit private bindings, no human membership, root-managed loopback Crafty mappings, scoped token/certificate and no service-role key. Stage A default-off gates exist in Worker, adapter and DB claims, including legacy wrappers.
- Commands: explicit allowlist/argument validation, expiry, bounded queue/rates, unique request ledger, server match, claim token and durable at-most-once local journal. Unknown outcomes require evidence-based reconciliation; at-most-once dispatch does not imply guaranteed completion.
- Transport: outbound HTTPS/Auth RPC; local Crafty TLS validation and redirect refusal; optional authenticated Unix bridge. No public SSH/Crafty/RCON or Docker socket exposed by this project.
- Archives: AES-GCM encrypted compressed records, authenticated manifests, SHA-256/count/fingerprint verification and fsync before ACK. Failed/uncertain exports never authorize deletion. One-GiB shared quota,64MiB reserve, verified retention and independent encrypted key recovery are essential.
- Data minimization: player visibility separate from status; private statistics default; no email/password in game chat; redaction and archive secret rejection. No real player dataset is exported for this handover.

## Current scan and review limitations

Gitleaks8.30.1 downloaded from official release with verified SHA-256 initially flagged the intentional public Supabase publishable key and an exact synthetic credential rejection fixture in historical code. Both were inspected. .gitleaks.toml has two narrow value/path exceptions, not blanket test/history exclusions. Full reachable-history rescan passed with those reviewed exceptions; current/staged tree and artifact scans are recorded in validation. A canary test verifies unrelated secret-shaped text still fails the gate. A clean scan is not proof no secret ever existed elsewhere.

Existing public history includes routing/project/controller identifiers and operational path references; they are not passwords and RLS must remain the security boundary. Newly supplied host login/internal-address metadata is local private only. No published history rewrite, credential rotation or secret collection was performed. No actual exposed long-lived credential was identified by these scans; rotate/review immediately if a later scan finds one, before removing/reworking history with approval.

## Residual risks and explicit gaps

Free provider outage/pause, SMTP limitations, unverified host permissions/TLS/token scopes, first live game integration, exact mod compatibility, online backup consistency, full browser/accessibility coverage, state/race behavior under actual providers and local cloud-sync/OS-account compromise remain. Supabase advisor historically and currently reports leaked-password protection disabled; do not buy a plan or disable verification as a shortcut. Google is primary. Future unofficial-client support needs authenticated player attestation and UUID collision/operator/inventory analysis; online-mode stays true.

For incidents stop only the separately installed agent, revoke exact bindings and credentials/sessions, preserve journals/keys/ciphertext, reconcile uncertain commands and restore through a reviewed forward repair. Do not erase worlds or evidence. See chapter10 and existing archive recovery guide.
