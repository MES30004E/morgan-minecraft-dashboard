# Morgan Minecraft Dashboard

Implementation in progress. **There is no deployed dashboard yet.**

## Verified milestone

The Python agent safety core validates a strict operation envelope and uses a
durable SQLite journal before dispatch. Duplicate deliveries are suppressed,
including across restarts. Lost responses and execution exceptions remain
`uncertain`, requiring reconciliation instead of automatic replay.

This module is not yet an installed agent or a Crafty integration. Do not connect
an executor until database authorization, agent identity, expiry and Crafty TLS
verification are implemented and tested together. Keep its journal on persistent
local storage with permissions restricted to the service user.

Run the tests from this directory:

```sh
PYTHONPATH=agent python3 -m unittest discover -s agent/tests -v
```

## Next milestones

See `docs/superpowers/plans/2026-11-10-dashboard.md` and `docs/requirements.md`.
Supabase project provisioning and the initial database/RLS migration are complete.
See `docs/cloud-status.md` for the verified scope. Google OAuth, verified email delivery,
frontend, Fabric integration, systemd service and end-to-end tests remain open.

No Ubuntu server changes are authorized until the installation plan has been
presented and separately approved. Preserve online-mode=true and existing worlds.
