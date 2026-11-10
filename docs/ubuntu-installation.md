# Ubuntu installation plan — approval required

Nothing in this plan has been run on the Minecraft laptop. Review and approve this plan before executing any commands. It creates a dedicated unprivileged agent, private encrypted archives and a systemd service. It opens no inbound ports and grants no Docker socket or shell execution capability. Existing worlds, Crafty schedules, playit and network failover remain in place.

## Prerequisites and private provisioning

Confirm the actual Ubuntu version, Python 3.11+ with venv, Crafty server ID and Docker volume mappings locally. Do not replace your existing Java installation. The Fabric module needs Java 21 and Fabric API for Minecraft 1.21.1; build artifacts are available from the repository's Fabric workflow. Its protocol has been compiled and tested, but not exercised inside your running server.

In Supabase Authentication create a **dedicated agent account**, using a long random password entered privately. Confirm that service account administratively; never reuse the Owner account. Record its Auth UUID. An administrator then registers that exact UUID in SQL (substitute only the agent UUID):

```sql
begin;
insert into private.agents(user_id,server_id)
values ('AGENT_AUTH_UUID'::uuid,'c18848e0-5448-433a-909d-804ad3680713'::uuid);
insert into public.audit_events(server_id,action,details)
values ('c18848e0-5448-433a-909d-804ad3680713','agent.registered','{}');
commit;
```

This account receives only agent RPC access for one server, no membership or human role. Provisioning it is still outstanding; no secret has been generated or stored in this repository.

Create a Crafty API token limited to the intended Minecraft server, read statistics/logs and the approved start/stop/restart and player commands. Never grant file manager, user administration or unrelated servers. Confirm the Crafty version's token permission model in its local UI. Copy the existing trusted Crafty CA/certificate from your controlled installation; validate its fingerprint locally and ensure its SAN matches `localhost`. Never disable TLS verification or obtain trust by blindly accepting a network certificate.

## Phase 1: prepare files and read-only preflight

Run these **only after approval**, at the laptop's local terminal. Use the exact tested commit from the deployment record for `REVIEWED_COMMIT`; this must be a full 40-character SHA, not a moving branch. If `/opt/morgan-minecraft-agent` already exists, inspect it instead of overwriting it.

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends git python3-venv ca-certificates
sudo git clone https://github.com/MES30004E/morgan-minecraft-dashboard.git /opt/morgan-minecraft-agent
cd /opt/morgan-minecraft-agent
sudo git checkout --detach REVIEWED_COMMIT
sudo bash deploy/install-agent.sh --approved-install
sudoedit /etc/morgan-minecraft-agent/agent.env
```

In that root-only file enter `AGENT_EMAIL`, `AGENT_PASSWORD`, `CRAFTY_TOKEN`, the confirmed server ID and trusted CA path. Install the locally verified CA as `/etc/morgan-minecraft-agent/crafty-ca.pem`, readable by the agent. Keep `ENABLE_LINK_BRIDGE=false`, `UPLOAD_CONSOLE=false` initially; set `ENABLE_ARCHIVES=true`. The independent 32-byte archive key is created by the installer; do not replace it on upgrades. The bridge key is different and is the only key shared with Minecraft. Do not paste credentials into chat or shell commands.

```bash
sudo chown root:morgan-agent /etc/morgan-minecraft-agent/crafty-ca.pem
sudo chmod 0640 /etc/morgan-minecraft-agent/crafty-ca.pem
sudo /opt/morgan-minecraft-agent/.venv/bin/python deploy/preflight.py /etc/morgan-minecraft-agent/agent.env
```

Preflight authenticates the scoped account, verifies local Crafty TLS and reads statistics. It checks the private archive store and may initialize application-owned archive files. It does not claim queue commands or alter Minecraft files. Stop here if it fails. After it passes, and only with the installation approval:

```bash
sudo systemctl enable --now morgan-minecraft-agent
sudo systemctl status morgan-minecraft-agent --no-pager
sudo journalctl -u morgan-minecraft-agent -n 50 --no-pager
```

Validate the live dashboard receives a real heartbeat, metrics and player data. Do not stop/restart the game merely as a smoke test. Check archive health and a daily snapshot before relying on retention. First archive processing runs automatically; cloud deletion requires its verified acknowledgment. If the agent is offline or archives fail, cloud records remain.

## Phase 2: optional console, backup metadata and Fabric linking

Only after reviewing the actual Crafty compose file, container user/group IDs and host paths: grant the agent read-only access to the existing ZIP backup directory and configure `BACKUP_DIRECTORY`. Do not change Crafty's six-hour backups. Console upload is opt-in because it can include player messages; set `UPLOAD_CONSOLE=true` only after reviewing redaction and privacy.

The server-only Fabric module provides `/link`, `/register`, `/verify`, `/profile`, `/unlink` and statistics without client installation. Back up the current mods/config and verify the most recent Crafty backup first. In a maintenance window, add the built mod and compatible Fabric API to the existing Minecraft mods directory. Keep `online-mode=true`; do not install hybrid/offline authentication mods alongside this bridge. The current bridge trusts the normal online-mode identity boundary; hybrid support needs a separate authentication attestation design and isolated tests.

Bind mount the **directory** `/var/lib/morgan-minecraft-link` into the Crafty Minecraft container at the same path, read-only. Allow the Minecraft process's supplemental group to read the bridge key and connect to the mode-0660 socket. Do not mount `/etc/morgan-minecraft-agent`, archive keys, the Docker socket or the complete agent state into the container. The shared host directory is stable across service restarts. Exact compose edits depend on your existing installation and are intentionally not fabricated here. Review them before any container recreation. Set `ENABLE_LINK_BRIDGE=true`, restart only the agent, then perform the separately approved Minecraft maintenance restart.

Test linking using a fresh short-lived code: website create → in-game `/verify CODE` → inspect displayed website identity → `/verify confirm CODE`. Verify Member users cannot issue control commands. Unlink and re-link only a test identity you control; never change existing Minecraft UUIDs/world player data. Verify a real statistics snapshot appears before calling this feature operational.

## Key recovery and archive inspection

Create an encrypted recovery key copy before relying on archive deletion. Run from the application directory; passphrases are entered interactively and must be kept separately from the recovery file:

```bash
sudo -u morgan-agent .venv/bin/python agent/archive_cli.py --key-file /etc/morgan-minecraft-agent/archive.key wrap-key --output /var/lib/morgan-minecraft-agent/archive-recovery.key.enc
sudo -u morgan-agent .venv/bin/python agent/archive_cli.py --root /var/lib/morgan-minecraft/archives --key-file /etc/morgan-minecraft-agent/archive.key inspect
sudo -u morgan-agent .venv/bin/python agent/archive_cli.py --root /var/lib/morgan-minecraft/archives --key-file /etc/morgan-minecraft-agent/archive.key health
```

Move a protected copy of the encrypted recovery key off the laptop. See [archives.md](archives.md) for search, decrypt, restore rehearsal, TTLs and optional WD Passport mirrors. A NAS is optional; no writable share is assumed. Do not place plaintext exports in the Minecraft directory.

## Rollback

```bash
sudo systemctl disable --now morgan-minecraft-agent
```

Revoke the agent registry row in Supabase to stop cloud agent access, then revoke its Auth sessions/password and Crafty token. Do not delete its SQLite journal, archive key, manifests or encrypted archives. Cloud cleanup preserves records without verified archives. Roll back Fabric by removing only the newly installed module and restoring the reviewed compose/config changes during a maintenance window. Preserve worlds, existing mods, actual backups and playit settings. Reconcile uncertain command outcomes against Crafty before any retry; do not erase the journal to force a command.
