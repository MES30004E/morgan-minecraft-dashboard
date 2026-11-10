# Ubuntu infrastructure — reported versus observed

Verified handover date: 10 November 2026 (Asia/Singapore). [Start here](00-START-HERE.md) · [Feature evidence](02-FEATURE-STATUS-MATRIX.md) · [Validation](17-HANDOVER-VALIDATION.md)

## Evidence classes

User-reported existing hardware/software: MSI GS65 laptop, Ubuntu Server 26.04.1 LTS, Crafty 4.11.0 in Docker, Minecraft Java 1.21.1 / Fabric Loader0.20.1 / Java21, local gameplay25565, loopback Crafty HTTPS8443, CGNAT and playit public gameplay, Ethernet/Wi-Fi failover and autostart. Exact hostname/login/internal addresses and mappings are preserved only in the protected local operational index; do not publish new network details.

Historical read-only Crafty UI inspection on 10 Nov confirmed version4.11.0, the intended server UUID/name, Java21 startup command, enabled autostart/crash detection, local port and enabled automatic six-hour backup. It showed a container-internal server directory and latest.log; that is not a host Docker mount source. No Crafty setting was saved and no game command was sent. This handover did not re-inspect the physical server or assert current game online status.

## Unknown/unverified host prerequisites

Actual shell/kernel/OS patch, Docker container name and host mount sources, numeric UID/GID, certificate provenance/fingerprint/SAN, scoped token semantics and real stats payload, actual SSD free space, backup retention/integrity/restore, service identity/groups and networking/power behavior need local validation. DHCP reservations, closed-lid handling, power-button protection, power-loss recovery, battery charge controls, temperatures and long-term alerts must not be reported configured merely because requested. Do not guess support for laptop charging firmware controls.

## Safe next inspection

Review deploy/inventory-readonly.sh before running it at the local Ubuntu terminal. It prints selected OS/Python/container name/image/mount/user/port/disk fields and does not dump Docker environment. Run with no argument, then with the exact observed Crafty container name. Inspect output privately before sharing. Certificate trust must come from controlled local material and verified SAN matching; never curl -k or bypass a browser warning.

The normal installation is /opt/morgan-minecraft-agent, root-managed private config under /etc/morgan-minecraft-agent, unprivileged nologin morgan-agent, per-server state under /var/lib/morgan-minecraft-agent, encrypted archives under /var/lib/morgan-minecraft/archives. These are **proposed application paths**, not claims they exist. Existing unexpected users, privileged/supplementary groups or path symlinks make installation/preflight refuse. No Docker group/socket privilege is granted.

See [integration audit](../integration-audit.md), [reviewed plan](../ubuntu-installation.md), [multi-server](../multi-server.md), and [deployment/recovery](10-DEPLOYMENT-AND-RECOVERY.md). Never run host-changing commands without separate approval.
