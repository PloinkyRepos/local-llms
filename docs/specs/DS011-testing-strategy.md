---
id: DS011
title: Testing Strategy
status: accepted
owner: repository
summary: Validation test suite, syntax checks, dispatcher behavioral tests, and test coverage boundaries.
---

# DS011 Testing Strategy

## Introduction

The local-llms repository uses a single test file (`tests/validate.mjs`) that validates structural and behavioral contracts without requiring Docker, model downloads, or network access. This specification defines what the tests cover, how they are organized, and what remains outside the automated test boundary.

## Core Content

### Test Runner

Tests run with `node --test tests/validate.mjs` using Node.js's built-in test runner (`node:test`) and assertion library (`node:assert/strict`). No external test framework or runner is used. The test file is ESM (`.mjs`).

### Test Categories

The suite is organized into `describe` blocks covering twelve areas:

**Catalog validation** verifies that `backends.json` has the required structure, all expected backends are defined, experimental backends are marked, and every agent catalog file is valid JSON with correct field types and model entries.

**Agent manifest validation** checks that every manifest uses the shared image, the shared start script, includes `profiles.default` with env and ports, declares the AgentServer port first, uses `.ploinky/` volume paths, includes a `package.json` marker, and has the correct `LOCAL_LLMS_CATALOG_DIR` default.

**MCP config validation** verifies that every agent has a `mcp-config.json` with a tools array, that every tool has `name`, `description`, `command` (pointing to the shared dispatcher path), and `inputSchema`.

**Manager tool surface** tests confirm the manager exposes all six management tools and does not expose model lifecycle tools (`start_model`, `stop_model`).

**Model agent tool surface** tests confirm that all model-serving agents expose the four lifecycle tools and do not expose manager-only tools (`generate_startup_script`, `register_agent_profile`, `promote_agent_profile`).

**Backend selection** tests enforce that seq2seq models use the `transformers_seq2seq` backend, reranker models use the `reranker` backend, neither can be routed as generic chat, `functiongemma` uses Ollama, and all model backends reference valid backend definitions.

**Default startup behavior** tests verify the manager manifest enables `function-selection` and `function-invocation` with `no-wait`, and that catalog `defaultEnabled` flags match the expected default set.

**Port ordering** tests confirm every manifest has AgentServer port 7000 as the first port entry.

**Generated script paths** tests verify the dispatcher writes scripts under `DATA_DIR/scripts` and rejects path-traversal profile IDs.

**Dispatcher runtime behavior** tests invoke the dispatcher in a subprocess with temporary data directories to verify envelope unwrapping for `register_model`, JSON output shape for `list_available_models`, and `backendModel` alias resolution for `generate_startup_script`.

**Runner, startup, and health script** tests read script file contents to verify resource checking patterns, failure behavior, service file resolution from the shared image path, and healthcheck endpoint routing.

**Translation and relevance agent specifics** tests verify specialized tool exposure, default backends, TranslateGemma alias behavior, CrossEncoder usage (not AutoModelForSequenceClassification), and gated health in the Python services.

**Shared image** tests verify the Dockerfile exists, all agents use the same container image, the Dockerfile copies runtime assets, installs PyTorch from the CPU index separately from transformers, and builds llama-server.

**Env defaults** tests confirm every manifest has `LOCAL_LLMS_AGENT_ID` with the correct default matching the agent directory name.

### Behavioral Tests

The dispatcher behavioral tests use the `runDispatcher` helper, which spawns `sh dispatcher.sh` with a temporary data directory, passes JSON input via stdin, and captures stdout/stderr/exit code. The temporary directory is cleaned up after each test. These tests validate real dispatcher behavior rather than just structural properties.

### Syntax Checks

In addition to the Node.js test suite, the repository recommends running shell syntax checks (`sh -n`) on all shell scripts and Python compilation checks (`python3 -m py_compile`) on all Python services. These are not part of the automated test file but are documented in the handoff as additional verification steps.

### Test Coverage Boundaries

The test suite covers structural contracts and dispatcher logic that can be validated without running backends. It does not cover:

- Docker image build success (Docker CLI was unavailable in the original implementation environment).
- Ploinky startup smoke tests (require a running Ploinky instance).
- Actual model inference (require downloaded model weights and backend processes).
- Network-dependent operations (model downloads, Ollama API calls).
- Health probe behavior under real startup timing.

These gaps are documented as remaining work in the handoff. Docker build validation and at least one Ploinky startup smoke test per backend family should be added before publishing `assistos/local-llms:latest`.

### Test Result

The suite currently reports 123 passing tests with no failures.

## Decisions & Questions

### Question #1: Should Docker build and Ploinky smoke tests be added to CI?

Response: Yes, once a CI pipeline is configured. The Docker build test would run `docker build` and verify exit code 0. Ploinky smoke tests would start `local-llms-manager`, `function-invocation` (Ollama), `language-translation` (transformers), and `relevance` (reranker) and verify MCP readiness. These require Docker and are not suitable for the lightweight `node --test` suite.

### Question #2: Should dispatcher tests be expanded to cover all tool handlers?

Response: The current tests cover `register_model`, `list_available_models`, and `generate_startup_script` including traversal rejection. Adding tests for `start_model`, `stop_model`, `status_model`, `translate`, and `rerank` would require mocking backend processes, which is complex in shell. The current coverage prioritizes the tool handlers that write to the registry and filesystem.

## Conclusion

The test suite validates 123 structural and behavioral contracts covering catalogs, manifests, MCP configs, tool surfaces, backend routing, dispatcher logic, and script properties. It runs without Docker or network access. Docker build and Ploinky smoke tests are identified as the primary coverage gap for future CI.
