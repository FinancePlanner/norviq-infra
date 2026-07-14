# norviq-infra

GitOps + IaC for the Norviq/StockPlan platform: one Hetzner VPS (2 vCPU/4 GB)
running k3s, deployed by ArgoCD, provisioned by Terraform, observed via
Grafana Cloud.

```
terraform/   hcloud server, primary IP, firewall, PG volume (state: HCP Terraform)
cluster/     addons: argocd (core), cert-manager, sealed-secrets, alloy, traefik cfg
charts/app   shared Helm chart for api + web
apps/        per-service values (CI bumps image.tag) + data layer (pg, redis, backups)
argocd/      root app-of-apps + child Applications
secrets/     SealedSecrets (committable) — see secrets/README.md
docs/        runbooks + legacy gateway reference
```

## Bootstrap order (fresh box)

1. `cd terraform && terraform init && terraform apply` (needs HCP login + `TF_VAR_hcloud_token`)
2. Fetch kubeconfig: `ssh root@<ip> cat /etc/rancher/k3s/k3s.yaml` → replace `127.0.0.1` with the IP
3. `kubectl apply -k cluster/argocd`
4. `kubectl apply -f argocd/root.yaml` — ArgoCD takes over everything else
5. Seal secrets per `secrets/README.md`, commit, wait for sync
6. **Back up the sealing key** (secrets/README.md)

## Deploy flow

- Merge to `main` in FinanceBackend / StockPlanWeb → CI pushes `ghcr.io/...:<sha>`,
  bumps `apps/<svc>/values-staging.yaml` → ArgoCD rolls **staging** (~3 min).
- Production: run the **Promote to Production** workflow → merge the PR.
- Rollback: revert the promote PR (or `kubectl -n production rollout undo deploy/<svc>` in emergencies).

## Runbooks

- [Cutover (blue → green)](docs/runbook-cutover.md)
- [Rollback](docs/runbook-rollback.md)
- [Restore drill](docs/runbook-restore-drill.md)
- [Disaster recovery](docs/runbook-disaster-recovery.md)
- [Advanced reporting](docs/runbook-advanced-reporting.md)
