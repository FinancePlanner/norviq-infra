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

## Adding one key to an existing secret

Re-sealing the whole file needs every plaintext value and rewrites every line.
To add a single key, encrypt just that value and paste the blob into
`encryptedData`:

```bash
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace kube-system --fetch-cert > /tmp/sealed-secrets.pem

printf '%s' "$VALUE" | kubeseal --raw --cert /tmp/sealed-secrets.pem \
  --namespace production --name api-env
```

Use `printf`, not `echo` — a trailing newline gets encrypted into the value. The
blob is bound to the namespace + secret name, so staging needs its own run.
`envFrom` is read only at pod start, so `kubectl rollout restart deploy/api -n production`
after ArgoCD syncs.

## Inventory

| File | Namespace | Keys |
|---|---|---|
| `staging/api-env.yaml` | staging | DATABASE_USERNAME, DATABASE_PASSWORD, JWT_SECRET, OAUTH_APPLE_*, APNs, Resend, AI_PROVIDER, AI_API_KEY or provider key, AI_BASE_URL, AI_MODEL, AI_CHAT_MODEL, AI_TIPS_MODEL, … |
| `production/api-env.yaml` | production | same, production values, plus `FRED_API_KEY` for live US macro data, plus the insights chain `HERMES_BASE_URL` + `HERMES_API_TOKEN` (primary) and `DEEPAPI_API_KEY` + `DEEPAPI_API_BASE_URL` (fallback) |
| `{staging,production}/report-download-signing.yaml` | matching environment | REPORT_DOWNLOAD_SIGNING_SECRET (unique 32-byte random value; signs private report links) |
| `staging/mcp-introspection.yaml` | staging | MCP_INTROSPECTION_SECRET (must equal the API secret value) |
| `production/mcp-introspection.yaml` | production | MCP_INTROSPECTION_SECRET (must equal the API secret value) |
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
