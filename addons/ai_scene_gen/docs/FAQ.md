# AI Scene Generator — FAQ

## General

### Can the AI run arbitrary code?
No. The AI produces JSON data only (SceneSpec format). The plugin parses it with `JSON.parse_string()`. No `eval()`, no `Expression`, no `load()` or `preload()` on LLM output. See the Security Model in ARCHITECTURE_INTEGRATED.md.

### Does it work offline?
Yes, with the MockProvider (ships with the plugin). MockProvider returns pre-made JSON responses — no network needed. Ollama also works offline if running locally. Cloud providers (OpenAI, Anthropic) require internet.

### Can I use my own models?
Yes. Use the Ollama provider for any locally-hosted model (Llama, Mistral, CodeLlama, Qwen, DeepSeek, etc.). If your model doesn't appear in the dropdown, type its name in the **Custom** field (e.g. `qwen3.5:27b`). For cloud models, use OpenAI (GPT-4o family) or Anthropic (Claude family). You can also implement a custom provider by extending LLMProvider.

### What if the LLM returns garbage?
The SceneSpecValidator catches invalid JSON and schema violations. If validation fails, the pipeline automatically retries up to 2 times, sending the validation errors back to the LLM for correction (Schema-Retry). If all retries fail, errors are displayed in the dock.

### Is my prompt sent to the cloud?
Only if you use a cloud provider:

- **MockProvider**: No data leaves your machine
- **Ollama (local)**: Data stays on localhost
- **Ollama (remote)**: Data goes to the configured host URL
- **OpenAI**: Data sent to api.openai.com (OpenAI data policies apply)
- **Anthropic**: Data sent to api.anthropic.com (Anthropic data policies apply)

### What Godot versions are supported?
Godot 4.4+ (tested and CI'd on Godot 4.6.1). Pure GDScript, no GDExtension.

### Can I use this in a published game?
The plugin is an EditorPlugin — it runs in the Godot editor only. It does not ship with your game build. Generated scenes become regular Godot nodes.

### How deterministic is scene generation?
With the same seed, prompt, model, and provider, you get the same output. MockProvider is fully deterministic. Real LLM providers may have slight variations due to floating-point differences in model inference.

## Troubleshooting

### Why does "Test Connection" fail?
- API key might be missing or wrong
- Network/firewall blocking the request
- Ollama might not be running
- Provider service might be down

### Why are objects outside my scene bounds?
The post-processor's BoundsClamp pass automatically clamps objects to bounds. If you see POST_WARN_BOUNDS_CLAMPED warnings, objects were moved. Increase bounds or simplify the prompt.

### Can I customize the LLM system prompt?
The system instruction template is in `core/prompt_compiler.gd` (SYSTEM_TEMPLATE constant). Modify it to change LLM behavior, but be careful — changes may break schema validation.

### How do I add my own assets?
Register tags in the AssetTagRegistry, then check them in the dock's Asset Tag Browser. The LLM will reference these tags, and the AssetResolver loads them instead of procedural primitives. See DEVELOPER_GUIDE.md for details.

### Why is Two-Stage mode slower?
Two-Stage makes 2 LLM calls instead of 1: first a planning call, then a spec generation call. This produces better results for complex scenes but takes roughly twice as long.

### What are the SceneSpec .json files?
SceneSpec is the intermediate JSON format between the LLM and the scene builder. Version 1.0.0. You can export them for debugging, sharing, or version control. Import re-runs the pipeline from validation onward (no LLM call needed).
