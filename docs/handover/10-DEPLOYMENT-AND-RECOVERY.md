# Deployment, rollback, recovery and portability

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Cloud release procedure

Inspect current remote HEAD and local status; create an isolated branch. Run existing frontend/Python/database/Java checks and secret scans. The public main branch triggers .github/workflows/pages.yml; it builds before deploying dist through GitHub Pages. Verify workflow conclusion, deployment URL and actual loaded asset/title—not merely a successful push. A full clone and Git bundle preserve reachable history. Public project docs/source are canonical in GitHub; private operational notes are not published.

Supabase already has15 ordered migrations. For any later database change, inspect hosted history, prepare/test a forward migration with the current CLI/plugin, review grants/RLS/search_path/legacy paths, apply only to the existing project under authorization, align recorded version and reverify. No schema change is made for this handover. A schema recreation cannot restore Auth users or private production rows by itself.

## Stage A — separate approval, observation only

Read [reviewed Ubuntu plan](../ubuntu-installation.md), [integration audit](../integration-audit.md), [multi-server migration](../multi-server.md) and [archive recovery](../archives.md). Revalidate actual controller mapping, mount facts, numeric users/groups, CA provenance/SAN and stats-only token semantics. Never create/admin-scope credentials to bypass a failed preflight. Exact existing mapping is in the protected index and existing authorized public reference; controller UUID and resource UUID must remain distinct.

The following commands are **prepared instructions, not authorization or execution evidence**. Substitute the full reviewed handover/source commit for REVIEWED_COMMIT and stop if the destination/state already exists:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends git python3-venv ca-certificates
sudo git clone https://github.com/MES30004E/morgan-minecraft-dashboard.git /opt/morgan-minecraft-agent
cd /opt/morgan-minecraft-agent
sudo git checkout --detach REVIEWED_COMMIT
sudo bash deploy/install-agent.sh --approved-install
sudoedit /etc/morgan-minecraft-agent/agent.env
sudoedit /etc/morgan-minecraft-agent/servers.json
# Install only the privately verified existing CA using its locally confirmed source.
sudo chown root:morgan-agent /etc/morgan-minecraft-agent/crafty-ca.pem
sudo chmod 0640 /etc/morgan-minecraft-agent/crafty-ca.pem
sudo .venv/bin/python deploy/preflight.py /etc/morgan-minecraft-agent/agent.env
```

Dedicated confirmed Auth identity must be bound in private.agents to the exact server, with control_enabled=false. No human Owner login or service-role key. Local controls_enabled=false, upload_console=false and no backup/bridge paths in Stage A. Archive key generated only during approved installation; make encrypted independent recovery copy before relying on deletion. Installer does not enable/start service. Only after approved install and passing preflight:

```bash
sudo systemctl enable --now morgan-minecraft-agent
sudo systemctl status morgan-minecraft-agent --no-pager
sudo journalctl -u morgan-minecraft-agent -n 50 --no-pager
```

Verify real heartbeat/state/count/available metrics and visible staleness. Stop/restart only the agent for safe recovery validation if within approved scope; do not restart Minecraft or disable game networking as a smoke test. Uptime remains unavailable until timestamp timezone is verified. Check manifests/count/checksum/ACK/quota before relying on retention.

## Stages B/C/D and rollback

B requires separate host control flag plus local switch, narrow Crafty permissions and maintenance window before live stop/restart. Console privacy and actual read-only backup paths need review. C adds exact compatible mods/Fabric API and only per-server bridge socket/key/group/mounts, with a reviewed systemd drop-in; no full config/state roots or Docker socket. D verifies independent real servers after fixture isolation has passed. Worlds and existing schedules remain unchanged.

Agent rollback: `sudo systemctl disable --now morgan-minecraft-agent`, revoke exact binding/Auth sessions/Crafty token, preserve journal/archive key/manifests/ciphertext. UI rollback redeploys the preceding tested commit, not a history rewrite. DB rollback is a reviewed forward repair, not destructive drops. Interrupted upgrades: stop agent, preserve old full state/key/config, inspect migration assumptions and uncertain outcomes, then recover partitioned state without resetting execution evidence. Never overwrite an existing archive key or erase journal to force replay.

Archive CLI supports inspect, health, search, decrypt, wrap-key, unwrap-key, mirror and prune. See ../archives.md for exact authenticated recovery/TTL commands. Search/decrypt outputs contain private records and stay outside Git. WD Passport mirrors require a mounted, marked destination; no NAS share is assumed. A Git bundle backs up source/history, not worlds, production database, live Auth secrets or archive master keys.

## Cross-platform local recovery

macOS/Linux/cloud: use deploy/setup-local-handover.sh with an explicit folder outside existing Git roots; no sudo required. Restore from an exported bundle with `git clone project.bundle repository`, verify SHA256SUMS first, and reconnect origin if needed. Run `git fsck --full`, inspect HEAD and restore the approved toolchains. A new ChatGPT account needs its own connectors/consent; no session/cookie export. The local private index can be read only by the owner and should be disclosed to the new session in minimal excerpts, never uploaded automatically.
