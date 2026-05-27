import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

const AGENT_IDS = [
    'local-llms-manager',
    'language-translation',
    'relevance',
    'function-selection',
    'function-invocation',
    'tool-composition-local',
    'base-local',
    'local',
    'planning-local',
    'validated-planning-local',
    'adaptive-local',
    'coding-local',
];

const VALID_BACKENDS = [
    'ollama', 'llama_cpp', 'transformers_seq2seq', 'reranker',
    'vllm', 'sglang', 'lmstudio_llmster',
];

const VALID_TASK_APIS = ['chat', 'function-calling', 'translation', 'scoring', 'management'];
const VALID_API_SHAPES = ['openai-chat', 'translation', 'scoring'];

const SEQ2SEQ_MODELS = [
    'facebook/m2m100_418M',
    'google/madlad400-3b-mt',
];

const RERANKER_MODELS = [
    'Qwen/Qwen3-Reranker-0.6B',
];

const MANAGER_TOOLS = [
    'list_available_models',
    'register_model',
    'generate_startup_script',
    'register_agent_profile',
    'promote_agent_profile',
    'status_model',
];

const MODEL_AGENT_LIFECYCLE_TOOLS = [
    'list_available_models',
    'start_model',
    'stop_model',
    'status_model',
];

const DEFAULT_ENABLED_AGENTS = ['function-selection', 'function-invocation'];

function loadJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function runDispatcher(toolName, input, extraEnv = {}) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'local-llms-dispatcher-'));
    try {
        const result = spawnSync('sh', [path.join(ROOT, 'scripts', 'dispatcher.sh')], {
            cwd: ROOT,
            input: JSON.stringify(input),
            encoding: 'utf8',
            env: {
                ...process.env,
                TOOL_NAME: toolName,
                LOCAL_LLMS_AGENT_ID: 'function-invocation',
                LOCAL_LLMS_BACKEND: 'ollama',
                LOCAL_LLMS_DATA_DIR: tmp,
                LOCAL_LLMS_CATALOG_DIR: path.join(ROOT, 'catalog'),
                ...extraEnv,
            },
        });
        return { ...result, tmp };
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
}

describe('Catalog validation', () => {
    let backends;

    before(() => {
        backends = loadJson(path.join(ROOT, 'catalog', 'backends.json'));
    });

    it('backends.json has required structure', () => {
        assert.ok(backends.backends, 'Missing backends key');
        assert.ok(typeof backends.backends === 'object');

        for (const [key, entry] of Object.entries(backends.backends)) {
            assert.ok(entry.name, `Backend ${key} missing name`);
            assert.ok(entry.description, `Backend ${key} missing description`);
            assert.ok(typeof entry.internalPort === 'number', `Backend ${key} missing internalPort`);
            assert.ok(VALID_API_SHAPES.includes(entry.apiShape), `Backend ${key} invalid apiShape: ${entry.apiShape}`);
            assert.ok(entry.readinessProbe, `Backend ${key} missing readinessProbe`);
            assert.ok(entry.readinessProbe.type, `Backend ${key} missing readinessProbe.type`);
            assert.ok(entry.readinessProbe.path, `Backend ${key} missing readinessProbe.path`);
            assert.ok(entry.storagePath, `Backend ${key} missing storagePath`);
            assert.ok(entry.storagePath.startsWith('/data/local-llms/'),
                `Backend ${key} storagePath must use the shared Ploinky data mount, got: ${entry.storagePath}`);
            assert.ok(entry.hostStorageKey, `Backend ${key} missing hostStorageKey`);
            assert.ok(entry.runner, `Backend ${key} missing runner`);
        }
    });

    it('all expected backends are defined', () => {
        for (const b of VALID_BACKENDS) {
            assert.ok(backends.backends[b], `Missing backend: ${b}`);
        }
    });

    it('experimental backends are marked', () => {
        assert.strictEqual(backends.backends.vllm.experimental, true);
        assert.strictEqual(backends.backends.sglang.experimental, true);
        assert.strictEqual(backends.backends.lmstudio_llmster.experimental, true);
        assert.strictEqual(backends.backends.ollama.experimental, false);
    });

    for (const agentId of AGENT_IDS) {
        it(`catalog/agents/${agentId}.json is valid`, () => {
            const filePath = path.join(ROOT, 'catalog', 'agents', `${agentId}.json`);
            assert.ok(fs.existsSync(filePath), `Missing catalog file: ${agentId}.json`);
            const agent = loadJson(filePath);

            assert.strictEqual(agent.agentId, agentId);
            assert.ok(agent.description);
            assert.ok(Array.isArray(agent.models));
            assert.ok(typeof agent.defaultModel === 'string');
            assert.ok(agent.backend);
            assert.ok(VALID_TASK_APIS.includes(agent.taskApi) || agent.taskApi === 'chat',
                `Invalid taskApi for ${agentId}: ${agent.taskApi}`);
            assert.ok(agent.ramBand);
            assert.ok(typeof agent.gpuRequired === 'boolean');
            assert.ok(typeof agent.cpuSafe === 'boolean');
            assert.ok(typeof agent.defaultEnabled === 'boolean');
            assert.ok(typeof agent.readinessTimeout === 'number');
            assert.ok(agent.startupPreset);

            for (const model of agent.models) {
                assert.ok(model.name, `Model in ${agentId} missing name`);
                assert.ok(model.backend, `Model ${model.name} in ${agentId} missing backend`);
                assert.ok(model.taskApi, `Model ${model.name} in ${agentId} missing taskApi`);
                if (model.backendModel) {
                    assert.match(model.backendModel, /^[A-Za-z0-9._:/+-]+$/,
                        `Model ${model.name} in ${agentId} has invalid backendModel: ${model.backendModel}`);
                }
            }
        });
    }
});

describe('Agent manifest validation', () => {
    for (const agentId of AGENT_IDS) {
        it(`${agentId}/manifest.json is valid Ploinky manifest`, () => {
            const filePath = path.join(ROOT, agentId, 'manifest.json');
            assert.ok(fs.existsSync(filePath), `Missing manifest: ${agentId}/manifest.json`);
            const manifest = loadJson(filePath);

            assert.ok(manifest.container, `${agentId}: missing container`);
            assert.ok(manifest.about, `${agentId}: missing about`);
            assert.strictEqual(manifest.start, '/opt/local-llms/scripts/start-agent.sh',
                `${agentId}: start must use the shared image runtime path`);
            assert.ok(manifest.profiles, `${agentId}: missing profiles`);
            assert.ok(manifest.profiles.default, `${agentId}: missing profiles.default`);

            const profile = manifest.profiles.default;
            assert.ok(profile.env, `${agentId}: missing profiles.default.env`);
            assert.ok(profile.ports, `${agentId}: missing profiles.default.ports`);

            assert.ok(Array.isArray(profile.ports), `${agentId}: ports must be array`);
            assert.ok(profile.ports.length > 0, `${agentId}: ports must have at least one entry`);

            const firstPort = profile.ports[0];
            assert.ok(firstPort.includes(':7000'), `${agentId}: first port must map to internal 7000 (AgentServer), got: ${firstPort}`);

            if (manifest.volumes) {
                for (const hostPath of Object.keys(manifest.volumes)) {
                    assert.ok(hostPath.startsWith('.ploinky/'),
                        `${agentId}: volume host path must be under .ploinky/, got: ${hostPath}`);
                }
            }

            const packagePath = path.join(ROOT, agentId, 'package.json');
            assert.ok(fs.existsSync(packagePath),
                `${agentId}: package.json is required so Ploinky prepares AgentServer dependencies for start-only agents`);

            const catalogEnv = profile.env.find(e =>
                (typeof e === 'object' ? e.name : e) === 'LOCAL_LLMS_CATALOG_DIR'
            );
            assert.ok(catalogEnv, `${agentId}: missing LOCAL_LLMS_CATALOG_DIR env`);
            assert.strictEqual(catalogEnv.default, '/opt/local-llms/catalog',
                `${agentId}: catalog must resolve from the shared image path`);

            const readinessScript = manifest.health?.readiness?.script;
            if (readinessScript) {
                assert.strictEqual(readinessScript, 'healthcheck.sh',
                    `${agentId}: readiness script must be a local script name, not a path`);
                assert.ok(fs.existsSync(path.join(ROOT, agentId, readinessScript)),
                    `${agentId}: missing local healthcheck wrapper`);
            }
        });
    }
});

describe('MCP config validation', () => {
    for (const agentId of AGENT_IDS) {
        it(`${agentId}/mcp-config.json is valid`, () => {
            const filePath = path.join(ROOT, agentId, 'mcp-config.json');
            assert.ok(fs.existsSync(filePath), `Missing mcp-config: ${agentId}/mcp-config.json`);
            const config = loadJson(filePath);

            assert.ok(config.tools, `${agentId}: missing tools array`);
            assert.ok(Array.isArray(config.tools), `${agentId}: tools must be array`);

            for (const tool of config.tools) {
                assert.ok(tool.name, `${agentId}: tool missing name`);
                assert.ok(tool.description, `${agentId}: tool ${tool.name} missing description`);
                assert.ok(tool.command, `${agentId}: tool ${tool.name} missing command`);
                assert.strictEqual(tool.command, '/opt/local-llms/scripts/dispatcher.sh',
                    `${agentId}: tool ${tool.name} must use the shared image dispatcher path`);
                assert.ok(tool.inputSchema, `${agentId}: tool ${tool.name} missing inputSchema`);
                if (tool.inputSchema.parameters?.type === 'object') {
                    assert.strictEqual(tool.inputSchema.parameters.additionalProperties, true,
                        `${agentId}: tool ${tool.name} parameters must preserve arbitrary keys`);
                }
            }
        });
    }
});

describe('Manager MCP tool surface', () => {
    let managerConfig;

    before(() => {
        managerConfig = loadJson(path.join(ROOT, 'local-llms-manager', 'mcp-config.json'));
    });

    it('manager exposes all required management tools', () => {
        const toolNames = managerConfig.tools.map(t => t.name);
        for (const expected of MANAGER_TOOLS) {
            assert.ok(toolNames.includes(expected), `Manager missing tool: ${expected}`);
        }
    });

    it('manager does not expose model lifecycle tools (start_model, stop_model)', () => {
        const toolNames = managerConfig.tools.map(t => t.name);
        assert.ok(!toolNames.includes('start_model'), 'Manager should not have start_model');
        assert.ok(!toolNames.includes('stop_model'), 'Manager should not have stop_model');
    });
});

describe('Model agent MCP tool surface', () => {
    const modelAgents = AGENT_IDS.filter(id => id !== 'local-llms-manager');

    for (const agentId of modelAgents) {
        it(`${agentId} exposes required lifecycle tools`, () => {
            const config = loadJson(path.join(ROOT, agentId, 'mcp-config.json'));
            const toolNames = config.tools.map(t => t.name);

            for (const expected of MODEL_AGENT_LIFECYCLE_TOOLS) {
                assert.ok(toolNames.includes(expected),
                    `${agentId} missing lifecycle tool: ${expected}`);
            }
        });

        it(`${agentId} does not expose manager-only tools`, () => {
            const config = loadJson(path.join(ROOT, agentId, 'mcp-config.json'));
            const toolNames = config.tools.map(t => t.name);

            assert.ok(!toolNames.includes('generate_startup_script'),
                `${agentId} should not have generate_startup_script`);
            assert.ok(!toolNames.includes('register_agent_profile'),
                `${agentId} should not have register_agent_profile`);
            assert.ok(!toolNames.includes('promote_agent_profile'),
                `${agentId} should not have promote_agent_profile`);
        });
    }
});

describe('Backend selection for models', () => {
    const allCatalogAgents = AGENT_IDS.map(id => {
        return loadJson(path.join(ROOT, 'catalog', 'agents', `${id}.json`));
    });

    it('seq2seq models use transformers_seq2seq backend', () => {
        for (const agent of allCatalogAgents) {
            for (const model of agent.models) {
                if (SEQ2SEQ_MODELS.includes(model.name)) {
                    assert.strictEqual(model.backend, 'transformers_seq2seq',
                        `${model.name} must use transformers_seq2seq, got: ${model.backend}`);
                    assert.strictEqual(model.taskApi, 'translation',
                        `${model.name} must have taskApi=translation, got: ${model.taskApi}`);
                }
            }
        }
    });

    it('reranker models use reranker backend', () => {
        for (const agent of allCatalogAgents) {
            for (const model of agent.models) {
                if (RERANKER_MODELS.includes(model.name)) {
                    assert.strictEqual(model.backend, 'reranker',
                        `${model.name} must use reranker, got: ${model.backend}`);
                    assert.strictEqual(model.taskApi, 'scoring',
                        `${model.name} must have taskApi=scoring, got: ${model.taskApi}`);
                }
            }
        }
    });

    it('seq2seq/reranker models cannot be routed as generic chat-only', () => {
        for (const agent of allCatalogAgents) {
            for (const model of agent.models) {
                if (SEQ2SEQ_MODELS.includes(model.name)) {
                    assert.notStrictEqual(model.backend, 'ollama',
                        `${model.name} must not use ollama (it is a seq2seq model)`);
                    assert.notStrictEqual(model.taskApi, 'chat',
                        `${model.name} must not have taskApi=chat`);
                }
                if (RERANKER_MODELS.includes(model.name)) {
                    assert.notStrictEqual(model.backend, 'ollama',
                        `${model.name} must not use ollama (it is a reranker model)`);
                    assert.notStrictEqual(model.taskApi, 'chat',
                        `${model.name} must not have taskApi=chat`);
                }
            }
        }
    });

    it('functiongemma uses ollama backend', () => {
        for (const agent of allCatalogAgents) {
            for (const model of agent.models) {
                if (model.name === 'functiongemma') {
                    assert.strictEqual(model.backend, 'ollama');
                }
            }
        }
    });

    it('all model backends reference valid backend definitions', () => {
        const backends = loadJson(path.join(ROOT, 'catalog', 'backends.json'));
        for (const agent of allCatalogAgents) {
            for (const model of agent.models) {
                assert.ok(backends.backends[model.backend],
                    `Model ${model.name} in ${agent.agentId} uses unknown backend: ${model.backend}`);
            }
        }
    });
});

describe('Default startup behavior', () => {
    it('manager manifest enables function-selection and function-invocation as no-wait', () => {
        const manifest = loadJson(path.join(ROOT, 'local-llms-manager', 'manifest.json'));
        assert.ok(manifest.enable, 'Manager manifest missing enable');
        assert.ok(Array.isArray(manifest.enable), 'Manager enable must be array');

        const enableStrings = manifest.enable.map(e => typeof e === 'string' ? e : '');

        let foundFunctionSelection = false;
        let foundFunctionInvocation = false;
        for (const entry of enableStrings) {
            const lower = entry.toLowerCase();
            if (lower.includes('function-selection') && lower.includes('no-wait')) {
                foundFunctionSelection = true;
            }
            if (lower.includes('function-invocation') && lower.includes('no-wait')) {
                foundFunctionInvocation = true;
            }
        }

        assert.ok(foundFunctionSelection, 'Manager must enable function-selection with no-wait');
        assert.ok(foundFunctionInvocation, 'Manager must enable function-invocation with no-wait');
    });

    it('default-enabled agents in catalog match manager enable entries', () => {
        for (const agentId of AGENT_IDS) {
            const catalog = loadJson(path.join(ROOT, 'catalog', 'agents', `${agentId}.json`));
            if (catalog.defaultEnabled && agentId !== 'local-llms-manager') {
                assert.ok(DEFAULT_ENABLED_AGENTS.includes(agentId),
                    `${agentId} is defaultEnabled but not in expected default set`);
            }
        }
    });
});

describe('Port ordering', () => {
    for (const agentId of AGENT_IDS) {
        it(`${agentId} has AgentServer port 7000 first`, () => {
            const manifest = loadJson(path.join(ROOT, agentId, 'manifest.json'));
            const ports = manifest.profiles?.default?.ports || [];
            if (ports.length > 0) {
                assert.ok(ports[0].includes(':7000'),
                    `${agentId}: first port must be AgentServer 7000, got: ${ports[0]}`);
            }
        });
    }
});

describe('Generated script paths', () => {
    it('dispatcher generates scripts under .ploinky/data/local-llms', () => {
        const dispatcherPath = path.join(ROOT, 'scripts', 'dispatcher.sh');
        assert.ok(fs.existsSync(dispatcherPath), 'Missing dispatcher.sh');
        const content = fs.readFileSync(dispatcherPath, 'utf8');
        assert.ok(content.includes('${DATA_DIR}/scripts') || content.includes('SCRIPTS_OUTPUT_DIR'),
            'Dispatcher must write scripts under DATA_DIR/scripts');
        assert.ok(!content.includes('/tmp/') || content.includes('.ploinky'),
            'Dispatcher must not write scripts to /tmp or outside .ploinky');
    });

    it('dispatcher rejects traversal profile IDs from AgentServer envelopes', () => {
        const result = runDispatcher('generate_startup_script', {
            tool: 'generate_startup_script',
            input: {
                profileId: '../../escape',
                agentId: 'function-invocation',
                modelName: 'qwen3.5:0.8b',
                backend: 'ollama',
            },
            metadata: {},
        });
        assert.notStrictEqual(result.status, 0, 'Traversal profileId should fail');
        assert.match(result.stdout, /profileId must be a slug/);
    });
});

describe('Dispatcher runtime behavior', () => {
    it('unwraps AgentServer envelopes for model-agent register_model calls', () => {
        const result = runDispatcher('register_model', {
            tool: 'register_model',
            input: {
                modelName: 'demo-model:1b',
                parameters: { temperature: 0.2 },
            },
            metadata: {},
        });
        assert.strictEqual(result.status, 0, result.stderr);
        const output = JSON.parse(result.stdout);
        assert.deepStrictEqual(output, {
            registered: 'demo-model:1b',
            backend: 'ollama',
            agentId: 'function-invocation',
        });
    });

    it('returns a single JSON object for list_available_models', () => {
        const result = runDispatcher('list_available_models', {
            input: { agentFilter: 'function-invocation' },
        });
        assert.strictEqual(result.status, 0, result.stderr);
        const output = JSON.parse(result.stdout);
        assert.ok(Array.isArray(output.catalog));
        assert.ok(Array.isArray(output.registry));
        assert.ok(output.catalog.every(model => model.agentId === 'function-invocation'));
    });

    it('maps catalog model IDs to backend-specific runtime model names', () => {
        const result = runDispatcher('generate_startup_script', {
            input: {
                profileId: 'translate-gemma',
                agentId: 'language-translation',
                modelName: 'google/translategemma-4b-it',
            },
        });
        assert.strictEqual(result.status, 0, result.stderr);
        const output = JSON.parse(result.stdout);
        assert.strictEqual(output.backend, 'ollama');
        assert.strictEqual(output.requestedModel, 'google/translategemma-4b-it');
        assert.strictEqual(output.runtimeModel, 'translategemma:4b');
    });
});

describe('Runner scripts exist', () => {
    const requiredRunners = [
        'ollama.sh',
        'llama-cpp.sh',
        'transformers-seq2seq.sh',
        'reranker.sh',
    ];

    const optionalRunners = [
        'vllm.sh',
        'sglang.sh',
        'lmstudio-llmster.sh',
    ];

    for (const runner of requiredRunners) {
        it(`scripts/runners/${runner} exists and is executable`, () => {
            const p = path.join(ROOT, 'scripts', 'runners', runner);
            assert.ok(fs.existsSync(p), `Missing runner: ${runner}`);
            const stat = fs.statSync(p);
            assert.ok(stat.mode & 0o111, `${runner} is not executable`);
        });
    }

    for (const runner of optionalRunners) {
        it(`scripts/runners/${runner} exists (optional/experimental)`, () => {
            const p = path.join(ROOT, 'scripts', 'runners', runner);
            assert.ok(fs.existsSync(p), `Missing optional runner: ${runner}`);
        });
    }
});

describe('Startup and health scripts', () => {
    it('start-agent checks resources before launching heavy model agents', () => {
        const script = fs.readFileSync(path.join(ROOT, 'scripts', 'start-agent.sh'), 'utf8');
        assert.match(script, /\/proc\/meminfo/);
        assert.match(script, /requires approximately/);
        assert.match(script, /cpuSafe=false/);
    });

    it('start-agent fails when backend readiness or default model pull fails', () => {
        const script = fs.readFileSync(path.join(ROOT, 'scripts', 'start-agent.sh'), 'utf8');
        assert.match(script, /backend process for '\$BACKEND' exited before becoming ready/);
        assert.match(script, /backend did not become ready/);
        assert.match(script, /model pull failed/);
        assert.ok(!script.includes('Continuing anyway'),
            'start-agent must not launch AgentServer after backend readiness failure');
    });

    it('healthcheck probes AgentServer /health for manager mode', () => {
        const script = fs.readFileSync(path.join(ROOT, 'scripts', 'healthcheck.sh'), 'utf8');
        assert.match(script, /127\.0\.0\.1:7000\/health/);
        assert.ok(!script.includes('127.0.0.1:7000/mcp'),
            'GET /mcp is not a valid readiness probe for AgentServer');
    });

    it('runners resolve bundled service files from the shared image runtime path', () => {
        const translationRunner = fs.readFileSync(path.join(ROOT, 'scripts', 'runners', 'transformers-seq2seq.sh'), 'utf8');
        const rerankerRunner = fs.readFileSync(path.join(ROOT, 'scripts', 'runners', 'reranker.sh'), 'utf8');
        assert.match(translationRunner, /LOCAL_LLMS_RUNTIME_DIR:-\/opt\/local-llms/);
        assert.match(rerankerRunner, /LOCAL_LLMS_RUNTIME_DIR:-\/opt\/local-llms/);
        assert.ok(!translationRunner.includes('/code/scripts/services'));
        assert.ok(!rerankerRunner.includes('/code/scripts/services'));
    });
});

describe('Translation agent specifics', () => {
    it('language-translation has translate tool', () => {
        const config = loadJson(path.join(ROOT, 'language-translation', 'mcp-config.json'));
        const toolNames = config.tools.map(t => t.name);
        assert.ok(toolNames.includes('translate'), 'language-translation must expose translate tool');
    });

    it('language-translation default backend is transformers_seq2seq', () => {
        const catalog = loadJson(path.join(ROOT, 'catalog', 'agents', 'language-translation.json'));
        assert.strictEqual(catalog.backend, 'transformers_seq2seq');
    });

    it('TranslateGemma preserves the requested HF ID while using the runnable Ollama tag', () => {
        const catalog = loadJson(path.join(ROOT, 'catalog', 'agents', 'language-translation.json'));
        const model = catalog.models.find(entry => entry.name === 'google/translategemma-4b-it');
        assert.ok(model, 'Missing TranslateGemma model entry');
        assert.strictEqual(model.backend, 'ollama');
        assert.strictEqual(model.backendModel, 'translategemma:4b');
    });

    it('translation service does not report healthy before model load', () => {
        const service = fs.readFileSync(path.join(ROOT, 'scripts', 'services', 'translation_service.py'), 'utf8');
        assert.match(service, /return jsonify\(\{"status": "not_loaded"/);
        assert.match(service, /sys\.exit\(1\)/, 'translation service must fail startup when model preload fails');
    });
});

describe('Relevance agent specifics', () => {
    it('relevance has rerank tool', () => {
        const config = loadJson(path.join(ROOT, 'relevance', 'mcp-config.json'));
        const toolNames = config.tools.map(t => t.name);
        assert.ok(toolNames.includes('rerank'), 'relevance must expose rerank tool');
    });

    it('relevance default backend is reranker', () => {
        const catalog = loadJson(path.join(ROOT, 'catalog', 'agents', 'relevance.json'));
        assert.strictEqual(catalog.backend, 'reranker');
    });

    it('relevance does not expose chat completions API shape', () => {
        const catalog = loadJson(path.join(ROOT, 'catalog', 'agents', 'relevance.json'));
        assert.strictEqual(catalog.taskApi, 'scoring');
        for (const model of catalog.models) {
            assert.notStrictEqual(model.taskApi, 'chat',
                `Reranker model ${model.name} must not have taskApi=chat`);
        }
    });

    it('reranker service uses a CrossEncoder scoring API and gated health', () => {
        const service = fs.readFileSync(path.join(ROOT, 'scripts', 'services', 'reranker_service.py'), 'utf8');
        assert.match(service, /from sentence_transformers import CrossEncoder/);
        assert.ok(!service.includes('AutoModelForSequenceClassification'),
            'Qwen reranker must not be loaded as a generic sequence classifier');
        assert.match(service, /return jsonify\(\{"status": "not_loaded"/);
        assert.match(service, /sys\.exit\(1\)/, 'reranker service must fail startup when model preload fails');
    });
});

describe('Shared image', () => {
    it('Dockerfile exists', () => {
        assert.ok(fs.existsSync(path.join(ROOT, 'Dockerfile')));
    });

    it('all agents use the same container image', () => {
        const images = new Set();
        for (const agentId of AGENT_IDS) {
            const manifest = loadJson(path.join(ROOT, agentId, 'manifest.json'));
            images.add(manifest.container);
        }
        assert.strictEqual(images.size, 1, `Expected 1 shared image, got: ${[...images].join(', ')}`);
    });

    it('Dockerfile copies shared runtime assets into the image', () => {
        const dockerfile = fs.readFileSync(path.join(ROOT, 'Dockerfile'), 'utf8');
        assert.match(dockerfile, /COPY scripts \/opt\/local-llms\/scripts/);
        assert.match(dockerfile, /COPY catalog \/opt\/local-llms\/catalog/);
        assert.match(dockerfile, /LOCAL_LLMS_RUNTIME_DIR=\/opt\/local-llms/);
        assert.match(dockerfile, /LOCAL_LLMS_CATALOG_DIR=\/opt\/local-llms\/catalog/);
    });

    it('Dockerfile installs torch from the CPU index without applying that index to transformers', () => {
        const dockerfile = fs.readFileSync(path.join(ROOT, 'Dockerfile'), 'utf8');
        assert.match(dockerfile, /pip install --no-cache-dir --index-url https:\/\/download\.pytorch\.org\/whl\/cpu torch/);
        assert.match(dockerfile, /pip install --no-cache-dir\s+\\\n\s+transformers/);
        assert.ok(!/--index-url https:\/\/download\.pytorch\.org\/whl\/cpu torch[\s\S]*transformers/.test(
            dockerfile.replace(/&& pip install --no-cache-dir\s+\\\n\s+transformers[\s\S]*/m, '')
        ), 'transformers must not be installed from the PyTorch CPU wheel index');
    });

    it('Dockerfile builds llama-server for llama.cpp runners', () => {
        const dockerfile = fs.readFileSync(path.join(ROOT, 'Dockerfile'), 'utf8');
        assert.match(dockerfile, /llama\.cpp/);
        assert.match(dockerfile, /--target llama-server/);
        assert.match(dockerfile, /\/usr\/local\/bin\/llama-server/);
    });
});

describe('Env defaults are explicit', () => {
    for (const agentId of AGENT_IDS) {
        it(`${agentId} has LOCAL_LLMS_AGENT_ID with correct default`, () => {
            const manifest = loadJson(path.join(ROOT, agentId, 'manifest.json'));
            const envs = manifest.profiles?.default?.env || [];
            const agentIdEnv = envs.find(e =>
                (typeof e === 'object' ? e.name : e) === 'LOCAL_LLMS_AGENT_ID'
            );
            assert.ok(agentIdEnv, `${agentId}: missing LOCAL_LLMS_AGENT_ID env`);
            if (typeof agentIdEnv === 'object') {
                assert.strictEqual(agentIdEnv.default, agentId,
                    `${agentId}: LOCAL_LLMS_AGENT_ID default should be "${agentId}", got: "${agentIdEnv.default}"`);
            }
        });
    }
});
