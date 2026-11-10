#!/usr/bin/env bash
# No installation, authentication, Minecraft commands, filesystem writes or Docker mutations.
# Run at the Ubuntu local terminal. Inspect output before sharing; it contains local paths.
set -euo pipefail
printf 'Operating system\n'
cat /etc/os-release
printf '\nKernel / Python / existing service identity\n'
uname -sr
python3 --version
getent passwd morgan-agent || true
printf '\nCrafty container candidates (names/images only)\n'
sudo docker ps --format '{{.Names}} {{.Image}}'
if [[ $# != 1 ]]; then
  printf '\nRerun with the exact Crafty container name from the list to inspect its mounts and configured user.\n'
  exit 0
fi
# Inspect selected fields only: never print environment variables or container configuration secrets.
sudo docker inspect --format 'Container configured user={{json .Config.User}} Mounts={{json .Mounts}} Ports={{json .NetworkSettings.Ports}}' -- "$1"
printf '\nLoopback dashboard listener\n'
sudo ss -ltn '( sport = :8443 )'
printf '\nDisk space for future application state\n'
df -h /var/lib /opt
printf '\nNo certificate was trusted, credential created, service installed or game operation performed.\n'
