# Morgan Minecraft Dashboard — Continue Full Implementation

Continue from the previously approved architecture and research. This message supersedes the earlier Discord-first authentication decision.

**You are authorised to proceed with implementation. Do not restart the brainstorming process or request another general design approval.**

Use your available GitHub, Supabase, browser, Computer Use and development capabilities wherever possible.

## 1. Final authentication decision

Implement the following authentication methods:

**Primary: Google OAuth**

- Allow users to sign up and log in using Google.
- Configure Google OAuth through Supabase Auth.
- Use Computer Use to complete the Google Cloud Console and Supabase dashboard configuration where supported.
- Request my intervention only when account authorisation, interactive consent or another genuinely unavoidable step requires it.
- Never expose OAuth client secrets.

**Secondary: Email and password**

- Allow traditional email/password registration.
- Support secure password resets and email verification.
- Investigate a genuinely free SMTP solution for Supabase Auth.
- If SMTP cannot be configured within the free-tier requirements, implement the supported parts and clearly document what remains unavailable.
- Never bypass email verification merely to make registration appear functional.

**Optional future provider: Discord OAuth**

- Design the authentication system so Discord can be added later.
- Do not make Discord mandatory.
- Do not require friends to install any applications.

**Important:** Authentication and Minecraft identity verification are separate processes. Signing in with Google does not automatically prove ownership of a Minecraft username.

## 2. Player registration and Minecraft account linking

Create a unified account system.

Each user should have:

- A website account.
- A unique internal user ID.
- A display name.
- One or more linked Minecraft identities, if safely supported.
- A membership approval state.
- Server roles and granular permissions.
- Player statistics and activity history.

Support both registration workflows.

### Workflow A — Website-first

1. User visits the GitHub Pages website.
2. Signs up using Google or email/password.
3. Enters their Minecraft username.
4. Receives a short-lived, single-use account-linking challenge.
5. Joins the Minecraft server.
6. Completes the challenge using an in-game command.
7. The backend verifies the pairing and links the Minecraft identity.
8. Owner approval grants access according to server policy.

### Workflow B — Minecraft-first

1. User joins the Minecraft server.
2. Uses `/register` or `/link` to begin registration.
3. Receives a secure, temporary pairing challenge.
4. Opens the website and signs in or creates an account.
5. Completes the pairing process.
6. The system links their verified in-game identity to their website account.

Registration, authentication, account linking and approval must have separate security checks.

Do not treat a submitted Minecraft username as proof of ownership.

## 3. Minecraft integration

The existing server runs:

- Ubuntu Server 26.04.1 LTS.
- Minecraft Java Edition 1.21.1.
- Fabric Loader 0.20.1.
- Java 21.
- Crafty Controller 4.11.0 in Docker.
- playit.gg for public Minecraft access.
- Automated Minecraft backups every six hours.

Public gameplay address:

`impairment-entering.tun.ply.gg`

Build a lightweight Minecraft integration layer.

Prefer a small server-side Fabric mod if necessary for secure player identity verification, statistics collection and in-game commands.

Requirements:

- Compatible with Minecraft Fabric 1.21.1.
- Server-side installation only wherever possible.
- No required client-side mod.
- No changes to vanilla technical redstone behaviour.
- Compatible with future Carpet and Carpet TIS Addition installation.
- No unnecessary mixins or modifications to Minecraft mechanics.
- Secure communication with the local Ubuntu agent.
- No direct access from Minecraft clients to Supabase service-role credentials.

Implement or provide a safely deployable foundation for:

- `/register`
- `/link`
- `/verify`
- `/profile`
- `/unlink`

Use commands only where appropriate, and do not transmit passwords, email addresses or long-lived authentication tokens through public chat.

If implementing the Fabric integration is substantial, work on it as a separate, fully tested module rather than delivering an insecure placeholder.

## 4. Player profiles and statistics

Build player profile pages showing available real server data:

- Minecraft username and avatar.
- Online/offline status.
- Playtime.
- First joined and last seen.
- Death count.
- Mob kills.
- Blocks mined.
- Advancement progress.
- Server role.
- Permissions.
- Recent activity.
- Leaderboards.

Only display metrics actually collected or reliably obtained from Minecraft.

Do not fabricate player statistics.

Use stable player identifiers, not usernames alone, for data ownership and historical records.

Provide sensible privacy controls for information visible to other players.

## 5. Roles and permissions

Implement owner-managed access control.

Default roles:

**Owner**
- Full management.
- Approve and reject accounts.
- Assign roles.
- Manage permissions.
- Configure integrations and security.
- View audit logs.

**Admin**
- Approved operational controls.
- Player moderation.
- Server management according to assigned privileges.

**Moderator**
- Limited player management.
- View relevant server activity.
- No unrestricted console or system access.

**Member**
- View permitted server information.
- View personal statistics.
- Join the server when authorised.

**Pending**
- Complete registration and account linking.
- View approval status.
- No privileged server controls.

Support granular permissions beyond the default role names.

Every permission must be enforced server-side, including through Supabase Row Level Security and trusted backend authorisation.

Never trust browser-supplied roles or editable user metadata.

## 6. Dashboard frontend

Use React, TypeScript and Vite, hosted through GitHub Pages.

Build a modern, responsive, Aternos-inspired interface with original visual design.

Core features:

- Google sign-in.
- Optional email/password registration.
- Account linking and approval.
- Server dashboard.
- Minecraft server status.
- Online players.
- Player profiles and statistics.
- Start, stop and restart controls.
- Restricted console viewer.
- Approved moderation actions.
- Backup history and status.
- Server activity and audit logs.
- Administration and permissions.
- Mobile-friendly layout.
- Clear loading, error, offline and connection states.

Prioritise a clean interface with intuitive navigation, good spacing, accessible controls and consistent visual styling.

Avoid cluttered interfaces and non-functional mock controls.

## 7. Supabase backend

Use the existing connected Supabase integration.

Create a new project if permitted by the account and free-plan limits. The previous inspection found three inactive projects and no Minecraft project, so check actual project eligibility before attempting creation.

Implement:

- Supabase Auth.
- PostgreSQL.
- Secure Row Level Security policies.
- Player profiles and linked Minecraft identities.
- Owner approval workflow.
- Role and permission tables.
- Reliable command queue.
- Command execution results.
- Agent registration and authorisation.
- Audit logs.
- Player statistics.
- Efficient presence and server-status updates.
- Database migrations.
- Retention policies.

Use proper server-side authorisation, replay protection, expiry, idempotency and rate limiting.

Do not expose privileged Supabase keys in the frontend.

Do not enable unrestricted anonymous database access.

## 8. Ubuntu background agent

Build the Ubuntu agent using a maintainable language such as Python.

Requirements:

- Runs as a systemd service.
- Starts automatically after reboot.
- Uses outbound connections only.
- Works behind CGNAT.
- Integrates securely with Crafty.
- Does not expose Crafty's HTTPS dashboard publicly.
- Validates Crafty's TLS certificate rather than disabling certificate verification.
- Implements narrowly scoped Minecraft operations.
- Uses persistent execution state to prevent unsafe command replay.
- Includes reconnect backoff, health reporting and structured logs.
- Never exposes arbitrary shell execution to website users.
- Continues operating safely when Supabase is unavailable.
- Does not interfere with Minecraft, Fabric, backups or playit.gg.

Prepare installation scripts and exact Ubuntu commands.

**Do not install the agent or modify the existing Ubuntu Minecraft server until you present the installation plan and receive my separate approval.**

Cloud components may be implemented and deployed independently.

## 9. Optional unofficial Minecraft client support

I would like the option to allow Minecraft clients that do not authenticate through official Microsoft/Mojang services.

However, prioritise account security.

For the initial implementation:

- Preserve `online-mode=true`.
- Preserve existing UUIDs, inventories and permissions.
- Do not enable offline mode without explicit approval.
- Research hybrid authentication options compatible with Fabric 1.21.1.
- Assess impersonation risks, UUID migration, account takeover, operator privileges and inventory ownership.
- Design the authentication layer to accommodate a future secure hybrid mode.
- Do not install cracked-client authentication mods yet.

Present a separate, thoroughly reviewed migration plan if unofficial-client support becomes feasible.

## 10. Free-tier requirements

Keep the entire system within free services:

- GitHub Pages.
- Supabase Free.
- Existing Ubuntu hardware.
- Existing Crafty installation.
- Existing playit.gg free tunnel.

No paid domains, subscriptions or hosting.

Monitor and limit:

- Database size.
- Supabase egress.
- Realtime messages and connections.
- Authentication email delivery.
- Function invocations.
- Logging volume.
- Storage usage.

Minecraft must continue running independently if Supabase is paused, unavailable or rate-limited.

## 11. Use your tools autonomously

You have access to GitHub and Supabase and may have Computer Use/browser capabilities.

Use them to:

1. Create and configure the new GitHub repository.
2. Create and configure the Supabase project, where free-tier eligibility allows.
3. Build the complete frontend and backend.
4. Configure Google OAuth where authorised.
5. Implement database migrations and RLS.
6. Build the Ubuntu agent and Fabric integration.
7. Create tests and CI workflows.
8. Deploy GitHub Pages.
9. Run security and functional tests.
10. Produce installation and maintenance documentation.

Do not ask me to manually perform something you can safely complete using your tools.

If a tool requires user authentication, account consent, payment or other unavoidable interaction, explain the exact required action.

Do not make irreversible changes without appropriate safeguards.

## 12. Execution instructions

Continue directly from the architecture already prepared.

You have my approval to implement the cloud application, repository, deployment workflows and database components.

You may skip further brainstorming and proceed with engineering.

Use sensible defaults for minor design decisions without repeatedly asking me questions.

Deliver working, tested features rather than placeholders.

Work in coherent milestones, using Codex's available execution and verification capabilities.

At each major milestone, report:

- What was implemented.
- Repository and deployment links.
- Test results.
- Security checks.
- Any blockers.
- Next implementation steps.

Do not claim success for untested or incomplete functionality.

**Primary goal:** Deliver a secure, polished, completely free Minecraft community dashboard that unifies website accounts, Minecraft player identities, statistics and server management, without disrupting the existing working Minecraft server.