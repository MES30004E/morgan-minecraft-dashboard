# Cloud archive contract and retention

This migration changes cloud metadata only. It installs no cron schedule, touches no Ubuntu host, and never deletes worlds or archive files. Apply it only after the SQL tests pass against an isolated PostgreSQL database. Run `supabase/tests/archiving.sql` after all migrations as postgres; the test creates synthetic fixtures and rolls everything back. The standalone bootstrap must include the real Supabase `service_role` role.

## Agent RPCs

Only a signed-in enabled agent mapped by `private.agent_server()` may use these RPCs. Human authenticated users fail authorization; anonymous users have no execute grant. Private tables have RLS, explicit deny policies, and no client table privileges. Public wrappers are security invokers; private implementations have a fixed empty search path and explicit execute grants.

`prepare_archive(kind text)` accepts `commands`, `audit`, `backups`, `statistics`, or `memberships`. It returns SQL null when there is nothing to export, otherwise:

```json
{"id":"batch UUID","kind":"commands","created_at":"timestamp","payload_text":"exact JSON text","sha256":"64 lowercase hexadecimal characters","record_count":1}
```

The exact UTF-8 bytes of `payload_text` are the plaintext to encrypt. Do not parse and reserialize before hashing or encrypting. Its JSON envelope is `{format:1,kind,server_id,exported_at,records:[...]}`. Each batch is at most 500 records and 524288 plaintext bytes. An oversize individual record raises an error and preserves its source. There is at most one pending batch per server and kind. Repeated preparation returns its identical stored ID, timestamp, text, digest and count, even after underlying source rows change.

Terminal commands, audit events and backup metadata become exportable when their creation timestamp is more than one day old. Already acknowledged identical versions are skipped. Statistics and memberships use complete, frozen daily UTC snapshots: all source rows are staged transactionally, drained across bounded batches, and captured only once per day. A stalled earlier snapshot finishes before the next daily capture. A snapshot chunk retains the original capture timestamp. An empty snapshot returns null. This is current-state snapshotting, not a history of every change between daily captures.

Membership records contain server/user UUIDs, state, role UUID, role name and a sorted permission list. No Auth user rows, emails, sessions, passwords or keys are read. Commands exclude `claim_token` and freeform `result`; player arguments and operation values are allowlisted. Audit exports allowlist action names, UUID detail values, recognized state/outcome/operation values, known permission names and a boolean enabled field. Freeform details, including reconciliation notes, are omitted. Unknown action names become `other`.

`ack_archive(batch_id uuid, plaintext_sha text, record_count integer, ciphertext_sha text)` returns void. The Ubuntu agent must first atomically persist an encrypted archive, reopen it, authenticate/decrypt it, and compare the exact plaintext digest and record count. Only then may it acknowledge. The database checks the mapped server, batch identity, exact stored plaintext hash/count and a lowercase 64-character ciphertext digest. A matching retry is harmless; a different digest/count or a conflicting ciphertext digest fails. On success the cloud plaintext payload is cleared. Ciphertext bytes and encryption keys never enter this database.

The acknowledgment is a trust statement by the authorized agent: SQL cannot independently inspect an Ubuntu disk or prove that a supplied ciphertext hash corresponds to a retained encrypted file. Keep the agent credential private and do not acknowledge failed encryption, failed persistence, failed decryption, or digest/count mismatches. Until acknowledgment succeeds, source rows remain regardless of age. Restore and disaster recovery still require the Ubuntu archive and its encryption key.

## Deletion gate

`private.housekeeping()` is executable by postgres only, with no public RPC wrapper. Scheduling is a separate operation after migration tests pass.

| Source | Earliest deletion | Required archive condition |
| --- | --- | --- |
| Terminal commands (`completed`, `failed`, `expired`) | Created more than 7 days ago | Acknowledged exact current full-row fingerprint |
| Audit events | Created more than 90 days ago | Acknowledged exact current full-row fingerprint |
| Backup metadata | Created more than 90 days ago | Acknowledged exact current full-row fingerprint |
| Pairing challenges | Expired more than 1 day ago | None; challenges are never exported |
| Uncertain/claimed/queued commands, statistics, memberships, roles, permissions, worlds and actual archive files | Never by this job | Not applicable |

Private item fingerprints hash the complete database row, including fields intentionally omitted from the sanitized export. Any field mutation invalidates the old acknowledgment for deletion; the changed row must be exported and acknowledged again. The exported sanitized record is intentionally not a backup of excluded sensitive/freeform fields.

Important membership, role permission, identity link/unlink, owner bootstrap/change, agent register/revoke, command reconciliation and security audit events leave a permanent daily count and chained SHA-256 rollup when pruned. The rollup hashes the full original cloud row but stores no freeform content or identities. One fixed-size rollup row per server and affected UTC day is retained. The `audit_security_summaries(target uuid)` RPC exposes only day/count/hash to a user with `audit.view` on that server; anonymous and other-server access fail. It is an integrity summary; reconstruct individual event history from the encrypted archives. Nonexpired audit events remain queryable normally.

Pending batch text and frozen snapshot queues intentionally have no expiry. A stalled archive cannot silently permit deletion. After acknowledgment, plaintext is erased; source fingerprint receipts disappear once the source is deleted, and statistics/membership receipts are cleared during housekeeping. Compact batch digest receipts and daily snapshot run markers remain for retry/idempotency. Monitor pending batches and cloud storage growth; retention is a safety gate rather than a guarantee of staying within a provider quota during archive outages. Batch bounds do not cap source history, snapshot row counts or permanent receipts.

## Verification boundaries

SQL tests cover anonymous/human/cross-agent denial, exact retries, count/hash/ciphertext mismatch rejection, no deletion before acknowledgment, deletion after acknowledgment only past the applicable TTL, uncertain preservation, mutation of an unexported field blocking deletion, rearchiving that changed version, audit redaction, role/permission snapshots, all 501 statistics rows across two chunks, source mutation between frozen chunks, daily deduplication, source preservation, permanent security summaries and acknowledged payload clearing. Tests are transactional and contain no real credentials or production data. Multi-session contention, Ubuntu filesystem durability, encryption and the remote API path require integration testing separately.
