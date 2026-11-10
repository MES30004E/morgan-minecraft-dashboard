#!/usr/bin/env bash
set -euo pipefail
# PREPARED ONLY. Run on Ubuntu after the separate installation-plan approval.
if [[ "${1:-}" != --approved-install || "$EUID" != 0 || $(uname -s) != Linux ]]; then
  printf 'Review docs/ubuntu-installation.md, then run on Ubuntu as root with --approved-install.\n' >&2
  exit 1
fi
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [[ "$repo_dir" != /opt/morgan-minecraft-agent ]]; then
  printf 'Use the reviewed pinned checkout at /opt/morgan-minecraft-agent.\n' >&2
  exit 1
fi
python3 -c 'import sys; assert sys.version_info >= (3,11), "Python 3.11+ required"'
if ! getent group morgan-agent >/dev/null; then groupadd --system morgan-agent; fi
if [[ $(getent group morgan-agent | cut -d: -f3) == 0 ]]; then printf 'Refusing unexpected privileged service group.\n' >&2; exit 1; fi
for path in /etc/morgan-minecraft-agent /var/lib/morgan-minecraft-agent /var/lib/morgan-minecraft /var/lib/morgan-minecraft/archives; do
  if [[ -L "$path" ]]; then printf 'Refusing application path symlink.\n' >&2; exit 1; fi
done
if ! id morgan-agent >/dev/null 2>&1; then
  useradd --system --no-create-home --home-dir /var/lib/morgan-minecraft-agent --shell /usr/sbin/nologin --gid morgan-agent morgan-agent
elif [[ $(id -u morgan-agent) == 0 || $(id -g morgan-agent) != $(getent group morgan-agent | cut -d: -f3) || $(id -G morgan-agent) != $(getent group morgan-agent | cut -d: -f3) || $(getent passwd morgan-agent | cut -d: -f6) != /var/lib/morgan-minecraft-agent || $(getent passwd morgan-agent | cut -d: -f7) != /usr/sbin/nologin ]]; then
  printf 'Existing morgan-agent account is not the expected service account; refusing to repurpose it.\n' >&2
  exit 1
fi
install -d -o root -g morgan-agent -m 0750 /etc/morgan-minecraft-agent
install -d -o morgan-agent -g morgan-agent -m 0700 /var/lib/morgan-minecraft-agent
install -d -o morgan-agent -g morgan-agent -m 0700 /var/lib/morgan-minecraft /var/lib/morgan-minecraft/archives
python3 - <<'PY'
import grp,os,pwd
from pathlib import Path
uid=pwd.getpwnam('morgan-agent').pw_uid
gid=grp.getgrnam('morgan-agent').gr_gid
for name,raw in [('archive.key',True)]:
 path=Path('/etc/morgan-minecraft-agent')/name
 if path.exists():
  if path.is_symlink():raise RuntimeError('Unexpected key symlink')
  continue
 fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'wb') as output:
  key=os.urandom(32);output.write(key if raw else key.hex().encode());output.flush();os.fsync(output.fileno())
 os.chown(path,uid,gid)
PY
if [[ ! -e /etc/morgan-minecraft-agent/agent.env ]]; then
  install -o root -g root -m 0600 "$repo_dir/agent/agent.env.example" /etc/morgan-minecraft-agent/agent.env
fi
if [[ ! -e /etc/morgan-minecraft-agent/servers.json ]]; then
  install -o root -g morgan-agent -m 0640 "$repo_dir/agent/servers.example.json" /etc/morgan-minecraft-agent/servers.json
fi
python3 -m venv "$repo_dir/.venv"
"$repo_dir/.venv/bin/python" -m pip install --no-cache-dir --require-hashes -r "$repo_dir/agent/requirements.lock"
install -o root -g root -m 0644 "$repo_dir/agent/morgan-minecraft-agent.service" /etc/systemd/system/morgan-minecraft-agent.service
systemctl daemon-reload
printf 'Agent files prepared. Service was NOT started. Configure private credentials, trusted Crafty CA, and run the read-only preflight in the installation guide.\n'
