# Portfolio rebalancing operations

The rebalancing engine is rule-based and runs inside the API. It does not call AI services, mutate holdings, or submit broker orders.

## Runtime controls

- `REBALANCING_ENABLED` exposes the authenticated API surface. Keep it `true` after the database migration succeeds.
- `REBALANCING_ALERTS_ENABLED` starts the drift evaluator lifecycle job.
- `REBALANCING_ALERT_POLL_SECONDS` controls evaluator cadence and is clamped to at least 60 seconds.

The migration creates normalized allocation policy, leaf target, plan, preference, and alert tables and extends APNs device registrations with capability negotiation. Deploy the API migration job before new iOS or web clients.

## Safe rollout

1. Sync staging and confirm the migration job completes.
2. Create a 60/40 target model against a test portfolio and verify the overview valuation timestamp and price-quality state.
3. Simulate a plan and confirm no position or transaction rows change.
4. Export CSV and PDF, then mark the planning record completed and verify discipline metrics.
5. Enable push alerts on a device advertising `rebalance_drift_v1`; confirm only one notification is sent for a newly breached scope.
6. Confirm the alert remains active while drift is between 80% and 100% of its threshold and resolves below 80%.
7. Promote the same image and values to production.

## Incident controls

Set `REBALANCING_ALERTS_ENABLED=false` to stop scheduled calculations and push delivery while leaving targets, simulations, exports, and in-app history available. Set `REBALANCING_ENABLED=false` only when the entire feature surface must be withdrawn; clients treat the resulting 404 as unavailable.

Drift calculations with incomplete prices do not create alerts or plans. Missing FX and stale quotes surface as valuation warnings instead of silently producing actionable output.
