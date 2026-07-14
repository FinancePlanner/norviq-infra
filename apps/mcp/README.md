# norviq-mcp deployment

Remote MCP server (Go, Streamable HTTP, container port 8087). Uses the shared
`charts/app` chart, same as `api` and `web`.

- Image: `ghcr.io/financeplanner/norviq-mcp` (private — `ghcr-pull` already present in both namespaces).
- Health: `/healthz` (liveness), `/readyz` (readiness).
- Metrics: `/metrics` (scraped through the shared pod annotations).
- Hosts: `dev-mcp.norviq.org` (staging), `mcp.norviq.org` (production).
- Talks to the backend in-cluster at `http://api:8080`.
- ArgoCD apps: `argocd/apps/mcp-staging.yaml`, `argocd/apps/mcp-production.yaml` (auto-discovered by the root app).

## One-time manual steps (need cluster / DNS / CI access)

1. **DNS** — create A records `dev-mcp.norviq.org` and `mcp.norviq.org` → the cluster IP (DNS is manual in this repo; cert-manager issues TLS once the host resolves).

2. **Introspection secret** — pick one shared value used by BOTH the backend and mcp:
   - Add `MCP_INTROSPECTION_SECRET` to the existing `api-env` sealed secret in both envs (re-seal the whole secret; SealedSecrets can't append a single key by hand).
   - Create the `mcp-introspection` sealed secret with the same value (see `secrets/{staging,production}/mcp-introspection.example.yaml`):
     ```sh
     echo "MCP_INTROSPECTION_SECRET=<shared-secret>" > .env.mcp
     kubectl create secret generic mcp-introspection -n staging --from-env-file=.env.mcp \
       --dry-run=client -o yaml \
       | kubeseal --controller-name sealed-secrets-controller \
                  --controller-namespace kube-system -o yaml \
       > secrets/staging/mcp-introspection.yaml
     # repeat with -n production > secrets/production/mcp-introspection.yaml
     ```

3. **Staging image tag** — add an `INFRA_DEPLOY_TOKEN` Actions secret to
   `norviq-mcp` with contents-write access to `norviq-infra`. MCP CI then
   writes `image.tag: <git-sha>` into `apps/mcp/values-staging.yaml` on
   every merge to main.

4. **Production promote** — `.github/workflows/promote.yml` now offers `mcp` (and `all`); run it to copy the staging tag into `values-production.yaml` and open the deploy PR.

5. **SSE note** — Traefik does not buffer responses, so the streamable-HTTP `/mcp` endpoint works out of the box. If long-lived streams get cut, add read/idle-timeout router options via `ingress.annotations` in the values.

6. **VPS Compose rollout** — configure the `norviq-mcp` production
   environment with `SERVER_HOST`, `SERVER_USER`, and `SERVER_SSH_KEY`,
   then set the repository variable `COMPOSE_DEPLOY_ENABLED=true`. The
   server's `/opt/stockplan/.env.production` must contain the shared
   `MCP_INTROSPECTION_SECRET` and may override `MCP_DOMAIN`.
