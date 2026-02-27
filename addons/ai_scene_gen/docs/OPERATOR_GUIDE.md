# AI Scene Generator — Operator Guide

> For project leads, tech leads, and admins who need to configure the plugin for their team.
>
> Godot 4.6.1 EditorPlugin

---

## Overview

The AI Scene Generator is an EditorPlugin that generates 3D scenes from natural-language prompts. It uses an LLM to produce a JSON SceneSpec, which is validated, resolved, and built into a Godot scene tree.

This guide covers provider setup, API key management, network requirements, performance tuning, security, and model caching — for operators configuring the plugin in a shared or restricted environment.

---

## Provider Setup

### MockProvider

- Ships with the plugin; works fully **offline**.
- No API key, no network needed.
- Returns canned JSON responses from `addons/ai_scene_gen/mocks/`:
  - `outdoor_clearing.scenespec.json`
  - `interior_room.scenespec.json`
- Ideal for testing the pipeline without an LLM.
- `needs_api_key()` = `false`, `needs_base_url()` = `false`.

### Ollama (Local LLM)

- Install Ollama: https://ollama.com
- Pull a model: `ollama pull llama3` (or any model that handles JSON).
- Default URL: `http://localhost:11434`
- Configurable **Host URL** field in the dock (stored per-provider in EditorSettings).
- `needs_api_key()` = `false`, `needs_base_url()` = `true`
- Models are auto-fetched from the `/api/tags` endpoint.
- For remote Ollama: set `OLLAMA_HOST=0.0.0.0` on the server, then enter `http://IP:11434` in the Host field.

### OpenAI

- Requires API key from https://platform.openai.com/api-keys
- API Base: `https://api.openai.com`
- Endpoints: `/v1/chat/completions` (generation), `/v1/models` (model list)
- Default models: `gpt-4o`, `gpt-4o-mini`
- Models are fetched via API and filtered to the `gpt-*` family.
- Uses JSON response mode (`response_format: json_object`).
- `needs_api_key()` = `true`, `needs_base_url()` = `false`

### Anthropic

- Requires API key from https://console.anthropic.com
- API Base: `https://api.anthropic.com`
- Endpoint: `/v1/messages`
- Required header: `anthropic-version: 2023-06-01`
- Default model: `claude-sonnet-4-20250514`
- No public model-list endpoint — plugin returns hardcoded defaults.
- `max_tokens`: 4096
- `needs_api_key()` = `true`, `needs_base_url()` = `false`

---

## API Key Management

- API keys are stored in **Godot EditorSettings** (not in project files).
- EditorSettings path for keys: `ai_scene_gen/api_keys/{ProviderName}`
- Provider URLs: `ai_scene_gen/provider_urls/{ProviderName}`
- Keys persist across sessions and are **per-user** (not shared via version control).
- Keys are entered in the dock’s masked “API Key” field.
- **Never commit API keys to version control.**

---

## Network Requirements

| Provider       | Network                    | Port |
|----------------|----------------------------|------|
| MockProvider   | None (fully offline)       | —    |
| Ollama         | HTTP to localhost or host  | 11434 |
| OpenAI         | HTTPS to api.openai.com    | 443  |
| Anthropic      | HTTPS to api.anthropic.com | 443  |

- **Firewall**: Allow outbound HTTPS (443) for cloud providers.
- **Proxy**: Not natively supported; configure at OS level if needed.
- **Timeout**: 120 seconds (`HTTP_TIMEOUT` in `plugin.gd`, configurable via code).

---

## Offline Mode

- Select **MockProvider** — no network required.
- Returns deterministic canned responses from the mocks directory.
- Full pipeline runs: validate → resolve → build → post-process → preview.
- Suitable for CI testing, demos, and offline environments.

---

## Performance Tuning

### Node Limits

- Default `max_nodes`: **256** (SceneSpec validator enforces this).
- Configurable range: **1–1024**
- Higher values mean longer build times and heavier scene trees.
- Setting is in `DEFAULT_SETTINGS` of `util/persistence.gd`.

### Poly Budget

- Procedural primitives (box, sphere, cylinder, capsule, plane) have fixed vertex counts.
- Sphere has the highest poly count — prefer box or plane for large flat surfaces.
- `MeshInstance3D` nodes can reference project assets via asset tags for custom geometry.

### Timeout

- `HTTP_TIMEOUT` = **120.0** seconds (`plugin.gd`).
- Ollama (local): typically 5–30 seconds, depending on model size.
- OpenAI: typically 5–15 seconds.
- Anthropic: typically 5–20 seconds.
- On timeout: `LLM_ERR_TIMEOUT` error; pipeline fails.

### Retries

- **JSON retries**: `MAX_JSON_RETRIES` = 2 (LLM returns non-success).
- **Schema retries**: `MAX_SCHEMA_RETRIES` = 2 (JSON passes but fails schema validation — LLM receives error feedback and is retried).
- Worst case: up to **5 LLM calls** per generation (3 JSON attempts + 2 schema retries).

---

## Security

### What Data Leaves the Machine

| Provider          | Data sent                                             |
|-------------------|-------------------------------------------------------|
| MockProvider      | Nothing (fully local)                                 |
| Ollama (local)    | Prompt to localhost only                              |
| Ollama (remote)   | Prompt to configured host URL (LAN/WAN)               |
| OpenAI            | Prompt to api.openai.com (subject to OpenAI policies) |
| Anthropic         | Prompt to api.anthropic.com (subject to Anthropic policies) |

### Safety Invariants (Never Broken)

1. No `eval()`, `Expression`, `load()`, or `preload()` on LLM output.
2. Allowlists are constants — not loaded from external files.
3. All file paths must start with `res://`.
4. API keys live in EditorSettings, not in project files.
5. JSON schema uses `additionalProperties: false` — no unknown fields.
6. LLM output is parsed only as JSON (`JSON.parse_string()`).

### What the LLM Can and Cannot Do

- **Can**: Output JSON describing node positions, types, materials, lights, cameras.
- **Cannot**: Execute code, load scripts, access the filesystem, or modify project settings.

- **Node types** (allowlist): `MeshInstance3D`, `StaticBody3D`, `DirectionalLight3D`, `OmniLight3D`, `SpotLight3D`, `Camera3D`, `WorldEnvironment`, `Node3D`.
- **Primitive shapes** (allowlist): `box`, `sphere`, `cylinder`, `capsule`, `plane`.
- **Code injection patterns** (`eval`, `Expression`, `load`, `preload`, `OS.`, `FileAccess`) are detected and rejected by the validator.

---

## Model Cache

- Model lists are cached per-provider in:
  - `res://addons/ai_scene_gen/cache/models_{Provider}.json`
- **Cache TTL**: 1 hour (3600 seconds).
- Cache is loaded on provider switch for instant UI; async fetch updates it in the background.
- Cache is refreshed after a successful fetch or connection test.
- **Cache format**:
  ```json
  {
    "models": ["model-a", "model-b"],
    "timestamp": 1730123456
  }
  ```
