# AI and MCP production setup

Norviq supports two complete AI runtime modes:

- openai: direct OpenAI Chat Completions and Responses APIs.
- openrouter: normalized access to Claude, Gemini, DeepSeek, Qwen, OpenAI,
  and other models through the same Chat Completions and Responses contracts.

custom is available for gateways that implement both compatible endpoints.
Direct Claude, Gemini, DeepSeek, and Qwen compatibility endpoints are not the
default production path because their OpenAI compatibility coverage differs,
especially for Responses tool calling.

## 1. Choose models

Use reviewed, pinned model slugs where possible. Models can be split by
workload:

    AI_PROVIDER=openrouter
    OPENROUTER_API_KEY=replace-me
    AI_MODEL=anthropic/claude-sonnet-4.6
    AI_CHAT_MODEL=anthropic/claude-sonnet-4.6
    AI_TIPS_MODEL=google/gemini-3.5-flash
    AI_MAX_TOKENS=700

To use DeepSeek or Qwen, replace the workload model with a current OpenRouter
slug from its model catalog. Do not put provider keys in web or iOS
configuration.

## 2. Generate the MCP shared secret

Generate one value and use it in both the API and MCP service:

    openssl rand -hex 32

Store it as MCP_INTROSPECTION_SECRET. It authenticates private token
introspection; it is not a user access token.

## 3. VPS Compose deployment

On the server, edit /opt/stockplan/.env.production and set:

    AI_PROVIDER=openrouter
    OPENROUTER_API_KEY=replace-me
    AI_MODEL=anthropic/claude-sonnet-4.6
    AI_CHAT_MODEL=anthropic/claude-sonnet-4.6
    AI_TIPS_MODEL=google/gemini-3.5-flash
    MCP_INTROSPECTION_SECRET=replace-with-generated-value
    MCP_DOMAIN=mcp.norviq.org

In the norviq-mcp GitHub repository:

1. Add production environment secrets SERVER_HOST, SERVER_USER, and
   SERVER_SSH_KEY.
2. Add INFRA_DEPLOY_TOKEN with contents-write access to norviq-infra.
3. Set the repository variable COMPOSE_DEPLOY_ENABLED=true.
4. Run the backend Deploy workflow once, then run the MCP Deploy workflow.

## 4. Kubernetes deployment

Do not use this section for the same hostname if Compose is serving MCP.

1. Add the AI variables and MCP_INTROSPECTION_SECRET to the source environment
   files used to seal api-env in staging and production.
2. Re-seal api-env in both namespaces.
3. Create mcp-introspection sealed secrets in both namespaces with the exact
   same MCP_INTROSPECTION_SECRET.
4. Commit the sealed secrets.
5. Let MCP CI update the staging image tag.
6. Promote the tested staging MCP tag through the infra promotion workflow.

## 5. DNS and health

Point only the active deployment target:

- Compose: mcp.norviq.org A/AAAA records to the VPS.
- Kubernetes: mcp.norviq.org and dev-mcp.norviq.org to the cluster ingress.

After TLS is issued, check:

    curl -fsS https://mcp.norviq.org/healthz
    curl -fsS https://mcp.norviq.org/readyz
    curl -fsS https://mcp.norviq.org/.well-known/oauth-protected-resource

Then create a PAT from the Norviq API Access settings and connect an MCP client
to https://mcp.norviq.org/mcp.

## 6. Data governance

Financial context is sent to the selected model provider. Before production:

1. Confirm the provider region and retention settings.
2. Complete DPA and subprocessor review.
3. Disable provider training or logging where the account supports it.
4. Keep API keys server-side and rotate them through sealed secrets or the VPS
   environment file.
