#!/usr/bin/env bash
# Public source/history + empty private templates only. No sudo or live credential collection.
set -euo pipefail
umask 077
base=${1:?Pass an absolute handover destination outside an existing Git worktree}
[[ "$base" = /* ]] || { printf 'Use an absolute path.\n' >&2; exit 1; }
mkdir -p "$base"
if git -C "$base" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
 printf 'Destination must be outside an existing Git working tree.\n' >&2; exit 1
fi
mkdir -p "$base/exports" "$base/reports"
chmod 700 "$base" "$base/exports" "$base/reports"
if [[ ! -e "$base/repository" ]]; then
 git clone https://github.com/MES30004E/morgan-minecraft-dashboard.git "$base/repository"
else
 [[ $(git -C "$base/repository" remote get-url origin) = https://github.com/MES30004E/morgan-minecraft-dashboard.git ]] || { printf 'Unexpected existing repository; refusing.\n' >&2; exit 1; }
 git -C "$base/repository" fetch --all --tags
 # Do not overwrite, reset, switch branches or discard existing working files.
fi
if [[ $(uname -s) = Darwin ]]; then
 private_root="$HOME/Library/Application Support/Minecraft Dashboard Handover/private"
else
 private_root="${XDG_DATA_HOME:-$HOME/.local/share}/minecraft-dashboard-handover/private"
fi
mkdir -p "$private_root"
chmod 700 "$private_root"
if git -C "$private_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then printf 'Private destination is inside Git; refusing.\n' >&2; exit 1; fi
if [[ ! -e "$private_root/PRIVATE-HANDOVER-INDEX.md" ]]; then
 (set -o noclobber; cat > "$private_root/PRIVATE-HANDOVER-INDEX.md" <<'TEMPLATE'
# Private local handover index — do not upload
Record only necessary operational metadata and provenance. No passwords, SSH keys,
OAuth secrets, service-role keys, Crafty tokens, sessions or archive master keys.
Host/network/mount/certificate facts: NOT VERIFIED; supply manually after approval.
Secret locations/provisioning: see public handover chapter14; never paste values here.
Review filesystem permissions, realpath and synchronization software before adding facts.
TEMPLATE
 )
 chmod 600 "$private_root/PRIVATE-HANDOVER-INDEX.md"
fi
printf 'Public checkout: %s\nProtected template location: %s\nNo live configuration or credentials were collected. Review sync and filesystem protections.\n' "$base/repository" "$private_root"
