# Multi-server implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline, with one independent final review.

**Goal:** Extend existing server-keyed data to a complete multi-server control panel without changing Ubuntu.
**Architecture:** Keep one Auth account per person and independent server memberships. Add provider-neutral endpoint resources and reversible configuration lifecycle. Bind each agent RPC to a verified server mapping; run locally configured Crafty adapters with separate journals, bridges and archives under one supervisor. Keep official Minecraft identity ownership global, but verification associations and challenges server-scoped.
**Tech stack:** Existing React/TypeScript, Supabase PostgreSQL/RLS, Python and Fabric.
**Spec:** docs/multi-server.md; original user request retained locally in docs/multi-server-requirements.md and excluded from public publication.

## Global constraints

No Ubuntu changes, paid services, arbitrary paths/commands from the website, world/backup modifications or offline-mode identities. Existing UUID remains the first server. Removal is reversible metadata removal with history preserved. Only a current Owner may create more servers or configure resources; approved invitees may request access to a known server ID without listing private servers.

## Review focus

- A multi-bound agent must not inherit an arbitrary default server or finish another server's command.
- Switching servers must discard old responses, pending actions and permission state.
- Linking/unlinking on one server must not change another server's ownership association.
- Archive and command journals must never be shared between configured server IDs.
- Removing/archiving a configuration must stop new operations without dropping history or touching game processes.

## Tasks

- [x] Database: write multi_server.sql regression tests, observe failure, implement resource/endpoint configuration RPCs, multi-agent mappings and scoped dispatcher, pairing associations/history, archive-aware lifecycle; run old and new SQL suites on rollback fixtures and CI.
- [x] Agent: write scope/config tests, observe failure; add local-only config validation, scoped RPC adapter, multi-server supervisor and per-server state/bridge/archive routing. Test mismatch rejection and independent dispatch/recovery.
- [x] Frontend: write route/selection tests, observe failure; add permitted-server overview and selector, configuration UI, server-specific bookmark routes and scoped child components; test/build and live smoke test.
- [ ] Verification: independent whole-change security review, fix important findings with regression tests, run CI, apply tested forward migrations, deploy Pages, update installation/maintenance evidence. No real server operation until separate installation approval.

## Ledger

Initial inspection: tables mostly server-keyed; frontend SERVER constant, single Crafty adapter, single-agent mapping and global pairing/unlink semantics prevent complete multi-server support.
Ruling: configuration removal is reversible soft removal — preserves approved audit/archive/world history; costs retained small metadata and requires explicit future purge policy.

Database, agent and frontend implementation complete for review. New multi-server SQL suite plus updated pairing/statistics suites passed under proposed DDL in rolled-back hosted transactions. Python 55/55, frontend 4/4 and production build passed locally. Verification branch commit 66a4f99 starts CI. Public publication was initially rejected for potentially sensitive identifiers; compared against existing public baseline, found no new nonfixture identifiers or secret patterns and excluded the raw user request. Reduced changed-file publication was approved.

Final review: Important duplicate Crafty target via URL aliases — reproduced RED, normalized loopback aliases/ports/trailing slash/environment fallback. Reviewer-rated minor game-first root link regraded Important because it breaks second-server registration — regression RED, scoped bookmark added. No deferred minors. CI also reproduced suspended-membership metadata visibility regression; narrowed metadata exception to pending membership, preserving prior revocation expectations.
Final rulings on reviewed nonfindings: existing target/claim-token checks remain; keyed frontend instances discard stale responses; local config remains routing authority; in-flight operations may finish after archival; official UUID ownership survives server unlink; quotas are bounds, not a promise ten busy servers fit Free; per-server bridge mounts/groups need live validation; real-game verification stays outside current installation authorization.

Free-tier verification: heartbeat refresh previously reread all permitted role metadata, which becomes expensive with many server roles. Added RED→GREEN query-budget regression and restricted heartbeat requests to snapshot/health/presence; console/audit/role configuration remain explicit refreshes.

Hosted migration applied as 20261110130459_multi_server_resources after all verification-branch CI jobs passed. Cloud metadata now names the existing resource Morgan's Test Server. No Ubuntu changes.
