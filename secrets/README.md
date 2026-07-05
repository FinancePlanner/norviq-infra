# Secrets (SealedSecrets)

Only `SealedSecret` resources are committed here — they are safe in git; only
the in-cluster controller can decrypt them. The `*.example.yaml` files show the
required keys; real sealed files replace them after the cluster exists.

## Sealing a secret

```bash
# once: install kubeseal locally (brew install kubeseal)
kubectl create secret generic api-env -n production \
  --from-env-file=.env.production --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > secrets/production/api-env.yaml
```

Repeat per namespace/secret. Commit the output; ArgoCD applies it; the
controller materializes the real `Secret`.

## Inventory

| File | Namespace | Keys |
|---|---|---|
| `staging/api-env.yaml` | staging | DATABASE_USERNAME, DATABASE_PASSWORD, JWT_SECRET, OAUTH_APPLE_*, APNs, Resend, … (everything secret from `.env.development`) |
| `production/api-env.yaml` | production | same, production values |
| `staging/web-env.yaml` | staging | SESSION_SECRET, SENTRY_DSN, POSTHOG_PROJECT_TOKEN, REVENUECAT_WEB_API_KEY |
| `production/web-env.yaml` | production | same, production values |
| `staging/web-staging-htpasswd.yaml` | staging | `users` (htpasswd line, `htpasswd -nb user pass`) |
| `data/postgres-credentials.yaml` | data | POSTGRES_USER, POSTGRES_PASSWORD |
| `data/backup-config.yaml` | data | RCLONE_CONFIG (Storage Box SFTP), AGE_PUBLIC_KEY |
| `observability/grafana-cloud.yaml` | observability | PROM_URL, PROM_USER, LOKI_URL, LOKI_USER, TEMPO_URL, TEMPO_USER, GC_API_KEY |

Note: the api pods read DATABASE_HOST/PORT/NAME from plain values env; only
username/password live in the secret.

## CRITICAL: back up the sealing key

Losing the sealing keypair means re-sealing everything from source values.
After bootstrap, and after any key rotation:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealing-key-backup.yaml
# age-encrypt and store off-site (Storage Box + password manager)
```

The weekly cluster-state backup CronJob also captures it.
