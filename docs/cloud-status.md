# Cloud implementation record

Project `iyhtknyrecnythgyuvbq` in Singapore was created at a quoted $0/month. Repository: https://github.com/MES30004E/morgan-minecraft-dashboard . Dashboard: https://mes30004e.github.io/morgan-minecraft-dashboard/ .

Supabase migrations implement current-membership authorization, granular roles, RLS, safe command queue, agent fencing, replay tombstones, pairing, statistics privacy, encrypted archive handshake and archive health. Nightly verified housekeeping is installed and its active cron job was checked. Browser roles cannot write audit, queue, agent or operational state directly. Only approved agent identities can publish state or execute claims.

Google provider is enabled with nonce checks and verified email; anonymous sign-ins are disabled. Its secret was transferred directly into Supabase without a repository/disk copy. Live PKCE Google login and profile editing passed. The user explicitly approved enrollment of the verified account as Owner. No unrelated project was changed. Google audience was Testing at the last check; publication is tracked separately. Default SMTP has not been configured for general users.

Python safety tests, PostgreSQL authorization tests and Fabric build/protocol checks passed on the verification branch. Security review fixes cover authorization revocation while waiting for a lock, archived-request replay and pruning during an ambiguous archive acknowledgment. SQL tests use disposable rolled-back fixtures; the concurrency test runs only in CI. The Supabase security advisor reports only leaked-password protection disabled (paid-plan feature).

No dedicated agent Auth account/registry binding, private Crafty credentials, Ubuntu service or Fabric deployment has been provisioned. No game command, in-game link, real statistics collection or real archive export has been tested against the laptop. Review ubuntu-installation.md for the remaining staged installation and safe validation. Until then the UI correctly shows the agent disconnected.
