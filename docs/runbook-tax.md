# Tax feature operations

Tax estimates, reports, and MCP `tax:read` tools run inside the API. Reports write to a **ReadWriteOnce** PVC (`TAX_REPORT_STORAGE_PATH`). Keep the API at **one replica** until object storage is introduced.

## Runtime controls

| Variable | Purpose |
|----------|---------|
| `TAX_VALIDATED_JURISDICTIONS` | Comma-separated ISO codes that may produce **actionable** opportunities. Production is **`US` only** until PT/ES/DE receive professional sign-off. |
| `TAX_REPORT_STORAGE_PATH` | Local path for PDF/CSV workpapers (PVC-mounted). |
| `TAX_REPORT_RETENTION_DAYS` | Optional cleanup horizon for completed report artifacts (when configured). |

Do **not** expand `TAX_VALIDATED_JURISDICTIONS` to `PT`, `ES`, or `DE` without written professional validation of the rule packs. `FR` and `IT` remain professional-review only until evidence-backed packs ship.

## Jurisdiction product status

| Code | Engine depth | Production posture |
|------|--------------|--------------------|
| US | Full (rates from profile) | Validated when listed in env |
| PT | CIRS Category G pack | Estimate-only until validated |
| DE | EStG / InvStG pack | Estimate-only until validated |
| ES | Loss deferral + user market admission | Estimate-only; admission is **user-attested** |
| FR | No production pack | Professional review only |
| IT | No production pack | Professional review only |

Spanish regulated vs unlisted windows depend on user-attested market admission. Automatic ISIN admission data is **not** deployed.

## MCP

Scoped tokens may request `tax:read` for:

- `get_tax_dashboard`
- `get_tax_loss_carryforwards`

Profile edits, scenarios, action plans, notifications, and report generation remain first-party only.

## Safe rollout

1. Deploy API image; confirm migrate job succeeds (tax optimization tables, loss ledgers, report retry fields, financing tables if not already applied).
2. Confirm tax-report PVC is **Bound** and writable at `TAX_REPORT_STORAGE_PATH`.
3. Keep API replicas = **1** while using RWO local storage.
4. Smoke-test first-party `/tax` for US (actionable path when profile complete) and PT/DE (estimate banners).
5. Smoke-test API token with only `tax:read` via MCP tools.
6. Confirm log streams for `tax.report generation failed`, projection poll failures, and cleanup job errors are scraped (see alerts below).

## Financing affordability (related)

Backend `FinancingPolicyRegistry` encodes consumer guidance (not underwriting):

- ES: 40% total-debt of net income (Banco de España educational guidance)
- IT: ~⅓ disposable income for mortgage payments (Bank of Italy educational)
- NL: no fixed % (AFM tables; cash-flow only)
- PL: 40–50% DStI caution band (KNF Recommendation S)
- BR: 30% gross housing guidance (BCB FAQ)
- DE / US: calculated ratio without a universal pass/fail threshold

## Incident controls

- Disable report generation by stopping Pro usage / feature flags if storage is full.
- Set `TAX_VALIDATED_JURISDICTIONS=` (empty) to force all jurisdictions to estimate-only / non-actionable overnight.
- Scale API only after moving tax reports to S3-compatible storage with lifecycle rules.

## Alerts to wire (log-based until Prometheus counters exist)

Alert on API logs matching:

1. `tax.report generation failed`
2. Tax report status stuck in `failed` / retry exhaustion messages from the generation poller
3. `tax.projection poll failed`
4. Tax report cleanup job errors

Promtail/Loki or Alloy log rules can match these strings until dedicated metrics are exported.
