# Cloud implementation record

Supabase project: `iyhtknyrecnythgyuvbq`, Singapore, created with a quoted cost of $0/month.
Console: https://supabase.com/dashboard/project/iyhtknyrecnythgyuvbq
GitHub: https://github.com/MES30004E/morgan-minecraft-dashboard

## Applied and verified

Migration `20261110103847_access_control.sql` matches the hosted migration history.
All eight exposed tables have RLS enabled. Anonymous roles have no table access.
Profiles can be created and edited only by their owner, with column grants limiting
editable properties. Roles and membership approval are not browser-writable.
Authorization reads current membership records, so suspension takes effect without
waiting for a new JWT. No user metadata participates in authorization.

Queue insertion is available only through an authorized RPC. It rejects unknown
operations and extra arguments, serializes per-server inserts, caps requests at five
per user/server/minute and twenty per server/minute, deduplicates request IDs and
assigns a 60-second expiry. Audit creation is transactional with queue insertion.
The queue has no agent consumer yet; no real server commands can execute.

The hosted SQL test transaction passed member control denial, cross-user membership
visibility, escalation denial, duplicate suppression, operation allowlisting,
rate limiting, immediate revocation and anonymous access denial. Fixtures rolled back.
Supabase security advisor returned no findings after this migration.

CI runs the same migration and tests on PostgreSQL 17 with a minimal Auth contract.
It does not replace real Supabase Auth/OAuth integration tests, which remain pending.

## Remaining

Owner enrollment and administration RPCs, agent identity and command claiming,
status snapshots, retention, Minecraft pairing/statistics, frontend and Pages,
SMTP and end-to-end OAuth validation remain incomplete. No live owner is provisioned.

Google Cloud project `just-inverter-514310-s6` is dedicated to Minecraft. Its OAuth
client was created with the user's action-time approval; its secret was transferred
directly from Google's creation dialog into Supabase's provider form, without any
file or repository copy. Google is enabled in Supabase. Nonce checks remain enabled,
anonymous sign-ins remain disabled, and email confirmation remains required.
The Pages site URL and exact production callback are configured. Google audience
is currently Testing; test users or publication must be configured before login.
The unrelated Notionary Auth project was not modified.

## Rollback and recovery for this milestone

There is no Ubuntu deployment to roll back. Queue execution remains disconnected.
Disable authenticated EXECUTE on `public.enqueue_command` to stop new requests.
Do not drop tables for rollback: preserve audit and membership records. Use a
reviewed forward migration to repair schema defects. Before live enrollment,
set up an encrypted database export procedure; free hosting is not a backup policy.
