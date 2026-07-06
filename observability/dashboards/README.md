# Grafana dashboards

Import into Grafana Cloud: **Dashboards → New → Import → Upload JSON**, then pick
your Prometheus (Mimir) data source when prompted.

- `norviq-overview.json` — node CPU/memory, per-pod container CPU/memory, restarts.

Notes:
- Node + container panels use metrics Alloy already ships (`node_*` from the unix
  exporter, `container_*` from cAdvisor).
- The "Pod restarts" panel needs `kube_pod_container_status_restarts_total`
  (kube-state-metrics), which is intentionally **not** deployed (10k-series free
  tier). Deploy kube-state-metrics later if you want that panel to populate.
