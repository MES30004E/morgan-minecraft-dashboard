# Morgan Minecraft Dashboard

Live frontend: https://mes30004e.github.io/morgan-minecraft-dashboard/

React/TypeScript on GitHub Pages, Supabase Auth/PostgreSQL/RLS/Realtime, an outbound-only Python Crafty agent, and an optional server-only Fabric identity/statistics bridge. Browser users need no client software. Current roles are configurable permission templates; database RPCs enforce current membership, operation allowlists, expiry, rate limits and replay protection.

**The cloud is deployed; the Ubuntu agent and Fabric module are not installed.** No real Minecraft control, linking or statistics collection has been verified yet. Controls stay unavailable without a fresh agent heartbeat. Owner Google login has been tested. Google audience publication and SMTP delivery have separate setup requirements; see the deployment record.

Review [Ubuntu installation](docs/ubuntu-installation.md) before approving any laptop changes. See [cloud status](docs/cloud-status.md), [maintenance](docs/maintenance.md), [archive recovery](docs/archives.md) and [archive protocol](docs/archive-cloud.md).

## Verification

```bash
npm ci
npm test
npm run build
python3 -m venv .venv
.venv/bin/pip install --require-hashes -r agent/requirements.lock
PYTHONPATH=agent .venv/bin/python -m unittest discover -s agent/tests -v
```

Database CI applies every migration on PostgreSQL 17 and tests RLS, role changes, rate limits, identity pairing, archive failures, statistics privacy, retention replay and a real concurrent permission-revocation race. Fabric CI builds on Java 21 and runs authenticated bridge protocol tests. GitHub Pages deployment requires all these checks. Never commit `.env`, credentials, service-role keys, user exports or archive keys.
