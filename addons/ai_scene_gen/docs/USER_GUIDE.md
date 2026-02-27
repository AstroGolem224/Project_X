# AI Scene Generator — User Guide

## Overview

The AI Scene Generator creates 3D scenes from natural-language prompts using a validated JSON pipeline (SceneSpec). The workflow is safe: no code execution, only structured data that drives scene construction.

---

## UI Overview

The dock panel is built programmatically (no scene file) and appears in the right dock area. Here is every element from top to bottom:

### 1. Header

**"AI Scene Generator"** — Centered title at the top of the panel.

### 2. Scene Description

A multiline **TextEdit** field for your prompt. Placeholder text: *"Describe your scene… e.g. 'a medieval courtyard with a well in the center'"*.

### 3. Settings Section

- **Provider** — Dropdown with: MockProvider, Ollama, OpenAI, Anthropic. A **"Test Connection"** button appears next to it for non-Mock providers.
- **Connection result label** — Shown below the Provider row: "Connected — X models" (green) or "Failed: could not reach provider" (red).
- **Model** — Dropdown populated with models from the selected provider.
- **Host** — URL field visible only when Ollama is selected. Default: *http://localhost:11434*.
- **API Key** — Secret field visible only for OpenAI and Anthropic.
- **Style** — Dropdown: blockout, stylized, realistic-lite.
- **Two-Stage (detailed planning)** — Checkbox.
- **Variation Mode** — Checkbox.
- **Seed** — Spinbox (0–2,147,483,647, default 42) with a **"Random"** button.
- **Bounds (meters)** — X (default 50), Y (default 30), Z (default 50). Range 1–1000, step 0.5.

### 4. Available Asset Tags

A collapsible section titled **"▶ Available Asset Tags"** (or **"▼ Available Asset Tags"** when expanded). Shows registered tags as checkboxes. Tooltips display the resource type (mesh, material, scene, etc.).

### 5. Action Buttons

- **"Generate Scene"** — Main button to start generation.
- **Apply / Discard** row — Two buttons; enabled only after a preview is ready.

### 6. Import / Export

- **"Import Spec"** — Load a `.scenespec.json` file.
- **"Export Spec"** — Save the last generated SceneSpec.

### 7. Status

- **Status label** — One of: "Ready", "Generating…", "Preview ready — apply or discard.", "Errors occurred."
- **Progress bar** — Visible during generation.

### 8. Error Panel

A scrollable area that shows color-coded messages:

- **[!]** Red — Errors
- **[?]** Yellow — Warnings  
- **[i]** Grey — Info

Each entry can include a **Fix:** hint with suggested actions.

---

## Dock States

| State | Generate | Import | Export | Apply / Discard | Progress |
|-------|----------|--------|--------|-----------------|----------|
| **IDLE** | ✓ | ✓ | ✓ | ✗ | Hidden |
| **GENERATING** | ✗ | ✗ | ✗ | ✗ | Visible |
| **PREVIEW_READY** | ✗ | ✗ | ✓ | ✓ | Hidden |
| **ERROR** | ✓ | ✓ | ✓ | ✗ | Hidden |

---

## Prompt Writing Tips

- **Be specific** — "a medieval courtyard with a stone well in the center, cobblestone ground, two wooden benches" works better than "a courtyard".
- **Mention materials and colors** — "red brick walls", "grey stone floor".
- **Specify quantities** — "three oak trees", "five torches on the walls".
- **Style matters** — blockout = grey-box prototyping, stylized = vibrant colors, realistic-lite = neutral palette.
- The LLM always adds: a ground plane, at least one light, and a camera.

---

## Style Presets

| Preset | Description | Best for |
|--------|-------------|----------|
| **blockout** | Simple shapes, solid muted colors, no detail | Grey-box level prototyping |
| **stylized** | Rounded shapes, vibrant colors, slight variation | Stylized games |
| **realistic-lite** | Realistic proportions, neutral palette, subtle detail | Grounded, realistic scenes |

---

## Seed and Determinism

- Same seed + same prompt + same model = same scene output.
- Default seed is 42.
- Click **"Random"** for a new random seed.
- Useful for iterating: change one parameter, keep the seed, compare results.
- Seed range: 0 to 2,147,483,647.

---

## Bounds

- Defines the 3D bounding box in meters (X = width, Y = height, Z = depth).
- Defaults: 50 × 30 × 50 meters.
- Objects placed outside bounds are clamped by post-processing.
- Smaller bounds = denser scenes; larger bounds = more spread out.

---

## Asset Tags

- Register project assets (meshes, materials, scenes) with tags.
- Use the collapsible **Available Asset Tags** section to choose which tags the LLM can use.
- If a tag does not match, the pipeline falls back to procedural primitives (box, sphere, cylinder, capsule, plane).
- Tags show the resource type in the tooltip.

---

## Import / Export

- **Export Spec** — Saves the last generated SceneSpec as a `.scenespec.json` file (res:// paths only).
- **Import Spec** — Loads a SceneSpec file, skips the LLM call, and goes directly to validate → build → preview.
- Useful for sharing scenes, version control, or debugging.
- Format: SceneSpec v1.0.0 JSON.

---

## Preview, Apply, Discard

- After generation, preview nodes appear as temporary children of the scene root.
- **Apply** — Commits nodes permanently to the scene tree (supports Ctrl+Z undo via EditorUndoRedoManager).
- **Discard** — Removes all preview nodes.
- You can re-generate when the dock is back in IDLE state.

---

## Variation Mode

- Enable **"Variation Mode"** to get different results from the same prompt.
- Appends a random variation seed to the prompt internally.
- Useful for exploring different layouts without changing your prompt text.

---

## Two-Stage Mode

- Enable **"Two-Stage (detailed planning)"** for complex scenes.
- Automatically activates for prompts longer than 30 words.
- **Stage 1** — LLM creates a layout plan (object positions, roles).
- **Stage 2** — LLM generates full SceneSpec JSON from the plan.
- Better results for complex, multi-object scenes.

---

## Health Check / Connection Test

- Click **"Test Connection"** next to the Provider dropdown (not shown for MockProvider).
- Tests connectivity by fetching the model list from the provider.
- Shows "Connected — X models" (green) or "Failed: could not reach provider" (red).
- The button is disabled during the test and re-enabled when the result arrives.
- On success, the model dropdown is updated and the model cache is persisted.

---

## Keyboard Shortcuts

- **Ctrl+Z** — Undo an applied preview (full undo/redo support via EditorUndoRedoManager).
