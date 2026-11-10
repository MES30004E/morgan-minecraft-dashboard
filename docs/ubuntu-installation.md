# Reviewed Stage A installation plan — separate approval required

Prepared only. **Do not execute this until Morgan separately approves installation on Ubuntu.** No agent has been installed or started; no live Crafty token has been created. Crafty, worlds, existing backups, playit and network failover remain authoritative and independent.

Read [integration audit](integration-audit.md), [multi-server](multi-server.md), [archives](archives.md) and [maintenance](maintenance.md). Use the full tested source SHA from the release record for `REVIEWED_COMMIT`; never deploy the older pre-observation release or a moving branch.

## 0. Read-only inventory, before approval

At the Ubuntu local terminal, review/run the repository's `deploy/inventory-readonly.sh`. With no argument it lists Crafty container candidates; rerun with the exact container name to inspect only its configured user, mount mappings and port bindings. No Docker environment or secret dump. Review output before sharing. This script does not install or modify anything. Resolve actual Ubuntu/Python version, UID/GID, mount paths, listener address, disk space and existing service identity before installation.

Privately inspect the existing Crafty CA/certificate using `openssl x509 -in VERIFIED_LOCAL_CERTIFICATE_PATH -noout -fingerprint -sha256 -ext subjectAltName`; substitute a locally identified path, not a guessed Docker source. Verify provenance locally, chain and SAN for `localhost` (or the actual chosen loopback IP). Do not fetch and automatically trust the network certificate. Do not bypass browser/curl certificate warnings.

## 1. Private identities after Stage A approval

Create a dedicated confirmed Supabase Auth account with a long random password entered privately. No human membership/role. Record only its Auth UUID, then the project administrator registers the exact mapping:

```sql
begin;
insert into private.agents(user_id,server_id,control_enabled)
values ('AGENT_AUTH_UUID'::uuid,'c18848e0-5448-433a-909d-804ad3680713'::uuid,false);
insert into public.audit_events(server_id,action,details)
values ('c18848e0-5448-433a-909d-804ad3680713','agent.registered','{"stage":"observe"}');
commit;
```

Provision a Crafty identity/token scoped to **only the intended server and statistics/read access**, without console write/start/stop/restart/file management/user management. Verify the installed Crafty role/token model and actual `/api/v2/servers/UUID/stats` response. If that version cannot supply adequately read-only permissions, stop for review instead of substituting an administrator token. No live credentials have been created in advance.

## 2. Prepare reviewed files (copy after separate approval)

If `/opt/morgan-minecraft-agent` or application state already exists, inspect and use the upgrade/migration procedure; do not overwrite it or delete journals/keys. Confirm the pinned commit in the release record first.

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends git python3-venv ca-certificates
sudo git clone https://github.com/MES30004E/morgan-minecraft-dashboard.git /opt/morgan-minecraft-agent
cd /opt/morgan-minecraft-agent
sudo git checkout --detach REVIEWED_COMMIT
sudo bash deploy/install-agent.sh --approved-install
sudoedit /etc/morgan-minecraft-agent/agent.env
sudoedit /etc/morgan-minecraft-agent/servers.json
```

The installer creates a nologin `morgan-agent`, private application state and archive key, installs pinned/hash-verified Python dependencies and systemd unit, and reloads systemd. **It does not start/enable the service.** It does not create a bridge key/group or change Docker. Existing identities/path symlinks are checked, not silently repurposed.

Enter agent email/password, stats-only Crafty token and verified local CA path privately into root-only `agent.env`. Never paste them into chat, shell history, repository or frontend. Use the example's existing resource-to-Crafty mapping, `controls_enabled:false`, `upload_console:false`; omit backup and bridge fields. `ENABLE_ARCHIVES=true` enables application archives, not world backups. Each additional server needs an independent mapping and explicit private registry row. Never share one Crafty UUID among resources.

Install the privately verified certificate as `/etc/morgan-minecraft-agent/crafty-ca.pem`, then:

```bash
sudo chown root:morgan-agent /etc/morgan-minecraft-agent/crafty-ca.pem
sudo chmod 0640 /etc/morgan-minecraft-agent/crafty-ca.pem
sudo /opt/morgan-minecraft-agent/.venv/bin/python deploy/preflight.py /etc/morgan-minecraft-agent/agent.env
```

Preflight signs in, checks scoped binding, performs verified TLS GET statistics and tests application archive access as the service user. It refuses Stage B/C configuration and never claims queue commands. Stop on any failure; secret values are not printed. Dashboard/physical server UUID mapping must also be manually confirmed in Crafty; preflight cannot infer the intended world from a UUID alone.

## 3. Start observation only (within separately approved Stage A)

Before cloud records can expire, create and securely copy an encrypted archive-key recovery file away from the SSD; see archive guide. Preserve that key across upgrades.

```bash
cd /opt/morgan-minecraft-agent
sudo -u morgan-agent .venv/bin/python agent/archive_cli.py --key-file /etc/morgan-minecraft-agent/archive.key wrap-key --output /var/lib/morgan-minecraft-agent/archive-recovery.key.enc
sudo systemctl enable --now morgan-minecraft-agent
sudo systemctl status morgan-minecraft-agent --no-pager
sudo journalctl -u morgan-minecraft-agent -n 50 --no-pager
```

Verify actual heartbeat and status within two minutes, player names/count where Crafty reports them, CPU/memory where supplied. Uptime is intentionally unavailable until raw timestamp timezone is verified. The dashboard must show observation mode with controls disabled. Do not send start/stop/restart as a smoke test. Verify stale rendering after safely stopping **only the agent**, then restart it and observe recovery; do not disrupt gameplay networking. Confirm real archive manifests/counts/checksums and quota health before relying on retention. Offline/unverified cloud records are retained.

## 4. Separate Stage B and C

Stage B requires explicit approval and a maintenance window before game operations. Add only approved Crafty capabilities, set exact registry binding `control_enabled=true` through project-admin SQL and exact local mapping `controls_enabled:true`, then restart only the agent. Review readiness and test isolated permissions. Console (`upload_console:true`) and backup metadata (`backup_directory` from observed host mounts, read-only rights) require their own privacy/path review. Changing dashboard metadata never changes host mappings.

Stage C requires separate mod and Docker-mount approval. No verified exact Plan Fabric 1.21.1 release was found; do not install newer game artifacts. The narrow server bridge requires tested Java 21/Fabric API versions, individual per-server bridge key/socket/group and only that server's reviewed mount. Stage A unit deliberately lacks bridge supplemental groups/writable socket paths: create a reviewed systemd drop-in for exact directories/groups before enabling a bridge. Never mount archive keys, entire configuration/state roots, Docker socket or other servers' keys. Keep online-mode true; no hybrid UUID changes. Back up mods/config and verify Crafty's world backup before any maintenance restart.

## Rollback and recovery

```bash
sudo systemctl disable --now morgan-minecraft-agent
```

Disable/revoke exact cloud binding and revoke the agent Auth sessions/password and Crafty token. Preserve SQLite journals, archive keys, manifests and ciphertext; do not delete them to retry uncertain operations. Ubuntu game processes, playit and existing backups continue. UI rollback redeploys the prior tested commit; database rollback uses a forward repair, not table drops. Stage C rollback affects only newly added files and reviewed mounts during a maintenance window. Detailed restore/search/mirror procedures are in archives.md; WD Passport is optional, NAS access is not assumed.
