# AI Scene Generator — Troubleshooting

## Error Code Reference

### UI Errors
| Code | Cause | Solution |
|------|-------|----------|
| UI_ERR_EMPTY_PROMPT | Scene description field is empty | Enter a prompt describing the scene |
| UI_ERR_INVALID_BOUNDS | Bounds axes must be > 0 and <= 1000 | Set each bound axis between 0.5 and 1000 |
| UI_ERR_INVALID_SEED | Seed out of range (0–2,147,483,647) | Enter a valid seed value |
| UI_ERR_NO_SCENE | No scene is open in the editor | Open or create a 3D scene (Node3D root) |
| UI_ERR_NOT_3D | Scene root is not a Node3D | Create a new scene with a Node3D root |

### Orchestrator Errors
| Code | Cause | Solution |
|------|-------|----------|
| ORCH_ERR_ALREADY_RUNNING | Generation already in progress | Wait for current generation to finish |
| ORCH_ERR_STAGE_FAILED | A pipeline stage failed (compile, LLM, validate) | Check the detailed error message; often LLM connectivity |
| ORCH_ERR_RETRY_EXHAUSTED | LLM request failed after all retries (max 2) | Check network, API key, or try a different model |
| ORCH_ERR_CANCELLED | User cancelled the generation | Normal — generation was stopped by user |

### LLM Provider Errors
| Code | Cause | Solution |
|------|-------|----------|
| LLM_ERR_NOT_CONFIGURED | Provider missing HTTP node, model, or API key | Configure the provider (select model, enter API key) |
| LLM_ERR_NETWORK | Network connection failed | Check internet/LAN, firewall, provider URL |
| LLM_ERR_TIMEOUT | Request exceeded 120s timeout | Check if Ollama/API is responding; try smaller model |
| LLM_ERR_AUTH | Authentication failed (401/403) | Check API key is correct and has permissions |
| LLM_ERR_RATE_LIMIT | Provider rate limit hit (429) | Wait and retry; check usage quotas |
| LLM_ERR_SERVER | Provider server error (5xx) | Provider issue — retry later |
| LLM_ERR_NON_JSON | Response is not valid JSON | Model may not support JSON mode; try different model |

### Schema Validation Errors
| Code | Cause | Solution |
|------|-------|----------|
| SPEC_ERR_PARSE | JSON parsing failed or required field missing | Check LLM output quality; try different model |
| SPEC_ERR_TYPE | Field has wrong type (e.g. string instead of number) | LLM formatting issue; schema retry may fix it |
| SPEC_ERR_VERSION | spec_version is not "1.0.0" | Model output wrong version; retry |
| SPEC_ERR_ADDITIONAL_FIELD | Unknown field in spec (security) | Model added unsupported fields |
| SPEC_ERR_NODE_TYPE | Node type not in allowlist | Only MeshInstance3D, StaticBody3D, lights, Camera3D, WorldEnvironment, Node3D |
| SPEC_ERR_PRIMITIVE | Primitive shape not in allowlist | Only box, sphere, cylinder, capsule, plane |
| SPEC_ERR_BOUNDS | Node position outside scene bounds | Adjust bounds or prompt for smaller scene |
| SPEC_ERR_LIMIT_NODES | Too many nodes (exceeds max_nodes) | Reduce scene complexity or increase node limit |
| SPEC_ERR_LIMIT_SCALE | Scale component outside [0.01, max_scale] | Model used extreme scale values |
| SPEC_ERR_LIMIT_ENERGY | Light energy outside [0.0, max_light_energy] | Model used extreme light energy |
| SPEC_ERR_DUPLICATE_ID | Duplicate node IDs in spec | Model reused node IDs |
| SPEC_ERR_CODE_PATTERN | Suspicious code pattern detected (eval, load, etc.) | Security check — model tried to inject code |
| BUILD_ERR_TREE_DEPTH | Scene tree exceeds max depth | Reduce nesting in scene |

### Build Errors
| Code | Cause | Solution |
|------|-------|----------|
| BUILD_ERR_TREE_DEPTH | Node tree too deep | Simplify scene hierarchy |
| BUILD_ERR_ASSET_LOAD | Could not load asset resource | Check asset path exists and is valid |
| BUILD_ERR_ENVIRONMENT | WorldEnvironment build failed | Check environment spec |
| BUILD_ERR_CAMERA | Camera build failed | Check camera spec |
| BUILD_ERR_LIGHT | Light build failed | Check light spec |

### Post-Processing Warnings
| Code | Cause | Solution |
|------|-------|----------|
| POST_WARN_BOUNDS_CLAMPED | Node was moved to fit inside bounds | Increase bounds or adjust prompt |
| POST_WARN_SNAP_MISS | Node floating above ground, couldn't snap | Manually lower node or enable physics snap |
| POST_WARN_SNAP_NO_GROUND | No ground plane found for snapping | Add a "Ground"/"Floor" node |
| POST_WARN_CAMERA_FAR | Camera framing distance > 200m | Reduce bounds or group objects closer |
| POST_WARN_OVERLAP | Two meshes overlap significantly | Move or scale one of them |

### Import/Export Errors
| Code | Cause | Solution |
|------|-------|----------|
| EXPORT_ERR_NO_SPEC | No SceneSpec to export | Generate a scene first |
| EXPORT_ERR_WRITE | Failed to write file | Check file permissions; path must start with res:// |
| IMPORT_ERR_FAILED | Failed to import SceneSpec | Check file exists, is valid JSON, has spec_version 1.0.0 |

### Other Errors
| Code | Cause | Solution |
|------|-------|----------|
| PREVIEW_ERR_NO_SCENE | No scene root for preview | Open a 3D scene |
| PREVIEW_ERR_ALREADY_ACTIVE | Preview already showing | Discard current preview first |
| PREVIEW_ERR_NOT_ACTIVE | Trying to apply when no preview exists | Generate a scene first |
| PROMPT_ERR_EMPTY | Prompt is empty | Enter a prompt |
| PROMPT_ERR_INVALID_PRESET | Unknown style preset | Use blockout, stylized, or realistic-lite |
| PROMPT_ERR_TOO_LONG | Prompt exceeds ~12,000 token estimate | Simplify prompt or reduce constraints |
| ASSET_ERR_NOT_FOUND | Asset tag not found in registry | Register the tag or remove from selection |
| ASSET_ERR_PATH_INVALID | Asset path doesn't start with res:// | Use res:// paths for assets |
| PRIM_ERR_UNKNOWN_SHAPE | Unknown primitive shape type | Use box, sphere, cylinder, capsule, or plane |
| PRIM_ERR_INVALID_SIZE | Primitive size invalid | Use positive, non-zero dimensions |

## Common Problems

### "Generation hangs / takes forever"
- Check network connectivity (for cloud providers)
- Check Ollama is running (`ollama list` in terminal)
- Try a smaller/faster model
- HTTP timeout is 120 seconds — after that LLM_ERR_TIMEOUT fires

### "Scene is empty after generation"
- Check if MockProvider is selected (returns canned response)
- Check LLM response quality — may need a more capable model
- Check error panel for validation errors

### "Undo doesn't work after Apply"
- Undo works via EditorUndoRedoManager (Ctrl+Z)
- Known limitation: Dock state (IDLE/PREVIEW_READY) is not auto-reverted on undo
- Nodes ARE correctly removed on undo

### "Model dropdown is empty"
- Click "Test Connection" to refresh models
- Check API key and network connectivity
- Model cache expires after 1 hour — switch provider to refresh

### "Preview nodes remain after discard"
- Click "Discard" button
- If stuck, close and reopen the scene

## Debug Logging

- **Levels**: DEBUG, INFO, WARNING, ERROR  
- **Default**: DEBUG (set in `plugin.gd` `_enter_tree`)  
- **Prefix**: `[AI_SCENE_GEN][LEVEL][category]`  
- **Categories**: ai_scene_gen.plugin, ai_scene_gen.orchestrator, ai_scene_gen.llm, ai_scene_gen.postprocess, ai_scene_gen.persistence, ai_scene_gen.prompt_compiler  
- **Warnings** also `push_warning()` (Godot Output panel)  
- **Errors** also `push_error()` (Godot Output panel)  
- **Metrics**: `record_metric()` tracks count, sum, min, max, avg for `llm_latency_ms`, `build_node_count`, `build_duration_ms`, `plan_llm_latency_ms`
