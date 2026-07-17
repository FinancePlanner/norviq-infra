# Runbook: production cutover (blue compose box → green k3s box)

**Decision (2026-07-17): Option B.** The green k3s box `178.105.73.13` becomes the
sole production host and the blue compose box `168.119.156.43` is deleted after
verification. Green already runs k3s + staging + a mostly-built `production`
namespace and keeps its own sealed-secrets key, so there is **no key migration**
and the prod DB-user problem is already solved (prod `api-env` uses
`stockplan_production_app`, not the blacklisted `stockplan_user`).

The one thing this costs vs. staying on blue's IP: a **Namecheap DNS change** to
point the hostnames at green. Everything else is prep that runs with zero user
impact while DNS still points at blue.

## Prerequisites (do before the window)

1. **Rescale green** cpx22 → **cx33** (4 vCPU / 8 GB / 80 GB) in the Hetzner
   console. Green is now the keeper and 4 GB won't comfortably hold
   prod + staging + platform. Snapshot first; disk-grow is irreversible; IP kept.
2. **Promote web + mcp to production** (they fail ArgoCD with empty `image.tag`
   until then): run `.github/workflows/promote.yml` (service=`all`) or merge the
   equivalent promote PR. Confirm `web-production` and `mcp-production` go
   Synced/Healthy. `api-production` is already Running.
3. **Lower DNS TTL** to 300 s for `api.norviq.org`, the web host, `mcp.norviq.org`,
   `norviq.org` at least a day prior.
4. **Rehearse the DB restore**: `BLUE_HOST=root@168.119.156.43 KUBECONFIG=~/.kube/norviq
   scripts/migrate-db.sh rehearse` (non-destructive; rehearsed 2026-07-16 = 176
   tables in 5 s). Note: green's `stockplan_production` currently has the schema
   but **no real data** — the real data is copied in the window (step 3 below).

## Cutover window (~20–30 min, dominated by dump/restore)

1. **(Optional) Pre-copy TLS** to avoid a brief HTTPS gap. The prod cert on green
   (`api-norviq-org-tls`) cannot issue until DNS points at green (cert-manager
   HTTP-01). Either accept a ~1–2 min gap after the flip, or seed blue's live
   certs first:
   ```bash
   scp root@168.119.156.43:/etc/letsencrypt/live/api.norviq.org/{fullchain.pem,privkey.pem} .
   KUBECONFIG=~/.kube/norviq kubectl -n production create secret tls api-norviq-org-tls \
     --cert=fullchain.pem --key=privkey.pem --dry-run=client -o yaml | kubectl apply -f -
   # repeat per public host (web, mcp) into its chart-convention <host-dashes>-tls secret
   ```
2. **Stop writes on blue** (nginx keeps serving 503; iOS clients retry):
   ```bash
   ssh root@168.119.156.43 'cd /opt/stockplan && docker compose -p prod -f docker-compose.production.yml stop app'
   ```
3. **Final dump blue → restore into green** (real prod data):
   ```bash
   BLUE_HOST=root@168.119.156.43 KUBECONFIG=~/.kube/norviq scripts/migrate-db.sh final
   ```
   (`final` restores into `stockplan_production` with `--clean --if-exists --no-owner`.)
4. **Re-assert ownership** of the restored objects to `stockplan_production_app`
   (the restore is `--no-owner`, so tables land owned by the superuser and prod
   migrations/writes would fail). Run the idempotent ownership-transfer SQL
   (`docs/sql/prod-owner-fix.sql` — loops `ALTER ... OWNER`, never `REASSIGN
   OWNED`, which errors on the DB object). Let the prod api pod restart.
5. **Flip DNS (Namecheap)**: A/AAAA for `api.norviq.org`, the web host,
   `mcp.norviq.org`, `norviq.org` → `178.105.73.13`.
6. **Verify**: cert-manager issues/serves valid TLS; `curl https://api.norviq.org/health/ready`;
   web login session; MCP auth round-trip; iOS login smoke; RevenueCat/Stripe
   webhook delivery; Grafana Cloud shows prod metrics; Sentry quiet.
7. **Keep blue stopped (not deleted) ~1–2 weeks** as rollback. Rollback = revert
   DNS + `docker compose -p prod ... start app` (minutes). Writes made on green
   after cutover are lost on rollback unless you dump green → blue first — decide
   before rolling back.
8. **T + ~1–2 weeks, stable**: snapshot then **delete blue** in the Hetzner
   console. Delete legacy compose deploy workflows: backend `deploy.yml`,
   `deploy-dev.yml`; web `deploy.yml` + `scripts/deploy/on-server.sh`.
