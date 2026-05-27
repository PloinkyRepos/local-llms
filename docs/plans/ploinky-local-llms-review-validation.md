# Ploinky Local LLM Plan Review Validation

Date: 2026-05-27

## Short Verdict

The review is mostly valid on Ploinky/runtime design issues, but two model/backend claims need correction:

- Ollama, llama.cpp, and LM Studio were suggestions, not hard requirements. The implementation should add whatever runners are needed by the actual model/task contracts.
- The LM Studio headless finding is outdated as written. LM Studio now documents `llmster`, a GUI-less daemon, and publishes a preview Docker image. It should still be experimental until we prove the target container/GPU path.

## Finding Validation

| Finding | Validation | Notes |
|---|---|---|
| F1 backend set too narrow | Valid, with corrections | M2M100 and MADLAD need seq2seq/text-to-text handling; Qwen reranker needs a scoring API. However, FunctionGemma is available in Ollama, TranslateGemma has Ollama and vLLM/SGLang paths, and EuroLLM is a causal instruction model. |
| F2 LM Studio headless blocked | Partially invalid/outdated | LM Studio now documents `llmster` as a standalone headless daemon and has a preview Docker image. It is still not a safe core v1 dependency until Docker/GPU/licensing behavior is smoke-tested. |
| F3 GPU passthrough missing | Valid | Ploinky `containerSecurity` currently only maps `privileged: true`; Docker and Podman need explicit GPU device flags outside the current manifest contract. |
| F4 model download strategy missing | Valid | The plan must define pull/download timing, readiness impact, and operator UX. The `basic/ollama` example uses shared storage and a postinstall bootstrap. |
| F5 port allocation missing | Valid, with nuance | Internal backend ports do not conflict across containers. Ploinky route readiness uses host-side mapped ports, and the current runtime picks the first declared mapping unless it falls back to implicit 7000. |
| F6 RAM bands advisory only | Valid | Current Ploinky manifests do not expose memory limits. The v1 workaround is startup resource checks plus clear refusal for unsafe profiles. |
| F7 manager enable should use no-wait | Valid | `no-wait` is implemented as an edge-local dependency modifier and should be used for default light model agents. |
| F8 per-agent MCP config split | Valid | AgentServer resolves `mcp-config.json` per container/agent; shared dispatcher scripts are fine, but each agent needs its own config and scoped tool surface. |
| F9 readiness protocol unspecified | Valid, stronger than stated | Current startup gating supports TCP/MCP/none. Manifest health probe scripts exist, but readiness script failure warns from the monitor path; it is not sufficient as dependency-wave gating by itself. |
| F10 storage sharing/isolation unspecified | Valid | Shared backend caches should be explicit, with isolated per-agent scratch directories. |
| F11 profiles missing | Valid | Existing agents use deploy-complete `profiles.default` and profile-specific env/ports. |
| F12 about/endpoints missing | Valid | `about` and `endpoints` are part of the agent manifest/routing contract. |
| F13 root catalog non-standard | Not blocking | A top-level catalog is allowed because Ploinky ignores non-manifest files, but agent-local config should still be present or generated for self-contained operation. |
| F14 dynamic promotion hot-add risk | Valid | Generated agent directories are a development/offline operation and require Ploinky rediscovery/start, not live hot-add. |

## Initial Model Audit

| Agent/model | Verified runner direction |
|---|---|
| `facebook/m2m100_418M` | Hugging Face `transformers_seq2seq`; expose translation MCP tool. |
| `google/madlad400-3b-mt` | Hugging Face `transformers_seq2seq`; llama.cpp/T5 GGUF can be a later optimization only after smoke testing. |
| `utter-project/EuroLLM-1.7B-Instruct` | Causal instruction model; use vLLM/SGLang/transformers, or llama.cpp/Ollama if a verified quantization is selected. |
| `google/translategemma-4b-it` | Translation model with vLLM/SGLang instructions and Ollama `translategemma`; use translation-specific MCP/tool contract. |
| `Qwen/Qwen3-Reranker-0.6B` | Reranker/cross-encoder style scoring API, not generic chat completions. |
| `functiongemma` | Ollama-compatible, minimum Ollama version required. |
| `qwen3.5:*` | Ollama-compatible variants exist for 0.8b, 2b, 4b, 9b, 27b, and 35b. |
| `qwen3.6:*` | Ollama-compatible variants exist for 27b and 35b. |
| `granite4.1:*` | Ollama-compatible variants exist for 3b, 8b, and 30b. |
| `hermes3:*` | Ollama-compatible variants exist for 3b and 8b. |
| `phi4-mini:3.8b` | Ollama-compatible. |
| `ministral-3:*` | Ollama-compatible, but the Ollama page declares a minimum/pre-release Ollama version. |
| `gemma4:*` | Ollama-compatible variants exist for e2b/e4b. |

## Ploinky Contract Checks

- Agent discovery requires top-level agent directories with `manifest.json` under the installed repo.
- AgentServer resolves `mcp-config.json` from configured paths, including `/tmp/ploinky/mcp-config.json`, `/code/mcp-config.json`, and cwd.
- `enable[]` supports `no-wait` as a string token or object flag.
- Startup readiness gates TCP/MCP/none against a host-side route port.
- Manifest `health.readiness.script` exists for monitor probes, but failed readiness emits a warning instead of failing the startup wave.
- `containerSecurity` currently supports only `privileged: true`.
- Manifest volumes must live under `.ploinky/`.
- `endpoints.chatCompletions` is command-backed and exposed through AgentServer at `/v1/chat/completions`, with Ploinky routing `/v1/chat/completions/<agent>` to the selected agent.

## Sources Checked

- Local Ploinky: `ploinky/docs/specs/DS003-agent-manifest-and-registry.md`, `DS004-runtime-execution-and-isolation.md`, `DS005-routing-and-web-surfaces.md`, `DS007-dependency-caches-and-startup-readiness.md`.
- Local Ploinky runtime: `ploinky/Agent/server/AgentServer.mjs`, `ploinky/cli/services/docker/agentServiceManager.js`, `ploinky/cli/services/docker/containerSecurity.js`, `ploinky/cli/services/workspaceDependencyGraph.js`, `ploinky/cli/services/startupReadiness.js`, `ploinky/cli/server/utils/agentReadiness.js`, `ploinky/cli/services/docker/healthProbes.js`.
- Local examples: `AssistOSExplorer/explorer/manifest.json`, `AssistOSExplorer/webmeetStt/manifest.json`, `AssistOSExplorer/llmAssistant/mcp-config.json`, `basic/ollama/manifest.json`, `basic/ollama/healthcheck.sh`.
- External docs/model cards:
  - https://huggingface.co/facebook/m2m100_418M
  - https://huggingface.co/google/madlad400-3b-mt
  - https://huggingface.co/Qwen/Qwen3-Reranker-0.6B
  - https://huggingface.co/utter-project/EuroLLM-1.7B-Instruct
  - https://huggingface.co/google/translategemma-4b-it
  - https://ollama.com/library/qwen3.5
  - https://ollama.com/library/qwen3.6
  - https://ollama.com/library/granite4.1
  - https://ollama.com/library/hermes3
  - https://ollama.com/library/phi4-mini:3.8b
  - https://ollama.com/library/ministral-3
  - https://ollama.com/library/functiongemma
  - https://ollama.com/library/gemma4
  - https://lmstudio.ai/docs/developer/core/headless
  - https://hub.docker.com/r/lmstudio/llmster-preview
  - https://docs.docker.com/engine/containers/gpu/
  - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html
