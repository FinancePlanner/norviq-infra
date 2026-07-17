# Runbook: production cutover (in-place, blue compose box → k3s ON blue)

**Decision (2026-07-17):** consolidate to ONE VPS. k3s is installed **on the blue
box `168.119.156.43`** (rescaled to cx33), the compose stack is replaced in place,
and the green rehearsal box `178.105.73.13` is deleted afterward. The api/web/mcp
DNS records already point at blue, so **DNS does not change** — this removes the
whole "flip DNS + pre-copy certs" risk of the old green-promotion plan.

Green stays as the throwaway rehearsal cluster until the very end (proves the
manifests, times the restore), then is deleted.

## Hard prerequisite — rescale blue FIRST

The current blue box (cx23, 2 vCPU / 4 GB / 40 GB) already runs the compose prod
stack and **cannot** also host k3s + Postgres + Redis + api/web/mcp. Rescale it to
**cx33 (4 vCPU / 8 GB / 80 GB)** in the Hetzner console **before** starting the
cutover:

1. Console → project → server `stock-plan-server` → **Snapshots** → take snapshot
   `pre-cx33-rescale` (rollback point).
2. **Power off** → **Rescaling** → **cx33** → choose the **disk-upgrade** option
   (80 GB). ⚠️ Disk grow is irreversible. IP `168.119.156.43` is retained.
3. **Power on**, confirm the compose stack returns healthy. Prod keeps running on
   compose until the cutover window.

## Other preconditions

- Staging verified on green for a few days; `scripts/migrate-db.sh rehearse`
  run and timed (rehearsed 2026-07-16: 176 tables in 5 s).
- DNS TTL for the api/web/mcp hosts lowered to 300 s a day prior (belt-and-suspenders;
  DNS does not actually change, but keeps rollback fast if anything DNS-adjacent moves).
- Green's sealed-secrets private key backed up (see step 2) — without it every
  SealedSecret in this repo is undecryptable on blue's fresh cluster.

Window: evening, ~30–60 min (dominated by k3s install + dump/restore).

## Cutover steps

1. **Snapshot blue** again (fresh rollback point) — Hetzner console.
2. **Back up green's sealed-secrets key** and keep it off-box:
   ```bash
   KUBECONFIG=~/.kube/norviq kubectl -n kube-system get secret \
     -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml
   ```
3. **Stop writes on blue** (nginx serves 503; iOS clients retry):
   ```bash
   ssh root@168.119.156.43 'cd /opt/stockplan && docker compose -p prod -f docker-compose.production.yml stop app'
   ```
4. **Final prod dump** off blue (reads the real username from the container env —
   do NOT hardcode; the prod .env is the source of truth):
   ```bash
   ssh root@168.119.156.43 'cd /opt/stockplan && docker compose -p prod -f docker-compose.production.yml exec -T db sh -c "pg_dump -Fc -U \$POSTGRES_USER \$POSTGRES_DB"' > prod-final.dump
   ```
   Copy the dump off-box (laptop) before proceeding.
5. **Tear down compose to free ports 80/443** (k3s Traefik needs them; point of no
   return without the snapshot):
   ```bash
   ssh root@168.119.156.43 'cd /opt/stockplan && docker compose -p prod -f docker-compose.production.yml down && docker compose -p dev -f docker-compose.dev.yml down 2>/dev/null; docker ps'
   ```
6. **Install k3s on blue**, then restore the sealed-secrets key from step 2
   **before** the sealed-secrets controller first starts, then install the platform
   (ArgoCD, cert-manager, Traefik, sealed-secrets) via the same Terraform/Helm path
   that built green — retargeted at blue's IP.
7. **ArgoCD sync** in order: `data` (Postgres/Redis) → `staging` → `production`.
8. **Restore the prod dump** into blue's k3s Postgres:
   ```bash
   kubectl -n data cp prod-final.dump postgres-0:/tmp/final.dump
   kubectl -n data exec postgres-0 -- sh -c 'pg_restore --clean --if-exists --no-owner --no-privileges -U "$POSTGRES_USER" -d stockplan_production /tmp/final.dump && rm /tmp/final.dump'
   ```
9. **Prod dedicated DB role** (prod api hits the same `stockplan_user` blacklist in
   `ProductionConfiguration.unsafeUsernames` that crashlooped staging). Create
   `norviq_api_prod`, transfer ownership of the restored `public` objects to it
   (same idempotent pattern as the staging fix — loop `ALTER ... OWNER`, never
   `REASSIGN OWNED`, which fails on the DB object), then reseal
   `secrets/production/api-env.yaml` `DATABASE_USERNAME`/`DATABASE_PASSWORD` and let
   the prod api pod restart onto the new creds.
10. **DNS unchanged** — api/web/mcp already resolve to `168.119.156.43`. cert-manager
    issues fresh TLS via HTTP-01 (works because DNS already points here).
11. **Verify**: `kubectl get pods -A` all Running; `curl https://api.<host>/health/ready`;
    web login session; MCP auth round-trip; iOS smoke; RevenueCat webhook delivery;
    Grafana Cloud shows prod metrics; Sentry quiet.
12. **Rollback** (if needed): restore the step-1 blue snapshot → compose prod returns
    on the same IP in minutes, no DNS involved. Writes made on k3s after cutover are
    lost on snapshot rollback unless you dump them back first — decide before rolling back.
13. **T + ~1–2 weeks**, once stable: **delete green** in the Hetzner console (ends its
    billing; snapshot it first if you want a keepsake). Delete legacy compose deploy
    workflows: backend `deploy.yml`, `deploy-dev.yml`; web `deploy.yml` +
    `scripts/deploy/on-server.sh`.
