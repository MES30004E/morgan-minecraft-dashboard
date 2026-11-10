# Supabase database, migrations and permissions

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Existing project and safe inspection

Use the existing Minecraft project in Singapore (public routing reference is already in src/client.ts); do not create another project or inspect unrelated projects. The project is ACTIVE_HEALTHY with PostgreSQL 17.11 observed at handover. No service-role key was requested/exported. The local private index records exact operational mapping. The public manifest records existing public project reference and migration versions, never credentials or Auth rows.

Current inspection: 15 hosted migrations match filenames in supabase/migrations. Zero agent bindings, commands, snapshots and metric samples. Two server configurations. Nightly morgan-verified-retention cron is active at `20 18 * * *` UTC (02:20 Singapore). No schema migration is needed for this handover; branding/ignore/scanning changes leave DB behavior intact.

## Tables and RPCs

See [source-inventory.json](source-inventory.json) for migration-derived tables/functions and their defining files. Human surfaces include servers, server_endpoints, profiles, roles, permissions, role_permissions, memberships, snapshots, online_players, metric_samples, commands, console_tail, backups, audit_events, mc_identities, identity_servers and player_statistics. Private surfaces hold scoped agent bindings, pairing, archive batches/fingerprints and durable request replay metadata. Read the actual migration definitions rather than guessing columns.

Public RPCs include request_membership, manage_member, set_role_permission, configure_server, configure_endpoint, enqueue_command, claim_command, finish_command, resolve_uncertain, agent_call, agent_metrics, server_readiness, begin_server_link, claim_server_link, verify_link, player_access, prepare_archive and ack_archive. Existing legacy wrappers remain compatible and must not bypass scoped binding/host control gates.

RLS separates status.view from players.view, console.view, backups.view and audit.view. Human users cannot write telemetry, grant themselves roles, read other-server/private state, or act as agents. Auth user metadata is not authorization. Security-definer routines live in private schema with empty search_path and explicit checks; public wrappers have restricted grants. agent_readiness table is not directly readable by browsers; the summary RPC checks status.view.

## Migration history and restore

Never run the CI bootstrap against production. It creates disposable auth/publication substitutes solely for ephemeral PostgreSQL. Apply reviewed forward migrations through the connected Supabase service; list history first and align filenames with hosted versions. Existing retention and replay structures depend on ordered migrations; do not cherry-pick just the last SQL file into an empty DB.

Source migrations recover schema, not production Auth users or all operational data. No full production data/Auth export was taken because it could expose private information or credentials. For a future disaster backup, obtain separate approval, export only necessary data to encrypted local storage, protect recovery keys separately, and rehearse isolated restoration. Do not drop/recreate this live project or overwrite existing users/worlds.

## Budget and monitoring

Existing design targets Supabase Free: review current provider quotas before expansion (https://supabase.com/pricing). Historical planning used 500 MB DB, 5 GB egress, 2M Realtime messages/month and 200 peak connections; these are planning references, not a permanent entitlement or live billing verification. Host snapshots about 43,200/month/server multiply with viewers. Guards include per-user/server rates, 200 operations/day/server, DB storage guard around 400 MB and replay-ledger cap. Monitor actual dashboard usage. Free projects can pause; Minecraft must continue independently.
