# QWiser University - App Configuration Reference

> **Last Updated**: 2026-01-14
> **Version**: 1.0.0
> **Audience**: University IT Infrastructure Teams

---

## Overview

Azure App Configuration serves as the single source of truth for all runtime configuration. All values use colon-separated keys that are converted to nested dictionaries at runtime.

### Key Format

```
category:subcategory:setting = value
```

Example: `params:chat:message:model = gpt-5.2`

### Labels

All keys use labels to separate environments:
- `production` - Production environment
- `staging` - Staging/test environment

---

## Configuration Categories

| Category        | Purpose                   | Hot-Reloadable        |
| --------------- | ------------------------- | --------------------- |
| `db:*`          | Database connection       | No (requires restart) |
| `redis:*`       | Redis connection          | No (requires restart) |
| `azure:*`       | Azure service connections | No (requires restart) |
| `qdrant:*`      | Qdrant vector database    | No (requires restart) |
| `ai:*`          | AI model endpoints        | Yes                   |
| `params:*`      | Application parameters    | Yes                   |
| `embedding:*`   | Embedding settings        | Yes                   |
| `text:*`        | Text processing           | Yes                   |
| `chat:*`        | Chat configuration        | Yes                   |
| `lti:*`         | LTI integration           | Yes                   |
| `maintenance:*` | Maintenance mode          | Yes                   |

**Hot-Reload**: Update `sentinel` key to trigger refresh in running services.

---

## Infrastructure Configuration

### Database (`db:*`)

| Key           | Type    | Required | Example                                      | Description         |
| ------------- | ------- | -------- | -------------------------------------------- | ------------------- |
| `db:host`     | string  | Yes      | `qwiser-prod-mysql.mysql.database.azure.com` | MySQL server FQDN   |
| `db:port`     | integer | Yes      | `3306`                                       | MySQL port          |
| `db:name`     | string  | Yes      | `qwiser`                                     | Database name       |
| `db:user`     | KV ref  | Yes      | `{"uri":"...DB-USER"}`                       | Key Vault reference |
| `db:password` | KV ref  | Yes      | `{"uri":"...DB-PASSWORD"}`                   | Key Vault reference |

### Redis (`redis:*`)

| Key                            | Type    | Required | Default | Description                 |
| ------------------------------ | ------- | -------- | ------- | --------------------------- |
| `redis:host`                   | string  | Yes      | -       | Redis hostname              |
| `redis:port`                   | integer | Yes      | `10000` | Redis port (AMR uses 10000) |
| `redis:max-connections`        | integer | No       | `100`   | Connection pool size        |
| `redis:socket_timeout`         | float   | No       | `300.0` | Socket timeout in seconds   |
| `redis:socket_connect_timeout` | float   | No       | `20.0`  | Connect timeout in seconds  |
| `redis:health_check_interval`  | integer | No       | `20`    | Health check interval       |

**Note**: Azure Managed Redis uses Entra ID authentication via Workload Identity. No password required.

### Azure Storage (`azure:storage:*`)

| Key                               | Type   | Required | Description                  |
| --------------------------------- | ------ | -------- | ---------------------------- |
| `azure:storage:queue_url`         | string | Yes      | Storage queue URL for Celery |
| `azure:storage:key`               | KV ref | Yes      | Storage account key          |
| `azure:storage:connection_string` | KV ref | Yes      | Full connection string       |

### Qdrant (`qdrant:*`)

| Key                  | Type   | Required | Default                                       | Description              |
| -------------------- | ------ | -------- | --------------------------------------------- | ------------------------ |
| `qdrant:cluster_url` | string | Yes      | `http://qdrant.qdrant.svc.cluster.local:6333` | Internal K8s service URL |
| `qdrant:api_key`     | KV ref | Yes      | -                                             | Qdrant API key           |

### Application Insights (`azure:*`)

| Key                                           | Type   | Required | Description                    |
| --------------------------------------------- | ------ | -------- | ------------------------------ |
| `azure:applicationinsights_connection_string` | KV ref | Yes      | App Insights connection string |

---

## AI Model Configuration

### Structure

Each AI model has these keys:

```
ai:{model-name}:endpoint
ai:{model-name}:api_key
ai:{model-name}:rpm
ai:{model-name}:tpm
ai:{model-name}:context_window (optional)
ai:{model-name}:max_output_tokens (optional)
```

### GPT-4.1 Mini

| Key                                 | Type    | Example                                                                                                              |
| ----------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `ai:gpt-4.1-mini:endpoint`          | string  | `https://qwiser-ai.openai.azure.com/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2025-01-01-preview` |
| `ai:gpt-4.1-mini:api_key`           | KV ref  | `{"uri":"https://kv.vault.azure.net/secrets/AI-FOUNDRY-API-KEY"}`                                                    |
| `ai:gpt-4.1-mini:rpm`               | integer | `1000`                                                                                                               |
| `ai:gpt-4.1-mini:tpm`               | integer | `100000`                                                                                                             |
| `ai:gpt-4.1-mini:context_window`    | integer | `1047576`                                                                                                            |
| `ai:gpt-4.1-mini:max_output_tokens` | integer | `32768`                                                                                                              |

### GPT-5.2

| Key                            | Type    | Example                                                                                                         |
| ------------------------------ | ------- | --------------------------------------------------------------------------------------------------------------- |
| `ai:gpt-5.2:endpoint`          | string  | `https://qwiser-ai.openai.azure.com/openai/deployments/gpt-5.2/chat/completions?api-version=2025-01-01-preview` |
| `ai:gpt-5.2:api_key`           | KV ref  | `{"uri":"https://kv.vault.azure.net/secrets/AI-FOUNDRY-API-KEY"}`                                               |
| `ai:gpt-5.2:rpm`               | integer | `2000`                                                                                                          |
| `ai:gpt-5.2:tpm`               | integer | `200000`                                                                                                        |
| `ai:gpt-5.2:context_window`    | integer | `400000`                                                                                                        |
| `ai:gpt-5.2:max_output_tokens` | integer | `128000`                                                                                                        |

### Text Embedding 3 Large

| Key                                  | Type    | Example                                                                                                          |
| ------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------- |
| `ai:text-embedding-3-large:endpoint` | string  | `https://qwiser-ai.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15` |
| `ai:text-embedding-3-large:api_key`  | KV ref  | `{"uri":"https://kv.vault.azure.net/secrets/AI-FOUNDRY-API-KEY"}`                                                |
| `ai:text-embedding-3-large:rpm`      | integer | `1000`                                                                                                           |
| `ai:text-embedding-3-large:tpm`      | integer | `500000`                                                                                                         |

### OCR (Mistral Document AI)

| Key               | Type    | Example                                                                                                                |
| ----------------- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `ai:ocr:endpoint` | string  | `https://qwiser-ai.openai.azure.com/openai/deployments/mistral-document-ai/completions?api-version=2025-01-01-preview` |
| `ai:ocr:api_key`  | KV ref  | `{"uri":"https://kv.vault.azure.net/secrets/AI-FOUNDRY-API-KEY"}`                                                      |
| `ai:ocr:model`    | string  | `mistral-document-ai-2505`                                                                                             |
| `ai:ocr:rpm`      | integer | `500`                                                                                                                  |

---

## Application Parameters

### Tree Generation (`params:tree:*`)

| Key                                  | Default   | Description                                      |
| ------------------------------------ | --------- | ------------------------------------------------ |
| `params:tree:token_threshold`        | `8000`    | Token threshold for short vs long tree algorithm |
| `params:tree:short:model`            | `gpt-5.2` | Model for short tree generation                  |
| `params:tree:short:temperature`      | `0.5`     | Temperature for short tree                       |
| `params:tree:short:max_tokens`       | `8000`    | Max output tokens                                |
| `params:tree:short:reasoning_effort` | `low`     | Reasoning effort level                           |
| `params:tree:long:model`             | `gpt-5.2` | Model for long tree generation                   |
| `params:tree:long:temperature`       | `0.5`     | Temperature for long tree                        |
| `params:tree:long:max_tokens`        | `10000`   | Max output tokens                                |
| `params:tree:long:diversity`         | `0.5`     | Topic diversity setting                          |
| `params:tree:long:nr_topics`         | `8`       | Number of topics to extract                      |

### Chat (`params:chat:*`)

| Key                                     | Default        | Description                    |
| --------------------------------------- | -------------- | ------------------------------ |
| `params:chat:message:model`             | `gpt-5.2`      | Model for chat messages        |
| `params:chat:message:temperature`       | `1`            | Temperature                    |
| `params:chat:message:context_limit`     | `3000`         | Context token limit            |
| `params:chat:message:response_limit`    | `5000`         | Response token limit           |
| `params:chat:summary:model`             | `gpt-5.2`      | Model for chat summaries       |
| `params:chat:name:model`                | `gpt-4.1-mini` | Model for chat name generation |
| `params:chat:standalone_question:model` | `gpt-4.1-mini` | Model for standalone questions |

### Questions (`params:questions:*`)

| Key                                 | Default   | Description                   |
| ----------------------------------- | --------- | ----------------------------- |
| `params:questions:model`            | `gpt-5.2` | Model for question generation |
| `params:questions:temperature`      | `0.5`     | Temperature                   |
| `params:questions:max_tokens`       | `3000`    | Max output tokens             |
| `params:questions:reasoning_effort` | `low`     | Reasoning effort              |

### Answers (`params:answers:*`)

| Key                          | Default   | Description              |
| ---------------------------- | --------- | ------------------------ |
| `params:answers:model`       | `gpt-5.2` | Model for answer grading |
| `params:answers:temperature` | `0.5`     | Temperature              |
| `params:answers:max_tokens`  | `3000`    | Max output tokens        |

### Study Notes (`params:study_notes:*`)

| Key                              | Default        | Description           |
| -------------------------------- | -------------- | --------------------- |
| `params:study_notes:model`       | `gpt-4.1-mini` | Model for study notes |
| `params:study_notes:temperature` | `0.5`          | Temperature           |
| `params:study_notes:max_tokens`  | `10000`        | Max output tokens     |

---

## Embedding Configuration

| Key                            | Default | Description                     |
| ------------------------------ | ------- | ------------------------------- |
| `embedding:window_size`        | `5`     | Sliding window size for context |
| `embedding:overlap`            | `2`     | Window overlap                  |
| `embedding:colbert_batch_size` | `8`     | ColBERT batch size              |
| `embedding:qdrant_batch_size`  | `20`    | Qdrant upsert batch size        |

---

## Text Processing

| Key                              | Default | Description                      |
| -------------------------------- | ------- | -------------------------------- |
| `text:min_paragraph_chars`       | `200`   | Minimum characters per paragraph |
| `text:min_chunk_words`           | `10`    | Minimum words per chunk          |
| `text:robust_loader_headless`    | `true`  | Run web loader headless          |
| `text:robust_loader_timeout`     | `30`    | Web loader timeout               |
| `text:robust_loader_max_retries` | `3`     | Max retry attempts               |

---

## LTI Configuration

| Key                            | Default            | Description                 |
| ------------------------------ | ------------------ | --------------------------- |
| `lti:key_id`                   | `qwiser-lti-key-1` | LTI key identifier          |
| `lti:private_key`              | KV ref             | RSA private key for signing |
| `lti:platform:issuer`          | `PLACEHOLDER`      | LMS issuer URL              |
| `lti:platform:client_id`       | `PLACEHOLDER`      | LTI client ID               |
| `lti:platform:deployment_id`   | `PLACEHOLDER`      | LTI deployment ID           |
| `lti:platform:oidc_auth_url`   | `PLACEHOLDER`      | OIDC authentication URL     |
| `lti:platform:oauth_token_url` | `PLACEHOLDER`      | OAuth token URL             |
| `lti:platform:jwks_url`        | `PLACEHOLDER`      | JWKS URL                    |

---

## Maintenance Mode

| Key                            | Default               | Description                           |
| ------------------------------ | --------------------- | ------------------------------------- |
| `maintenance:scheduled`        | `false`               | Enable maintenance mode               |
| `maintenance:message`          | `We'll be back soon!` | User-facing message                   |
| `maintenance:bypass_whitelist` | ``                    | Comma-separated IPs to bypass         |
| `maintenance:scheduled_time`   | -                     | Scheduled maintenance time (ISO 8601) |

---

## System Keys

| Key                   | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| `environment`         | Environment name (production/staging/local)                          |
| `logging:level`       | Log level (TRACE/DEBUG/INFO/WARNING/ERROR/CRITICAL). Hot-reloadable. |
| `worker:polling_time` | Worker queue polling interval                                        |
| `sentinel`            | Config refresh trigger (update to trigger reload)                    |
*Note: logging:level can be overriden at startup by environment variable LOGGING_LEVEL. Override lasts until config changes, then hot-reload takes precedence.*

---

## Hot-Reload Procedure

To update configuration without restarting services:

1. Update the desired keys:
```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "params:questions:temperature" \
    --value "0.7" \
    --label production \
    --yes
```

2. Update the sentinel key:
```bash
az appconfig kv set \
    -n "$APPCONFIG_NAME" \
    --key "sentinel" \
    --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label production \
    --yes
```

3. Wait for refresh interval (~45 seconds)

4. Verify in logs:
```bash
kubectl logs deployment/public-api | grep "Configuration refreshed"
```

---

## Validation Rules

The application validates configuration at startup:

| Rule                                            | Action if Failed                          |
| ----------------------------------------------- | ----------------------------------------- |
| Missing `db:host`                               | Crash with error                          |
| Missing `redis:host`                            | Crash with error                          |
| Missing AI model referenced by `params:*:model` | Crash with error listing available models |
| Invalid `environment` value                     | Crash with error                          |
| Missing Key Vault reference resolution          | Crash with error                          |

---

## Export/Import

### Export Configuration

```bash
az appconfig kv export \
    -n "$APPCONFIG_NAME" \
    --label production \
    --destination file \
    --path ./appconfig-backup.json \
    --format json
```

### Import Configuration

```bash
az appconfig kv import \
    -n "$APPCONFIG_NAME" \
    --label production \
    --source file \
    --path ./appconfig-backup.json \
    --format json \
    --yes
```

---

## Related Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment guide
- [AI_MODELS_SETUP.md](./AI_MODELS_SETUP.md) - AI model configuration
- [SECRET_ROTATION.md](./SECRET_ROTATION.md) - Secret rotation procedures
