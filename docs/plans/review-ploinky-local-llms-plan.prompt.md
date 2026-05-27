# Claude Code Review Prompt

```text
You are reviewing an implementation plan before any code is written. Work read-only: do not edit files, do not run mutating commands.

Repo root:
  /Users/danielsava/work/file-parser

Plan location:
  /Users/danielsava/work/file-parser/local-llms/docs/plans/ploinky-local-llms-plan.md

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

Context already chosen during planning:
- Runtime architecture: single shared image, not nested Docker.
- Config location: hybrid model.
- Default startup: light only, meaning manager plus function-selection and function-invocation.
- local-llms is currently essentially empty except README.md.
- Existing examples to inspect: AssistOSExplorer/gitAgent, llmAssistant, tasksAgent, explorer.
- Existing related agent: basic/ollama, but it is a single Ollama service, not the intended multi-agent repo.

Relevant workspace rules to check:
- Read /Users/danielsava/work/file-parser/CLAUDE.md first.
- Read ploinky/CLAUDE.md.
- For runtime/manifest/MCP/security, inspect:
  - ploinky/docs/specs/DS003-agent-manifest-and-registry.md
  - ploinky/docs/specs/DS004-runtime-execution-and-isolation.md
  - ploinky/docs/specs/DS005-routing-and-web-surfaces.md
  - ploinky/docs/specs/DS007-dependency-caches-and-startup-readiness.md
  - ploinky/docs/specs/DS011-security-model.md
- Inspect AssistOSExplorer agent patterns:
  - AssistOSExplorer/*/manifest.json
  - AssistOSExplorer/*/mcp-config.json
  - AssistOSExplorer/*/scripts/startAgent.sh

Please review the plan file for:
1. Compatibility with current Ploinky discovery, manifest, dependency graph, startup, port, volume, profile, and MCP contracts.
2. Whether a manager/meta agent with enable[] is the right way to start selected agents by default.
3. Whether the shared AgentServer + mcp-config dispatcher pattern fits the desired tools.
4. Risks in the single-image backend approach, especially Ollama, llama.cpp, and LM Studio headless inside one container.
5. Security/runtime invariant risks: router-mediated MCP, generated secrets, logs, volumes under .ploinky, avoiding Ploinky core hardcoding.
6. Missing files, docs, tests, or decisions needed before implementation.
7. Recommended changes to the plan.

Return:
- Findings first, ordered by severity, with file/spec references.
- Open questions that must be answered before implementation.
- Recommended changes to the plan.
- A short verdict: proceed / proceed with changes / do not proceed yet.
```
