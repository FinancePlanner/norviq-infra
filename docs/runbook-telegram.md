# Runbook — Telegram bot

The Norviq assistant, reachable from a Telegram chat. Same assistant, same
conversation thread, same monthly quota as the app.

There is no new service, no new hostname, and no DNS record: the webhook is a
route inside the existing `api` deployment, and the ingress is already a
host-based catch-all (`charts/app/templates/ingress.yaml`).

---

## Architecture in one paragraph

Telegram POSTs updates to `https://api.norviq.org/webhooks/telegram`. The route
sits outside every authenticator — Telegram cannot present a session — and is
guarded solely by a constant-time comparison of the
`X-Telegram-Bot-Api-Secret-Token` header against `TELEGRAM_WEBHOOK_SECRET`.
Nothing else stands in front of it: there is no WAF, no Cloudflare, and no
forwardAuth middleware on the api ingress. **That secret is the entire door.**

The handler acknowledges immediately and answers on a detached task, because a
turn can take minutes and Telegram retries anything it does not see acked.

## Tenancy — one bot, many users

`TELEGRAM_BOT_TOKEN` and `TELEGRAM_WEBHOOK_SECRET` are **deployment** secrets, not
per-user ones. There is exactly one of each, and neither carries user identity:

- The **bot token** identifies Norviq to Telegram.
- The **webhook secret** proves an inbound POST came from Telegram rather than
  from anyone else who can reach a public URL. Telegram permits one webhook and
  one secret per bot token, so a per-user value is not expressible.

User isolation is enforced by the link table instead, and it is strict:

| Guarantee | Where |
|---|---|
| One Telegram chat maps to exactly one account | `UNIQUE (platform, external_id)` on `messaging_links` |
| Every turn runs as the linked account | `assistantTurn(inbound, userId: link.userId, …)` |
| The model cannot name a different user | `AIToolContext(userId:)` binds identity server-side |
| A linked chat cannot be re-pointed at another account | `RedeemFailure.alreadyLinkedToAnotherAccount` |
| Group and channel chats are refused | a shared chat cannot map to one person's finances |

Covered by `MessagingLinkingTests` — "A chat linked to one account cannot be
claimed by another" and "Two chats on one bot resolve to their own accounts".

The trade-off this design accepts: Norviq operates the bot, so the token is a
central secret whose compromise would expose inbound messages for every linked
user — the same trust shape as the APNs key. A per-user bring-your-own bot
(mirroring `UserAIProviderCredential`) would remove that, at the cost of making
every user create a bot through @BotFather before they can start. Not built.

## Mode selection

Derived from configuration, never set directly:

| `TELEGRAM_WEBHOOK_SECRET` | Mode | Where |
|---|---|---|
| set | webhook | production |
| empty | long-polling (`getUpdates`) | local development |

Production **refuses to boot** in polling mode (`TelegramConfiguration.validate`).
A rolling deploy briefly runs two pods, and two pollers sharing one bot token
fight over the same update queue — the bot would answer roughly every other
message. Long-polling exists so a laptop can drive a real bot with no public
URL.

## Configuration

Sealed into `secrets/production/api-env.yaml` (see `secrets/README.md`):

| Key | Notes |
|---|---|
| `TELEGRAM_BOT_TOKEN` | From @BotFather. **Absent ⇒ the feature is off**: no route mounted, no poller, and the settings panel hides itself. |
| `TELEGRAM_WEBHOOK_SECRET` | `openssl rand -hex 32` |

Plain value in `apps/api/values-production.yaml`:

| Key | Notes |
|---|---|
| `TELEGRAM_BOT_USERNAME` | Handle without the `@`. Used to build `t.me` deep links. |

Sealing one key without re-sealing the file:

```bash
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace kube-system --fetch-cert > /tmp/sealed-secrets.pem

printf '%s' "$TELEGRAM_BOT_TOKEN" | kubeseal --raw --cert /tmp/sealed-secrets.pem \
  --namespace production --name api-env
```

`printf`, not `echo` — a trailing newline gets encrypted into the value, and a
bot token with `\n` on the end fails in a way that looks like a bad token.

`envFrom` is read only at pod start:

```bash
kubectl rollout restart deploy/api -n production
```

## Cutover

Use a **separate production bot from your development one.** A token can hold
exactly one webhook, so pointing the dev bot at production silently kills the
local loop.

```bash
curl -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d url="https://api.norviq.org/webhooks/telegram" \
  -d secret_token="$TELEGRAM_WEBHOOK_SECRET" \
  -d allowed_updates='["message","callback_query"]'

curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo"
```

Healthy `getWebhookInfo`: the right `url`, `pending_update_count: 0`, and no
`last_error_message`.

Then, end to end: open Norviq → Settings → Integrations → Telegram → Connect,
send the 8-character code to the bot, and ask it something.

## Database

`messaging_links` and `messaging_preferences`, created by
`CreateMessagingLinks` / `CreateMessagingPreferences`. They ride the existing
ArgoCD PreSync migrate hook (`charts/app/templates/migrate-job.yaml`), which
takes a `pg_dump` first. No manual step.

## Rolling back

Disable the bot without a deploy:

```bash
curl -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/deleteWebhook"
```

Telegram stops delivering immediately; links and preferences are untouched, so
re-running `setWebhook` resumes exactly where it left off. To remove the feature
entirely, drop `TELEGRAM_BOT_TOKEN` from `api-env` and restart — the route stops
being mounted.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `getWebhookInfo` shows 401s | `TELEGRAM_WEBHOOK_SECRET` in the cluster differs from the one passed to `setWebhook`. Re-run `setWebhook`. |
| Bot silent, `pending_update_count` climbing | api pods not running, or the token was sealed with a trailing newline. |
| Bot answers every other message | Two pollers. Should be impossible in production — check that `TELEGRAM_WEBHOOK_SECRET` is actually set in the running pod. |
| "This chat is not connected" after redeeming | Codes are single-use and expire in 15 minutes. Mint a fresh one. |
| Answers arrive but alerts never do | Alerts are opt-in per kind and default to **off**. Turn them on in Settings → Integrations → Telegram. |
| 404 on `/webhooks/telegram` | No `TELEGRAM_BOT_TOKEN` in the pod: the route is only mounted when one is configured. |
