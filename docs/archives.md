# Verified local archives

This implementation is prepared for review. It does not install anything on Ubuntu, create a service, mount a WD disk, or assume a NAS exists. Enable it in the agent only after provisioning a separate archive key and a private archive directory, and deploying the matching cloud archive RPCs.

The cloud makes an immutable export before removing source rows. The agent requests at most 20 batches per kind in one run, checks the exact UTF-8 payload checksum, JSON envelope, record count and forbidden credential fields or recognizable OAuth, Supabase secret, Bearer, and JWT values, then gzip-compresses and encrypts with AES-256-GCM and a fresh random 96-bit nonce. Batch identity is authenticated as associated data. A separately derived HMAC-SHA256 key authenticates each manifest. Each manifest contains `batch_id`, `kind`, `created_at`, `archived_at`, `ack_state`, `record_count`, `sha256`, `cipher_sha256`, `filename`, and `hmac`.

Only after writing and fsyncing encrypted bytes, authenticating/decrypting/recounting their on-disk contents, writing/fsyncing the manifest, and verifying again does the worker call `ack_archive`. RPC failure propagates; a pending batch can be retried safely. Existing manifests are authenticated and their exports verified before reuse. Every new or reused batch is durably marked `pending` before cloud acknowledgement; after the RPC succeeds it is durably marked `acknowledged`. Pending exports are retried before new prepares, including when an earlier cloud ACK committed but its response or the local state update was interrupted. The cloud must accept exact acknowledgement replays idempotently. The archive lock remains held throughout the awaited cloud ACK, so concurrent pruning cannot delete its local evidence. Contending maintenance or archiver operations fail closed with a busy error and must be retried later; they do not block the event loop. A complete encrypted file left by interruption before manifest creation is authenticated against the cloud batch before a new manifest is written. Conflicting, corrupt, or unrecognized files are retained for manual investigation. A cloud acknowledgement interrupted in transit may already have committed: the protocol must make acknowledgement idempotent.

Archive files are 0600 and the archive root is 0700. Use an account-private parent directory; do not place keys or exports under the group-readable Minecraft server tree. `ARCHIVE_KEY_FILE` must be an independently generated raw 32-byte secret, separate from the bridge HMAC key. It must be owned by the agent account and inaccessible to the shared Minecraft group. Keep its recovery copy apart from both the archive volume and the live key. Losing all copies of this key makes archives unrecoverable. The implementation does not provide OS keychain management or automatic key rotation.

LocalArchiveStore defaults to a 1 GiB quota, configurable using its `max_bytes` argument. Existing regular files, unknown/orphan files, and manifests count toward quota. An export exceeding quota is refused without cloud acknowledgement. This logical quota is not a filesystem reservation: a free-space preflight also reserves 64 MiB for other local workloads before new writes. Full disks and I/O errors stop acknowledgement. The preflight is a point-in-time check; another process can consume space afterwards. `usage_bytes()` and `health()` expose quota usage, remaining quota, filesystem free bytes, reserve bytes, and a writable status; the CLI `health` command prints these without record data. Archive operations serialize on a local advisory file lock. Keep one trusted OS account responsible for the root; protection against an attacker controlling that account or changing ancestor directories is outside this boundary.

## Local retention

| Kind | Local TTL |
| --- | ---: |
| Commands | 365 days |
| Audit events | 730 days |
| Backup metadata | 365 days |
| Daily statistics snapshots | 365 days |
| Daily membership snapshots | 365 days |

Local TTL starts at signed manifest `archived_at`, the actual local archival time, rather than the cloud batch creation timestamp. A previously delayed cloud batch therefore receives its full local retention period. Only `acknowledged` archives may expire. `pending` archives, including legacy signed manifests without explicit state or `archived_at`, never expire automatically. Legacy manifests acquire a local archival clock when their ACK is retried successfully. Cloud source retention and daily snapshot generation are managed by the SQL archive protocol. Backups here mean metadata; actual Minecraft world backup files require their own backup workflow. Expiry is an explicit CLI `prune` operation, not automatic cleanup. All manifests must verify before any files are removed. Unverified files and orphan files are never automatically deleted, including after interrupted pruning. This conservative behavior may require manual disk cleanup after investigation. A WD mirror has its own retained files and must be pruned explicitly if desired.

## Offline CLI

Run commands as the archive owner, using the pinned agent Python environment. Examples use placeholders for paths; substitute your private archive root and key file. Never put the key itself or recovery passphrase in command arguments, environment dumps, chat, or logs.

```sh
python archive_cli.py --root /private/archive-root --key-file /private/archive-key inspect
python archive_cli.py --root /private/archive-root --key-file /private/archive-key health
python archive_cli.py --root /private/archive-root --key-file /private/archive-key search start
python archive_cli.py --root /private/archive-root --key-file /private/archive-key decrypt BATCH_ID --output /private/review.json
python archive_cli.py --root /private/archive-root --key-file /private/archive-key prune
```

`inspect` verifies every manifest and archive before listing metadata. `search` decrypts locally and prints matching records, which may include private operational information. `decrypt` writes verified JSON to a new 0600 file and refuses to overwrite any existing path. The JSON is reformatted for review; retain the encrypted original and signed manifest to preserve the original exact-byte checksum. Avoid retaining plaintext exports longer than needed.

Create a recovery copy using `wrap-key`; it prompts twice using `getpass`, derives an AES-256 key with scrypt (`N=131072`, `r=8`, `p=1`, random 16-byte salt), and encrypts the archive key with AES-GCM. Choose a long unique recovery passphrase stored separately. Recovery uses `unwrap-key`, prompts once, authenticates the passphrase, and writes a new 0600 raw key file without printing the key:

```sh
python archive_cli.py --key-file /private/archive-key wrap-key --output /private/recovery.key.enc
python archive_cli.py unwrap-key --input /private/recovery.key.enc --output /private/recovered-key
```

Recovery key files use an authenticated versioned binary format. Incorrect passphrases and modified files fail closed. Key files and recovery inputs must not have group/other permissions.

## Optional mounted WD mirror

Mount and validate the intended external disk yourself. At the actual mount point create a file named `.morgan-archive-target` containing exactly `morgan-minecraft-archives-v1` followed by a newline. The CLI never mounts hardware and refuses an absent or incorrect marker, and requires the target itself to pass `os.path.ismount`. Set the marker only on the intended mounted target; the marker selects a mounted filesystem, but does not prove a particular hardware serial number. Check the mount before each use to avoid copying into an unmounted local mountpoint.

```sh
python archive_cli.py --root /private/archive-root --key-file /private/archive-key mirror /Volumes/WD
```

The mirror copies exact verified ciphertext and signed manifests into the target's private `archives` directory, checks quota there, and verifies destination bytes. It refuses conflicting files and supports interruption recovery. It does not mirror the live encryption key or remove source or destination files. A mirror is additional storage resilience, not a substitute for a separately protected recovery key. Mirrors are not required before the primary local store acknowledges cloud export.

## Manual restore rehearsal

1. Recover the archive key into a private file if necessary.
2. Run `inspect` against the primary or WD `archives` directory. Resolve any authentication failure before proceeding.
3. Decrypt a selected batch into a new private plaintext file and review its kind, server identity, export time, and records.
4. Create a separate staging database or isolated staging project using the matching schema. Import only reviewed records using an explicit kind-specific mapping and least privilege credentials. Preserve original IDs where appropriate and check duplicates, row counts, referential integrity, and permissions. Membership snapshots describe historical access; do not silently reactivate old permissions.
5. Compare staging results with the archive and record any transformations. Decide separately whether any production change is appropriate.

No CLI command automatically restores, overwrites, or reconnects a production database. These operational exports are not full database backups: they omit credentials and unsafe freeform fields, and cannot reconstruct deleted user authentication accounts or restore Minecraft world contents.

## Verification

From the application root, run `PYTHONPATH=agent python -m unittest discover -s agent/tests`. Archive coverage includes tamper/wrong-key failures, checksum/count mismatch before cloud acknowledgement, quota refusal, idempotent retry, concurrent prune/ACK exclusion, pending-ACK recovery after cloud source deletion, local archival retention clocks, legacy pending manifests, interrupted writes and acknowledgements, credential rejection, conservative TTL pruning, explicit mirror selection, CLI plaintext permissions, and passphrase recovery.
