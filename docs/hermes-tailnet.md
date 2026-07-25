# Hermes over Tailscale — how the path works, and how it broke

The backend reaches the hermes VPS over Tailscale: the VPS `finance-api`
binds to its **tailnet address only** (never the public internet), so
`HermesSyncJob` must egress through the tailnet. Three things must all be
true, and each one has broken at least once:

| # | Requirement | Where it lives | Failure signature |
|---|---|---|---|
| 1 | `HERMES_BASE_URL` points at a live hermes address | sealed `secrets/production/api-env.yaml` | `connectTimeout` (dead IP after a VPS rebuild) |
| 2 | Pods can **resolve** the hermes name | `cluster/coredns/custom.yaml` | `DNS error … UnknownHost` |
| 3 | Pods can **route** to the tailnet | `cluster/networking/tailnet-snat.yaml` **+ tailscale on the node** | `connectTimeout` |

Requirement 3 is the subtle one and has two halves:

- **The node must be a tailnet member.** Provisioned via
  `terraform/cloud-init/k3s-node.yaml.tftpl` (set `tailscale_authkey`).
  Hetzner user-data is immutable on a running server and Terraform has
  `ignore_changes = [user_data]`, so on an **already-running** node install
  it once by hand:

  ```sh
  ssh root@<node>            # k3s node, not the hermes VPS
  curl -fsSL https://tailscale.com/install.sh | sh
  tailscale up --authkey=tskey-auth-… --hostname=norviq-green --accept-dns=false
  tailscale ip -4            # expect a 100.x address
  ```

  `--accept-dns=false` on purpose: the node keeps its own resolver and pods
  resolve hermes through the CoreDNS entry instead.

- **Pod egress must be SNAT'd to the tailnet address.** flannel masquerades
  pod egress to the node's *public* IP, and tailscaled drops tunnel packets
  whose source is not a tailnet address. The `tailnet-snat` DaemonSet
  inserts `-t nat -I POSTROUTING 1 -s 10.42.0.0/16 -d 100.64.0.0/10 -j SNAT
  --to-source <tailscale0 IP>` and re-asserts it every 60s. It is a no-op
  until tailscale exists on the node.

## Diagnosing quickly

```sh
# Is the node on the tailnet? (expect a 100.x address on tailscale0)
kubectl run t --rm -i --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"hostNetwork":true}}' -- ip -o -4 addr show

# Can a POD reach hermes? (this is the one that regressed silently)
kubectl run t --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -q -T5 -O- http://<hermes-tailnet-ip>:8780/healthz

# Is the SNAT rule installed?
kubectl logs -n kube-system ds/tailnet-snat --tail=5

# End to end
curl -s https://api.norviq.org/health/ready | jq .checks.hermes
kubectl logs -n production deploy/api --since=30m | grep hermes_sync
```

Healthy looks like `hermes_sync ok events=… ticker_posts=…` every 15 min and
`hermes: healthy` in readiness.

## History

- The legacy docker-compose stack could reach the tailnet because docker's
  bridge masquerades differently. The k3s cutover silently removed that, and
  hermes sync has been down on the cluster ever since.
- After each hermes VPS rebuild the tailnet IP changes. `HERMES_BASE_URL` is
  now a MagicDNS name (`hermes-vps-2.tail562587.ts.net`) so only the hosts
  entry in `cluster/coredns/custom.yaml` needs the new IP — no resealing.
  Keep the VPS hostname stable across rebuilds.
