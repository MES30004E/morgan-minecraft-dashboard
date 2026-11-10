# Ubuntu integration audit — 10 November 2026

## Observed facts and limits

Read-only inspection of the existing Crafty UI confirmed Crafty 4.11.0, Morgan's Test Server, Crafty UUID `36ca5a76-35ed-4db4-aafa-d34923e83916`, game port 25565, Java 21, and an enabled “Automatic World Backup” every six hours. The container server directory shown is `/crafty/servers/36ca5a76-35ed-4db4-aafa-d34923e83916`, with `./logs/latest.log`; this is **not evidence of a host bind-mount source**. Autostart and crash detection were enabled. Nothing was saved or executed in Crafty.

The Java command shown was `"/usr/lib/jvm/java-21-openjdk-amd64/bin/java" -Xms2000M -Xmx8000M -jar fabric.jar nogui`. Do not change Java, these flags or the server manager as part of dashboard installation. UI timing formatting changed after JavaScript initialized; raw API timestamp timezone remains unverified. The adapter deliberately returns unavailable uptime instead of guessing from a naive timestamp.

Supabase inspection still reports zero agent bindings and zero game commands. Website resource UUID `c18848e0-5448-433a-909d-804ad3680713` is distinct from the Crafty UUID. No live status has been manually inserted into the cloud. Minecraft can be online while this dashboard honestly reports unknown.

Not observed: Ubuntu shell/kernel version, actual Docker mount sources, Crafty container numeric UID/GID, service-account existence/groups, local CA fingerprint/SAN/chain, working token scope and exact authenticated stats payload, filesystem permissions, SSD free space, or network recovery on this host. The read-only inventory script collects selected fields without dumping container environment or secrets. Host facts must be reviewed before installation.

## Findings and fixes

| Area | Finding | Implemented correction / verification |
|---|---|---|
| Stage A safety | The previous service would consume commands immediately | `controls_enabled` defaults false, strict boolean validation, Worker returns before cloud claim, Crafty execute refuses effects. Database binding `control_enabled` separately defaults false and both legacy/scoped claim RPCs deny dispatch. Python and SQL regressions prove it. |
| Readiness | Heartbeat did not prove control readiness | Permission-checked RPC combines host approval, local mode report, recent health, recent known snapshot and active resource. UI disables operations unless all are satisfied. |
| Preflight | Initial instructions requested control credentials too early | Stage A requires GET/statistics-only Crafty identity and rejects local control, console, backup paths and bridge settings. No queue claims. It can initialize only application-owned archive state. |
| Installer | Bridge setup was coupled to initial install | Stage A no longer creates a bridge group/key/socket. Existing unexpected privileged service account/group and path symlinks are rejected. Service is installed but never started by the script. |
| Docker | Generic container paths risked incorrect host assumptions | No Docker socket/group access, compose edits or host-path assumptions. Stage A uses loopback TLS only. Additional mounts are deferred and must be reviewed from actual inventory. |
| TLS | Self-signed deployment needs explicit trust | Local HTTPS only; redirect refused, trust via privately verified CA, hostname/SAN matching and TLS 1.2+. No `verify=false`, `curl -k`, or automatic remote certificate trust. |
| Identity | Human role and agent identity must remain separate | Dedicated confirmed Auth account, no human membership, exact server binding in private schema. No frontend service role. Provisioning not performed. |
| Recovery | Agent crash must not replay an operation | Per-server SQLite durable journal; expired queue, claim token, replay ledger, uncertain reconciliation and original revocation locking retained. Observer does not recover/finish commands. |
| Archives | Shared state changes could break evidence | Existing nonpartitioned state makes preflight fail; migrate preserving journal/key/manifests using multi-server guide. Verified encrypted archive acknowledgement remains necessary for cloud deletion. No uncertain deletion. |
| Systemd | Service rights must match stage | Unprivileged identity, no Docker or bridge supplemental group, read-only system; writable application state and archive root only. Stage C requires a reviewed socket-path/group drop-in. |
| Telemetry | Charts should not manufacture history | Actual snapshot trigger stores one 15-minute sample per server, prunes on update to one day. Human/cross-server writes denied. Missing data stays missing. |
| Multiple servers | One host may manage several resources | Root-managed mappings, scoped RPC calls, independent workers/journals/archive paths and batched metrics. One invalid Crafty adapter does not hide other server telemetry. Two-configuration SQL/Python fixtures cover isolation without launching game processes. |

## Operational stages

A: separately approve files/service/account and a stats-only Crafty identity. Prove real heartbeat/status/players/available metrics, visible staleness, agent restart and short network interruption recovery. Agent restart is permitted only after installation approval; do not disable host networking/playit as an artificial test. Physical uptime stays unavailable until its exact API contract is verified.

B: separate approval plus game maintenance window. Review narrow Crafty permissions, then host administrator enables only the exact binding and local `controls_enabled:true`. Console and backup metadata are additional opt-ins. Verify permissions against an independent test configuration before live stop/restart. Archive and journal remain in place. Do not change Docker volume ownership recursively.

C: no exact official Plan Fabric 1.21.1 artifact was verified; the official loader/version filter returned no versions. Do not install a newer incompatible JAR. Existing narrow Fabric bridge has Java 21 tests but is not installed or operational. Review exact Fabric API dependency, socket-only per-server mount, group IDs, key recovery and maintenance restart separately. No browser client mod needed.

D: automated independent test configurations pass without real game processes; physical second-server validation remains outstanding. Never point two resource UUIDs at the same Crafty UUID or share bridge keys/directories.

## Live versus simulated

Live: Pages UI, Supabase Auth/Google and approved Owner membership, RLS/RPC database checks, existing Crafty UI inspection. Local/CI simulation: Python adapter/worker faults and recovery, queue races, two-server isolation, archive interruptions, Fabric protocol tests. Not live: Ubuntu agent, real telemetry transfer, Crafty API token integration, console upload, metadata scan, game commands, archive exports from Ubuntu or in-game linking/statistics. Installing or testing those requires the staged approvals above.
