---
id: DS003
title: Agent Manifests
status: accepted
owner: repository
summary: Ploinky manifest contract, port ordering, environment variables, readiness, and volume declarations.
---

# DS003 Agent Manifests

## Introduction

Each of the twelve agents has a `manifest.json` that Ploinky reads to configure the container, startup command, ports, environment, volumes, and health checks. This specification defines the invariants that every manifest must satisfy.

## Core Content

### Common Fields

Every manifest must set `container` to `assistos/local-llms:latest`, `start` to `/opt/local-llms/scripts/start-agent.sh`, and `cli` to `/bin/bash`. The `about` field must be a human-readable one-line description of the agent's role.

### Volume Mount

Every manifest must declare a volume mapping `.ploinky/data/local-llms` on the host to `/data/local-llms` inside the container. This is the shared model and runtime data root. The host path must start with `.ploinky/` because Ploinky validates that volume host paths are under the workspace data directory.

### Port Ordering

Every manifest profile must declare ports as an array. The first port entry must map to internal port 7000 (AgentServer). Model-serving agents declare a second port for their backend service (e.g., 11434 for Ollama, 8090 for transformers seq2seq, 8091 for reranker). The manager agent, which has no backend, declares only the AgentServer port.

Port ordering is significant because Ploinky uses the first declared port as the primary service port. AgentServer on 7000 must always be first so that Ploinky's MCP proxy routes correctly.

### Environment Variables

Every manifest profile must include these environment entries with their defaults:

- `LOCAL_LLMS_AGENT_ID`: must default to the agent directory name (e.g., `function-invocation`). This is the agent's identity for catalog lookups, registry writes, and logging.
- `LOCAL_LLMS_DATA_DIR`: must default to `/data/local-llms`.
- `LOCAL_LLMS_CATALOG_DIR`: must default to `/opt/local-llms/catalog`.

Model-serving agents must additionally declare:

- `LOCAL_LLMS_DEFAULT_MODEL`: the default model to load at startup.
- `LOCAL_LLMS_BACKEND`: the backend identifier (e.g., `ollama`, `transformers_seq2seq`, `reranker`).
- `LOCAL_LLMS_BACKEND_PORT`: the backend service port number.

Ollama-backed agents must also include `OLLAMA_HOST`, `OLLAMA_MODELS`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`, and `OLLAMA_KEEP_ALIVE` to ensure Ollama runs with predictable defaults inside the container.

### Readiness and Health

Model-serving agents must declare a `health.readiness` block with `script: "healthcheck.sh"`. The script name must be a bare filename (not a path) because Ploinky validates readiness script names against the agent directory. Each agent directory contains a local `healthcheck.sh` that delegates to `/opt/local-llms/scripts/healthcheck.sh`.

The `interval`, `timeout`, and `failureThreshold` values vary by agent. Heavy agents (adaptive-local, coding-local) use longer timeouts and higher failure thresholds to account for large model download and load times.

The manager agent does not declare a health readiness script because it has no backend to probe. Its readiness is determined by AgentServer availability on port 7000.

### Package.json Marker

Every agent directory must contain a `package.json` file. These are intentionally minimal dependency markers (typically just `name` and `version`). Their purpose is to trigger Ploinky's AgentServer dependency preparation step, which is required even when the manifest uses `start` rather than the default Node.js entrypoint.

### Manager Enable Entries

The `local-llms-manager` manifest must include an `enable` array that launches `function-selection` and `function-invocation` with the `no-wait` flag. This means the manager becomes MCP-ready immediately while the two model agents load their backends in the background. The `global` scope keyword makes them available workspace-wide rather than scoped to the manager.

## Decisions & Questions

### Question #1: Should Ploinky manifests gain GPU resource declarations?

Response: This is a Ploinky core question, not a local-llms decision. The current `containerSecurity` field only supports `privileged: true`. GPU passthrough remains an operator-level concern handled through Docker/Podman runtime flags. If Ploinky adds a `resources.gpu` manifest field, agent manifests should adopt it.

### Question #2: Should `failureThreshold` be derived from catalog `readinessTimeout`?

Options:
- Calculate `failureThreshold` automatically as `ceil(readinessTimeout / interval)` during a validation or generation step.
- Keep it manually declared per manifest, since different deployment environments may need different thresholds.

## Conclusion

Agent manifests follow a strict contract: shared image, shared start script, AgentServer port first, explicit environment defaults, volume mount under `.ploinky/`, and a local healthcheck wrapper for model-serving agents.
