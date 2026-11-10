# Multiple server operation

The first version had server-keyed commands, memberships, snapshots, backups, audit and statistics, but its frontend, agent and linking workflows assumed one server. This update completes selection and configuration around those existing resources rather than replacing the control queue or Crafty adapter.

## Selection and permissions

Use **All servers** for the permitted-server overview, or **Selected server** to switch without signing in again. URLs use `#server/SERVER_UUID/overview` (and `/players`, `/player/MINECRAFT_UUID`, `/access`, `/configuration`, etc.). The last permitted selection is remembered per website user in local storage. A bookmarked private UUID does not grant visibility or control. An invited user may request membership using that bookmark; new requests remain pending and do not grant operations.

Memberships and role templates belong to each server. The same person can have different roles on different servers. `server.create` permits adding configurations; `server.configure` permits changing metadata, endpoint references and lifecycle. Both default only to Owner. The database rechecks current permissions under the server lock; browser controls are just presentation. Suspended users lose operation access immediately. Configuration removal is reversible soft removal; it preserves audit, identity, statistics, backup metadata and execution history. Archive/removal stops new claims and operations, not a game process or an already dispatched command.

The existing instance retains its UUID and is labelled **Morgan's Test Server**, Minecraft Java 1.21.1, Fabric 0.20.1. Its existing Crafty UUID and playit endpoint are metadata references. No world, tunnel, Crafty installation, loader, backup schedule or local port was changed.

## Endpoints and configuration

A game server can have zero through eight endpoint references. Providers are simple labels such as `playit`, `direct` or another provider; hostname, optional public port and internal destination are separate fields. An endpoint has its own UUID and never identifies the game server. Endpoint status is **unknown**, not an inferred assertion that a tunnel is reachable. This release does not provision, modify or probe tunnels. Editing a reference cannot make the Ubuntu agent connect to a new address or filesystem path.

Only Minecraft Java is implemented initially. Version, loader and port are per-resource metadata; Fabric linking/statistics are optional. Crafty-based start/stop/player operations can manage other compatible Minecraft instances without requiring Fabric. Other game adapters are not claimed to work.

## Agent mappings and deployment

The agent reads `/etc/morgan-minecraft-agent/servers.json`, owned by root:morgan-agent with mode 0640 (or stricter service-owned 0600). This private local file is the sole authority for mapping a dashboard UUID to a Crafty UUID, certificate, token and optional local backup directory. It is never downloaded from database configuration. One Auth service identity may be registered for multiple server UUIDs on the same machine. Different machines should have different Auth identities and tokens. A server has one active registry binding; moving it between machines requires stopping the old agent and reviewing journal/state transfer before rebinding.

Example local configuration (replace the second mapping with an actual created dashboard UUID and confirmed local Crafty UUID):

```json
{"servers":[
 {"server_id":"c18848e0-5448-433a-909d-804ad3680713","crafty_server_id":"36ca5a76-35ed-4db4-aafa-d34923e83916","crafty_url":"https://localhost:8443","upload_console":false},
 {"server_id":"SECOND_DASHBOARD_UUID","crafty_server_id":"SECOND_CRAFTY_UUID","crafty_url":"https://localhost:8443","upload_console":false}
]}
```

Per-server `crafty_token` and `crafty_ca_file` may override private environment defaults if controllers use different credentials/certificates. Tokens must remain scoped to intended instances. To register another mapping, use the same reviewed `private.agents(user_id,server_id)` insert with that server UUID and record an audit event for that server. Do not use an owner account or service-role key. The agent preflight checks every mapping with the `agent_call(target,'identity',{})` RPC and read-only Crafty statistics.

Each mapping has its own journal under `/var/lib/morgan-minecraft-agent/SERVER_UUID/`, archive directory under `/var/lib/morgan-minecraft/archives/SERVER_UUID/`, optional bridge socket/key and independent retry loop. RPCs include a pinned server UUID; SQL verifies its registry binding and the command's server, and the Python adapter rejects a mismatched returned command before execution. A multi-bound identity gets no implicit default target. Recovery queries are bounded and scoped. The service opens one Auth session and one command subscription; metrics are collected concurrently and sent as a bounded batch once a minute. A bad Crafty instance produces unknown metrics without hiding healthy instances.

### Separate Fabric bridges

Configure `link_socket`, `link_key_file` (the private mode-0600 agent copy), and `link_group` per server. Each bridge needs a distinct socket, secret and Unix group; duplicate groups or keys are rejected. Provision per-server subdirectories under `/var/lib/morgan-minecraft-link/`, owned by morgan-agent and that server's group, mode 0750. Add the agent to each group. Put only that server's shared mode-0640 bridge key in its subdirectory. Bind mount **only that subdirectory** into its Minecraft container. Never mount the common parent containing other servers' keys. Configure the Fabric module's `MORGAN_LINK_SOCKET` and `MORGAN_LINK_SECRET_FILE` accordingly. The agent's private key path and the container's shared copy are distinct. Review actual container UID/GID mappings before installation.

Keep normal online-mode authentication. A global official UUID can belong to one website account and be verified on several servers. Pairing codes and final confirmation are server-specific; unlink disconnects only the current server. Other associations, website ownership, inventory and roles survive. Username history records trusted observations instead of using the username as identity. Offline-mode/hybrid namespaces remain unsupported and fail closed at the bridge.

## Archives, quotas and recovery

The existing 1 GiB archive quota is a machine-wide budget split evenly among configured servers, not 1 GiB multiplied by server count. Archive retention and the verified-before-delete gate are unchanged. Pending/unverified archives never auto-expire. Optional WD mirrors must be operated separately for each server directory, retaining the server UUID in the destination layout. Use separate target mountpoints/markers or explicitly choose a per-server mirror destination; do not merge separate archive roots blindly. NAS access remains optional.

If any earlier agent installation has execution journals or archives at the old root path, stop and review an explicit offline migration before enabling this version. Never discard a journal or start a new journal to evade uncertain-operation reconciliation. No prior agent was installed by this project, so no journal migration has been performed.

The project limits configuration to ten servers and eight endpoints per server. Creation/metadata caps are not proof that ten busy servers fit the free plan. A 60-second snapshot is about 43,200 updates per server per month; viewer fan-out multiplies Realtime traffic. Frontend history downloads remain explicit, only the selected dashboard subscribes, and switching servers unmounts pending actions and permission state. Review actual egress/Realtime/database usage before increasing active server count. Permanent replay and archive receipts also consume storage. No extra website deployment or Supabase project is needed to add a resource.

## Verification and limits

Tests cover hidden-resource RLS, independent server memberships, explicit agent binding, cross-server command completion denial, archive/lifecycle behavior, pairing scope, shared official UUIDs, isolated statistics, username history, safe unlink, private local config, duplicate target rejection, per-server journals, and a failed Crafty adapter alongside a working one. Real multi-instance control, in-game linking, Ubuntu permissions and live archive exports still require separately approved installation and non-destructive validation. SMTP and timestamp-derived uptime limitations from the initial release remain.
