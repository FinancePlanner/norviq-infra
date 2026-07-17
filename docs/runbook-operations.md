# Runbook: day-to-day operations (green k3s / GitOps)

Single production host: **green `178.105.73.13`** running k3s + ArgoCD. Everything
is GitOps — you change git, ArgoCD (on the box) reconciles git → cluster. Nothing
pushes to the cluster, so no server IP or SSH key lives in the deploy path.

## Which layer do I touch?

| Change | Layer | Where | Frequency |
|---|---|---|---|
| Ship a new app version | image tag | `promote.yml` workflow → `apps/<svc>/values-production.yaml` | often |
| App config (URL, flag, tuning) | values `env:` | `apps/<svc>/values-production.yaml` | common |
| A credential / key | sealed secret | `secrets/production/*.yaml` | as needed |
| Replicas, CPU/mem, probes, ingress hosts, volumes | Helm chart | `charts/app/` + values | occasional |
| Box size, add a node, k3s version, cluster addons | Terraform | `terraform/` (TF Cloud "NorviqInfra") | rare |

A normal release touches **neither Terraform nor the chart** — just an image-tag bump via the promote PR.

## Deploy a new version (the flow)

1. Merge code to `main` in norviq-backend/web/mcp → `ci.yml` builds + tests.
2. Run **`deploy-k3s.yml`** (Actions → Run workflow) — builds the image, pushes to
   GHCR, records the git-sha tag in `apps/<svc>/values-staging.yaml`.
3. Run **`promote.yml`** (service = api/web/mcp/all) — copies that tag into
   `values-production.yaml`, opens a promote PR.
4. **Merge the promote PR** → ArgoCD deploys it to the `production` namespace.

Rollback = **revert the promote PR** (ArgoCD redeploys the previous tag).

## Set a new env variable

**Non-secret** (URL, flag, number) — edit the app's values:
```yaml
# apps/api/values-production.yaml
env:
  - name: MY_FLAG
    value: "true"
```
Commit → ArgoCD applies → pod rolls.

**Secret** (key, password, token) — seal it into `secrets/production/api-env.yaml`:
```bash
# one-time: fetch the cluster's public seal cert
KUBECONFIG=~/.kube/norviq kubeseal --fetch-cert \
  --controller-name sealed-secrets-controller --controller-namespace kube-system > cert.pem

# seal ONE value (bound to namespace + secret name)
printf %s 'the-secret-value' | kubeseal --raw \
  --namespace production --name api-env --cert cert.pem
```
Paste the `AgB...` output under `encryptedData:` as `MY_KEY: AgB...`, commit.
ArgoCD → the sealed-secrets controller decrypts it into the real `api-env` Secret.
The api reads env at **startup**, so load it:
```bash
KUBECONFIG=~/.kube/norviq kubectl -n production rollout restart deploy/api
```

## How sealed secrets work

Secrets live in git **encrypted** (`AgB...`). Only the in-cluster controller holds
the private key to decrypt; you seal with the public cert from anywhere. A sealed
value is bound to a specific `--namespace` + `--name`, so it only decrypts into
that Secret. `kubeseal --raw` seals a single value to paste into the SealedSecret.

## Seeing what's happening — without SSH

- **Grafana Cloud** (already wired; Alloy ships logs/metrics/traces): your primary
  window. Explore → **Loki** `{namespace="production"}` for live logs, **Prometheus**
  for metrics, **Tempo** for traces.
- **k9s** (`brew install k9s`): terminal dashboard — pods, logs, exec, restarts.
  `KUBECONFIG=~/.kube/norviq k9s`.
- **ArgoCD UI**: deploy/sync/health + sync & rollback buttons (see below).
- Optional desktop cluster GUIs: **Headlamp** (free) or **Lens**.

## ArgoCD UI

ArgoCD here is the **core install (no built-in web server)** to save RAM. Two ways
to get the UI:

**On demand, zero server RAM (recommended for this box):**
```bash
KUBECONFIG=~/.kube/norviq argocd admin dashboard -n argocd
# opens the full ArgoCD UI at http://localhost:8080 for as long as it runs
```
(Install the CLI: `brew install argocd`.)

**Permanent URL (`argocd.norviq.org`)** — requires deploying the argocd-server
component (~100 MB RAM) + an ingress + a DNS record. See
`cluster/argocd/` if enabled. Only worth it if you want always-on access.

In the UI: each Application (`api-production`, `web-production`, `data`, …) shows
**Sync** (Synced/OutOfSync) and **Health** (Healthy/Degraded). Click one for its
resource tree (Deployment → ReplicaSet → Pod), the live-vs-git **diff**, a **Sync**
button to force reconcile, and **History/Rollback** to redeploy a prior git revision.

## Handy commands (KUBECONFIG=~/.kube/norviq)

```bash
kubectl -n production get pods                      # prod health
kubectl -n production logs deploy/api --tail=100    # api logs (or use Grafana)
kubectl -n argocd get applications                  # sync/health of everything
kubectl -n production rollout restart deploy/api    # reload after a secret change
argocd --core app list                              # ArgoCD state from the CLI
```
