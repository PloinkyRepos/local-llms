# Claude Code Implementation Prompt

```text
You are Claude Code. Implement the revised Ploinky local-llms plan in this workspace.

Repo root:
  /Users/danielsava/work/file-parser

Implementation target repo:
  /Users/danielsava/work/file-parser/local-llms

Canonical revised plan:
  /Users/danielsava/work/file-parser/local-llms/docs/plans/ploinky-local-llms-plan-v2.md

Review validation notes:
  /Users/danielsava/work/file-parser/local-llms/docs/plans/ploinky-local-llms-review-validation.md

Historical original plan:
  /Users/danielsava/work/file-parser/local-llms/docs/plans/ploinky-local-llms-plan.md

Original review prompt:
  /Users/danielsava/work/file-parser/local-llms/docs/plans/review-ploinky-local-llms-plan.prompt.md

Original user request:
"""
Carefully analyze ploinky/ and how ploinky agents should look. Look in AssistOSExplorer/ for examples of ploinky agents.

The local-llms repo should be a ploinky repo that contains multiple ploinky agents, the ones in the table below. Each of the ploinky agents in the table below should start with the same base docker image.

A docker image with multiple types of modes for running local LLMs - a custom docker image that will be pushed to docker hub in the assistos org. The image will contain different docker images used to run local LLMs like ollama, llama.cpp, lmstudio, etc.

Each ploinky agent is an MCP server that has the following tools:
- Add scripts for starting models / registering a new model
- Start / stop / status
- List available models

Configure X agents with startup scripts and parameters:
- Predefined scripts for clearly defined sizes and purposes
- Need suggestions/guidance for where this config should live
- Some of the agents below should start by default in ploinky

Ploinky Agent Name | Model Name | Obs.
language-translation | facebook/m2m100_418M, utter-project/EuroLLM-1.7B-Instruct, google/madlad400-3b-mt, google/translategemma-4b-it | Local translation models
relevance | Qwen/Qwen3-Reranker-0.6B | 0.6B parameters, over 100 languages, declared 32k-token context window, support for task-specific instructions. Relevant when passages are longer, when searching through code, or when more specialized relevance criteria are needed. Heavier than 17M-278M models.
function-selection | functiongemma | Specialized routing; 1-2 GB RAM
function-invocation | qwen3.5:0.8b | Tool calls with simple parameters; 2-4 GB RAM
tool-composition-local | qwen3.5:2b, granite4.1:3b, hermes3:3b | Short tool chains; 4-6 GB RAM
base-local | qwen3.5:4b, granite4.1:3b, phi4-mini:3.8b, ministral-3:3b | General writing and simple plans; 6-8 GB RAM
local | qwen3.5:4b, granite4.1:8b, hermes3:8b | Tool-based workflows; 8-12 GB RAM
planning-local | qwen3.5:9b, granite4.1:8b, ministral-3:8b, gemma4:e2b, gemma4:e4b | DSL planning, reports, specifications; 12-16 GB RAM
validated-planning-local | qwen3.5:9b, granite4.1:8b, qwen3.5:27b | Plans with validation and controlled repair; 16-24 GB RAM
adaptive-local | qwen3.5:27b, granite4.1:30b, qwen3.6:27b | Replanning after execution and errors; 24-32 GB RAM
coding-local | qwen3.6:27b, qwen3.6:35b, granite4.1:30b | Agentic coding in a local repository; 30-48 GB RAM

Create a plan for implementing this.
"""

Important correction from the user:
  Ollama, llama.cpp, and LM Studio were suggestions. They are not hard requirements and not a closed backend set. Add other tools/runners when needed by model architecture or task API.

Before editing:
1. Read /Users/danielsava/work/file-parser/CLAUDE.md.
2. Read /Users/danielsava/work/file-parser/ploinky/CLAUDE.md if present.
3. Read the revised plan and validation notes listed above.
4. Inspect these Ploinky specs and runtime files before choosing manifest/startup/MCP details:
   - /Users/danielsava/work/file-parser/ploinky/docs/specs/DS003-agent-manifest-and-registry.md
   - /Users/danielsava/work/file-parser/ploinky/docs/specs/DS004-runtime-execution-and-isolation.md
   - /Users/danielsava/work/file-parser/ploinky/docs/specs/DS005-routing-and-web-surfaces.md
   - /Users/danielsava/work/file-parser/ploinky/docs/specs/DS007-dependency-caches-and-startup-readiness.md
   - /Users/danielsava/work/file-parser/ploinky/docs/specs/DS011-security-model.md
   - /Users/danielsava/work/file-parser/ploinky/Agent/server/AgentServer.mjs
   - /Users/danielsava/work/file-parser/ploinky/cli/services/docker/agentServiceManager.js
   - /Users/danielsava/work/file-parser/ploinky/cli/services/docker/containerSecurity.js
   - /Users/danielsava/work/file-parser/ploinky/cli/services/startupReadiness.js
   - /Users/danielsava/work/file-parser/ploinky/cli/server/utils/agentReadiness.js
   - /Users/danielsava/work/file-parser/ploinky/cli/services/docker/healthProbes.js
5. Inspect existing agent examples:
   - /Users/danielsava/work/file-parser/AssistOSExplorer/explorer/manifest.json
   - /Users/danielsava/work/file-parser/AssistOSExplorer/webmeetStt/manifest.json
   - /Users/danielsava/work/file-parser/AssistOSExplorer/llmAssistant/mcp-config.json
   - /Users/danielsava/work/file-parser/basic/ollama/manifest.json
   - /Users/danielsava/work/file-parser/basic/ollama/healthcheck.sh

Implementation scope:
- Implement inside /Users/danielsava/work/file-parser/local-llms.
- Do not modify Ploinky core unless the revised plan cannot be implemented without it. If core changes seem necessary, stop and document the exact required extension instead of making a broad runtime change.
- Do not download model weights as part of tests or default verification. Do not bake model weights into the image.
- Do not make LM Studio/llmster a default v1 dependency. It may be represented as an experimental backend only.
- Preserve existing planning docs. Add implementation docs as needed.

Core deliverables:
1. Ploinky agent directories
   Create top-level agent folders:
   - local-llms-manager
   - language-translation
   - relevance
   - function-selection
   - function-invocation
   - tool-composition-local
   - base-local
   - local
   - planning-local
   - validated-planning-local
   - adaptive-local
   - coding-local

   Each agent directory must contain:
   - manifest.json
   - mcp-config.json

   Every manifest must include:
   - about
   - profiles.default
   - explicit env defaults
   - explicit ports, with AgentServer port 7000 first when the Ploinky route should target MCP/AgentServer
   - readiness configuration aligned with current Ploinky TCP/MCP/none startup readiness behavior
   - volumes under .ploinky only
   - endpoint metadata where the agent truly supports the contract

2. Shared image and startup
   Add one shared Dockerfile for assistos/local-llms:<tag>.
   The image should support a practical v1 backend set:
   - Ollama for Ollama-native chat/tool models
   - llama.cpp server for GGUF-backed models
   - lightweight Python services for transformers seq2seq translation and reranker/scoring APIs
   - vLLM/SGLang only if practical for image size and compatibility; otherwise represent them as optional/profile-driven runners
   - LM Studio llmster only as experimental metadata/runner if implemented without making it required

   Add scripts/start-agent.sh. It must:
   - read LOCAL_LLMS_AGENT_ID
   - resolve repo catalog plus workspace registry settings
   - start the selected backend on a known container-local port
   - verify backend/default model readiness when needed
   - launch Ploinky AgentServer only after backend readiness for model-serving agents

   This readiness order matters because Ploinky MCP readiness can otherwise go green while the model backend is still unusable.

3. Backend runners and dispatcher
   Add shared scripts under scripts/:
   - scripts/dispatcher.* for MCP tool dispatch
   - scripts/runners/ollama.sh
   - scripts/runners/llama-cpp.sh
   - scripts/runners/transformers-seq2seq.sh
   - scripts/runners/reranker.sh
   - optional scripts/runners/vllm.sh
   - optional scripts/runners/sglang.sh
   - optional experimental scripts/runners/lmstudio-llmster.sh

   The implementation may use Python or Node for shared logic, but keep the tool surface stable.

4. Catalog and runtime state
   Add:
   - catalog/backends.json
   - catalog/agents/<agent>.json for every agent
   - JSON schema files or validation code for the catalog

   Runtime state must be under .ploinky/data/local-llms:
   - registry.json for dynamic model/profile registrations
   - scripts/<profile-id>/start.sh for generated startup scripts
   - ollama/ shared Ollama root
   - llama-cpp/models/ shared GGUF cache
   - transformers/cache/ shared HuggingFace cache
   - agents/<agent-id>/ per-agent scratch

5. Model routing
   Encode the validated routing decisions:
   - facebook/m2m100_418M -> transformers_seq2seq, translation MCP
   - google/madlad400-3b-mt -> transformers_seq2seq by default
   - utter-project/EuroLLM-1.7B-Instruct -> causal/chat generation through vLLM/SGLang/transformers or verified quantized llama.cpp/Ollama path
   - google/translategemma-4b-it -> Ollama translategemma or vLLM/SGLang with translation-specific MCP behavior
   - Qwen/Qwen3-Reranker-0.6B -> reranker/scoring API, not generic chat completions
   - functiongemma -> Ollama-compatible with minimum Ollama version metadata
   - qwen3.5, qwen3.6, granite4.1, hermes3, phi4-mini, ministral-3, gemma4 -> Ollama-compatible catalog entries with version constraints where applicable

6. MCP tools
   Manager mcp-config.json should expose:
   - list_available_models
   - register_model
   - generate_startup_script
   - register_agent_profile
   - promote_agent_profile
   - status_model

   Model-agent mcp-config.json files should expose only scoped lifecycle tools:
   - list_available_models
   - start_model
   - stop_model
   - status_model
   - register_model only if scoped safely to that agent

   Each agent needs its own mcp-config.json even when the commands call shared dispatcher code.

7. Default startup
   local-llms-manager should enable the default light agents using no-wait:
   - function-selection global no-wait
   - function-invocation global no-wait

   The manager itself should become MCP-ready without waiting for those model-serving agents.

8. Resource and GPU policy
   Do not claim GPU passthrough is solved by the current Ploinky manifest. Current containerSecurity only supports privileged.
   Add catalog metadata for:
   - RAM band
   - gpuRequired
   - recommended VRAM
   - CPU-safe status

   Startup scripts should refuse obviously unsafe defaults when local resource checks can detect the problem. Document the current operator-level GPU requirement:
   - Docker needs --gpus
   - Podman/NVIDIA CDI needs --device nvidia.com/gpu=all and related runtime setup

9. Documentation
   Update README.md or add docs explaining:
   - what agents exist
   - default startup behavior
   - backend families
   - model download strategy
   - storage layout
   - GPU/resource limitations
   - LM Studio/llmster experimental status
   - how to register models and generate startup scripts

10. Tests and verification
   Add tests that can run without downloading model weights:
   - validate catalog schemas
   - validate all agent manifests and mcp-config files
   - verify backend selection for every listed model
   - verify seq2seq/reranker models cannot be routed as generic chat-only models
   - verify manager vs model-agent MCP tool surfaces
   - verify generated script paths stay under .ploinky/data/local-llms
   - verify default-enabled agents and no-wait behavior are represented in the manager manifest
   - verify port ordering where AgentServer must be first

   Run the relevant test suite. If no test runner exists, add a minimal local validation script and run it.

Implementation guidance:
- Follow existing Ploinky and AssistOSExplorer conventions over inventing new manifest shapes.
- Keep generated runtime state out of git except for documented examples/templates.
- Avoid hardcoding secrets or logging prompts/tokens/raw model responses.
- Prefer deterministic JSON and scripts that are easy to review.
- Keep implementation cohesive. If the full Docker backend implementation is too large for one pass, still create the complete Ploinky-compatible repo structure, catalog, manifests, MCP configs, dispatcher interface, mocked/safe runner behavior, docs, and tests so the repo is runnable and verifiable without large model downloads.

When finished, report:
- Files created/changed.
- Which parts are fully implemented versus stubbed/experimental.
- Commands/tests run and their results.
- Any follow-up decisions required before building/publishing assistos/local-llms.
```
