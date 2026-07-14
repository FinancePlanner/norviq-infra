# Runbook: advanced reporting

The API generates Advanced Reporting Center PDF and XLSX artifacts. PDF
conversion is handled by an internal Gotenberg service; generated files stay on
a dedicated retained PVC mounted only by the API.

## Topology and configuration

| Component | Configuration | Purpose |
| --- | --- | --- |
| API | `ADVANCED_REPORT_STORAGE_PATH=/var/lib/norviq/advanced-reports` | Private artifact storage |
| API | `GOTENBERG_BASE_URL=http://gotenberg:3000` | In-cluster PDF conversion |
| API | `PUBLIC_API_BASE_URL` | Base URL embedded in signed delivery links |
| API | `REPORT_DOWNLOAD_SIGNING_SECRET` | HMAC key for expiring download links |
| Gotenberg | ClusterIP service on port 3000 | Internal-only HTML-to-PDF renderer |

Gotenberg has no Ingress and must not be exposed publicly. The API's advanced
report PVC is independent of the existing tax-report PVC so the stores can be
sized and restored separately. Both PVCs use Helm's `keep` resource policy.

| Environment | Advanced-report PVC |
| --- | ---: |
| staging | 2 GiB |
| production | 10 GiB |

## Retention and privacy

The API's `AdvancedReportRetentionJob` removes artifact files after 90 days and
report-run metadata after one year. It runs hourly by default. Change its
interval only with `ADVANCED_REPORT_CLEANUP_INTERVAL_SECONDS`; do not disable
it without adding an equivalent cleanup mechanism.

The artifact directory is not served by the web server. Downloads pass through
the authenticated API or a short-lived HMAC-signed URL. Gotenberg receives
render input only over the cluster network and has no persistent volume.

## Health checks

```sh
kubectl -n staging get deploy,svc,pvc api gotenberg
kubectl -n staging get pods -l app.kubernetes.io/instance=gotenberg
kubectl -n staging port-forward svc/gotenberg 3000:3000
curl -fsS http://127.0.0.1:3000/health
```

Repeat in `production` after promotion. For generation failures, inspect both
services while preserving report contents and recipient data:

```sh
kubectl -n production logs deploy/api --since=30m | grep advanced_report
kubectl -n production logs deploy/gotenberg --since=30m
```

## Rotate the download signing key

Rotation immediately invalidates every outstanding signed report URL. Stored
files and authenticated downloads remain available until normal retention.
Generate a different value for each environment and never write plaintext into
Git:

```sh
openssl rand -hex 32 | kubeseal --raw \
  --from-file=REPORT_DOWNLOAD_SIGNING_SECRET=/dev/stdin \
  --name report-download-signing --namespace staging --scope strict
```

Put the ciphertext in
`secrets/staging/report-download-signing.yaml`, validate it with
`kubeseal --validate`, commit, and wait for the secrets and API applications to
sync. Repeat for production with a new value and the production namespace.

## Backup and restore

The database backup contains report definitions, schedules, runs, and artifact
metadata. The artifact PVC contains the PDF/XLSX bytes. Include
`api-advanced-reports` in volume snapshots or file-level backups when report
downloads must survive a full cluster rebuild. Restore the database and PVC to
the same logical point in time; orphaned files are harmless, while metadata
without a restored file produces a missing-artifact download until regenerated.
