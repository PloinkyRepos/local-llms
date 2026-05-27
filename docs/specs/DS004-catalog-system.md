---
id: DS004
title: Catalog System
status: accepted
owner: repository
summary: Backend definitions, agent catalog entries, JSON schemas, and model routing rules.
---

# DS004 Catalog System

## Introduction

The catalog is the declarative source of truth for which backends exist, which models each agent supports, and how model identifiers map to backend-specific runtime names. This specification defines the catalog structure, schema contracts, and routing semantics.

## Core Content

### Directory Layout

The catalog lives under `catalog/` in the repository root and is copied to `/opt/local-llms/catalog` inside the Docker image. It contains:

- `backends.json` — the backend registry, keyed by backend identifier.
- `agents/<agent-id>.json` — one file per agent, declaring supported models and resource metadata.
- `schemas/backends.schema.json` — JSON Schema for `backends.json`.
- `schemas/agent.schema.json` — JSON Schema for agent catalog entries.

### Backend Definitions

Each entry in `backends.json` must include `name`, `description`, `internalPort`, `apiShape`, `readinessProbe`, `storagePath`, `hostStorageKey`, and `runner`. The `apiShape` field classifies the backend's HTTP interface as `openai-chat`, `translation`, or `scoring`.

The `readinessProbe` object specifies a `type` (currently always `http`), a `path` (the URL path to probe), and an `expectedStatus` (the HTTP status code that indicates readiness). The startup script uses these values to poll the backend after launch.

The `storagePath` is the absolute path inside the container where the backend stores models. It must start with `/data/local-llms/`. The `hostStorageKey` is the relative path under the Ploinky data mount that corresponds to `storagePath`.

Backends with `experimental: true` are not installed in the base image and are not used as default backends by any agent. The three experimental backends are `vllm`, `sglang`, and `lmstudio_llmster`.

### Agent Catalog Entries

Each agent entry must include `agentId`, `description`, `models` (array), `defaultModel`, `backend`, `taskApi`, `ramBand`, `gpuRequired`, `cpuSafe`, `defaultEnabled`, `readinessTimeout`, and `startupPreset`. The `agentId` must match the agent directory name and follow the pattern `^[a-z][a-z0-9-]*$`.

The `taskApi` field classifies the agent's primary interface: `chat`, `function-calling`, `translation`, `scoring`, or `management`. This drives which MCP tools the agent exposes and how the dispatcher routes tool calls.

The `ramBand` is a human-readable range (e.g., `"2-8 GB"`) used by the startup script to check available memory. The startup script parses the lower bound from this string and compares it against `/proc/meminfo`.

### Model Entries

Each model in an agent's `models` array must include `name`, `backend`, and `taskApi`. Optional fields are `backendModel`, `huggingfaceId`, `ollamaMinVersion`, `quantization`, and `notes`.

The `backendModel` field is the key to model routing. When present, it maps the user-facing `name` to the backend-specific runnable identifier. For example, `google/translategemma-4b-it` has `backendModel: "translategemma:4b"` because Ollama uses a different tag format than HuggingFace. The dispatcher's `resolve_backend_model` function performs this lookup at tool-call time.

### Routing Rules

Seq2seq translation models (`facebook/m2m100_418M`, `google/madlad400-3b-mt`) must use the `transformers_seq2seq` backend with `taskApi: "translation"`. They must not be routed through Ollama or any chat-completions backend because they are encoder-decoder architectures that require the HuggingFace `pipeline("translation")` interface.

The Qwen3 Reranker (`Qwen/Qwen3-Reranker-0.6B`) must use the `reranker` backend with `taskApi: "scoring"`. It must not be routed through a generic sequence classifier (`AutoModelForSequenceClassification`) — the reranker service uses `sentence_transformers.CrossEncoder` specifically.

All other chat, function-calling, and coding models use the `ollama` backend by default.

### Schema Validation

The JSON Schema files under `catalog/schemas/` are the authoritative definition of required and optional fields. The test suite validates all catalog entries against these structural expectations. The schemas use JSON Schema draft 2020-12 with `additionalProperties: false` to catch unexpected fields.

## Decisions & Questions

### Question #1: Should the catalog support model aliases beyond `backendModel`?

Response: The current `backendModel` field is sufficient for the one-to-one mapping between user-facing IDs and backend IDs. If a model needs multiple backend-specific names (e.g., different quantizations), a future `variants` array could be added. Deferred until a concrete use case emerges.

### Question #2: Should `ollamaMinVersion` be enforced at startup?

Options:
- Add an Ollama version check to `start-agent.sh` that compares the installed version against `ollamaMinVersion` from the catalog.
- Keep it as metadata for documentation and operator guidance only.

## Conclusion

The catalog provides declarative backend definitions and per-agent model registries with schema validation, resource metadata, and backend-model alias resolution. Routing rules ensure that non-chat models (seq2seq, rerankers) are served by their correct specialized backends.
