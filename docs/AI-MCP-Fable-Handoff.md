# AI and MCP handoff for Fable

Last updated: 2026-07-14

## Purpose

This document is the durable checkpoint for reviewing and continuing Norviq's
AI assistant and Model Context Protocol work. It records what is shipped,
important architecture decisions, manual production work, known limitations,
and the recommended implementation order.

## Current status

The core feature is implemented across backend, web, iOS, MCP, shared
contracts, and infrastructure. All listed code is on each repository's main
branch.

Production is not considered verified until the operator completes secrets,
DNS, deployment, and live authenticated smoke checks. Tests and builds for the
latest streaming and provider changes were intentionally skipped.

## Shipped architecture

### Backend assistant

- Persisted conversations and encrypted messages with retention.
- Monthly free-preview usage and Pro entitlement handling.
- Proactive daily financial tips based on server-side financial context.
- Tips, preferences, usage, and pending-action APIs.
- Confirmation-required mutations with transactional execution and audit data.
- Financial context tools for expenses, budgets, reports, portfolios, goals,
  market data, and other supported user data.
- First-party assistant routes reject scoped MCP credentials.
- Additive Server-Sent Events endpoint for persisted turns.
- Existing JSON turn endpoint remains backward compatible.

### Streaming

The backend now emits live SSE lifecycle events:

    started
    turn
    error
    done

Web uses an authenticated server-side SSE proxy so browser bearer tokens are
never exposed. iOS uses URLSession bytes to consume the persisted stream.

This is lifecycle streaming, not token-by-token generation. The final
assistant text currently arrives in the persisted turn event.

### Provider support

AIProviderConfiguration supports:

- openai: direct OpenAI Chat Completions and Responses APIs.
- openrouter: recommended multi-model production route.
- custom: a gateway implementing compatible Chat Completions and Responses
  endpoints.

OpenRouter mode can select Claude, Gemini, DeepSeek, Qwen, OpenAI, or other
models independently for normal AI, assistant turns, and proactive tips.

Relevant environment variables:

    AI_PROVIDER
    AI_API_KEY
    AI_BASE_URL
    AI_MODEL
    AI_CHAT_MODEL
    AI_TIPS_MODEL
    AI_MAX_TOKENS
    OPENAI_API_KEY
    OPENAI_BASE_URL
    OPENAI_MODEL
    OPENROUTER_API_KEY

Legacy OPENAI_BASE_URL and OPENAI_MODEL values are ignored when the selected
provider is not openai. This prevents accidentally sending an OpenRouter key to
OpenAI.

Direct Claude, Gemini, DeepSeek, and Qwen compatibility endpoints are not the
default full-feature path because their Responses and tool-calling parity
differs. OpenRouter normalizes the required contracts. Native adapters can be
added later if cost, data residency, or provider fidelity justifies them.

### MCP service

- Go MCP server using Streamable HTTP.
- Bearer token introspection against the backend.
- PAT and supported OAuth token scope enforcement.
- Pro entitlement is rechecked during introspection.
- Read tools bind the authenticated user on the server.
- Write tools require form elicitation support and explicit confirmation.
- Write tools are hidden from clients that do not advertise elicitation.
- Expense, CSV import, goal, budget, and recurring-item mutations are covered.
- Health endpoints: /healthz and /readyz.
- Prometheus endpoint: /metrics.
- Protected-resource metadata is published for MCP clients.

### Deployment

VPS Compose:

- MCP is an independently restartable service in production Compose.
- Traefik routes mcp.norviq.org to port 8087.
- Backend deployment bootstraps MCP only when the shared secret exists.
- MCP repository deployment is opt-in with COMPOSE_DEPLOY_ENABLED=true.
- MCP images use immutable Git SHA tags.

Kubernetes:

- Staging and production ArgoCD MCP applications exist.
- Shared app chart supplies probes, secret injection, ingress, and resources.
- Pod annotations enable Prometheus scraping.
- MCP is stateless and does not run migrations.
- Sealed-secret examples document AI and MCP keys.

Only one production target should own mcp.norviq.org. Do not point the hostname
at both Compose and Kubernetes.

## Commit checkpoints

- norviq-shared: v3.27.0 contracts published.
- norviq-backend 533531f: Compose MCP and AI production configuration.
- norviq-backend f0d9b23: persisted assistant SSE.
- norviq-backend 56967c5: multi-provider AI routing.
- norviq-web f179328: authenticated web assistant streaming.
- norviq-ios 645233b: persisted native assistant streaming.
- norviq-mcp 350d030: deployment workflow and Prometheus metrics.
- norviq-infra 4eca3c1: MCP deployment observability.
- norviq-infra 51426b9: AI and MCP production runbook.

Earlier tool, scope, persistence, UI, and contract commits are ancestors of
these checkpoints.

## Required operator work

The detailed commands are in AI-MCP-Production-Setup.md.

Recommended Compose sequence:

1. Create and fund an OpenRouter API key.
2. Generate MCP_INTROSPECTION_SECRET with openssl rand -hex 32.
3. Put AI and MCP variables in /opt/stockplan/.env.production.
4. Create the mcp.norviq.org DNS record pointing to the VPS.
5. Add SERVER_HOST, SERVER_USER, and SERVER_SSH_KEY to the norviq-mcp
   production GitHub environment.
6. Add INFRA_DEPLOY_TOKEN to norviq-mcp.
7. Set COMPOSE_DEPLOY_ENABLED=true in norviq-mcp repository variables.
8. Run the backend Deploy workflow.
9. Run the MCP Deploy workflow.
10. Check /healthz, /readyz, and protected-resource metadata over HTTPS.
11. Create a Norviq PAT and connect a real MCP client to /mcp.
12. Send authenticated assistant prompts from web and iOS.

Recommended initial model split:

    AI_PROVIDER=openrouter
    AI_MODEL=anthropic/claude-sonnet-4.6
    AI_CHAT_MODEL=anthropic/claude-sonnet-4.6
    AI_TIPS_MODEL=google/gemini-3.5-flash
    AI_MAX_TOKENS=700

Review current model slugs before production. Prefer pinned versions after
evaluation instead of floating aliases.

## Release acceptance checklist

1. Backend deployment completes with migrations.
2. MCP deployment pulls the expected immutable image.
3. DNS and TLS resolve for mcp.norviq.org.
4. MCP readiness returns HTTP 200.
5. Protected-resource metadata contains the canonical API authorization server.
6. Revoked PATs fail introspection.
7. Free users fail the MCP Pro entitlement check.
8. Read tools cannot access another user's data.
9. Write tools are absent without elicitation support.
10. Confirmed writes persist exactly once.
11. Web assistant receives started and final turn events.
12. iOS assistant receives started and final turn events.
13. Pending assistant actions require confirmation and create audit records.
14. Daily tips run with the selected tips model.
15. Prometheus scrapes MCP metrics.
16. Model-provider cost and error rate are visible in production logs.

## Known limitations and risks

- Latest backend, web, iOS, MCP, and Helm changes are not fully regression
  tested as a single release.
- iOS compilation remains a required release check.
- Assistant streaming does not forward individual model tokens.
- OpenRouter Responses is a beta contract and needs defensive monitoring.
- Model aliases and availability can change.
- Provider compatibility does not guarantee equal tool-call quality.
- Financial context is sent to the configured external model provider.
- Data processing agreements, retention, region, and training settings require
  business review.
- Prompt-injection and untrusted financial descriptions remain ongoing risks.
- Model-generated mutations must never bypass pending-action or MCP elicitation
  confirmation.
- Cost controls currently rely on application quotas and provider account
  limits; formal per-model budgets should be added.

## What to do next

### P0: production enablement

1. Complete the operator work above.
2. Run backend, web, iOS, MCP, and Helm validation.
3. Perform authenticated end-to-end checks with a test and Pro account.
4. Confirm dashboards and alerts before general availability.

### P1: reliability and quality

1. Add integration tests for provider selection and configuration precedence.
2. Add contract tests for OpenRouter Chat Completions and Responses fixtures.
3. Add MCP PAT revocation, OAuth, scope, elicitation, and idempotency E2E tests.
4. Add web streaming disconnect and retry coverage.
5. Add iOS SSE cancellation, backgrounding, and malformed-event coverage.
6. Add alerts for AI provider failures, rate limits, latency, cost, and empty
   responses.
7. Add a provider circuit breaker and explicit fallback policy.

### P2: token streaming

1. Request upstream Responses streaming.
2. Parse provider SSE deltas without exposing reasoning tokens.
3. Forward safe text deltas to web and iOS.
4. Accumulate the final response server-side.
5. Persist only the completed final message.
6. Handle cancellation without storing partial assistant output as complete.
7. Keep pending-action creation transactional and emit it only after commit.

### P3: AI evaluation

1. Build a de-identified finance prompt evaluation set.
2. Score factual grounding, numerical accuracy, tool selection, refusal
   behavior, and unsupported investment advice.
3. Compare Claude, Gemini, DeepSeek, Qwen, and OpenAI models.
4. Pin approved model versions per workload.
5. Add regression gates before changing production models or prompts.
6. Collect explicit user feedback on tips and assistant answers.

### P4: direct provider adapters, only if justified

1. Add native Anthropic Messages support for maximum Claude fidelity.
2. Add native Gemini support for Google-specific capabilities.
3. Add direct DeepSeek and Qwen adapters for cost or regional requirements.
4. Preserve a common internal tool and confirmation contract.
5. Do not expose provider-specific response shapes to web or iOS.

## Review references

- AI and MCP operator runbook: docs/AI-MCP-Production-Setup.md
- Anthropic OpenAI compatibility:
  https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk
- Gemini OpenAI compatibility:
  https://ai.google.dev/gemini-api/docs/openai
- DeepSeek API:
  https://api-docs.deepseek.com/
- Qwen Model Studio:
  https://help.aliyun.com/en/model-studio/what-is-model-studio
- OpenRouter Responses:
  https://openrouter.ai/docs/api/reference/responses/overview

## Instructions for Fable

Before changing code:

1. Read this handoff and AI-MCP-Production-Setup.md.
2. Check the listed commits are present on main.
3. Confirm whether production uses Compose or Kubernetes.
4. Confirm secrets and DNS exist without printing secret values.
5. Inspect the current provider model slugs and official compatibility docs.
6. Treat pending-action and elicitation confirmation as security invariants.
7. Do not claim release readiness until the acceptance checklist is completed.
