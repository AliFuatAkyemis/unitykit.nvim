# unitykit.nvim

Unity development toolkit — for Neovim.

Completes the methods Unity invokes through reflection (`Awake`, `Start`,
`Update`, `OnCollisionEnter`, …) with the correct signature and body. C# LSPs
do not know about these "magic" methods; unitykit fills that gap.

It covers the MonoBehaviour, ScriptableObject and `UnityEditor.Editor` message
sets, runs as an nvim-cmp source, and reports its own status through
`:checkhealth unitykit`.

## Table of contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Installation](#installation)
  - [1. Verify prerequisites](#1-verify-prerequisites)
  - [2. Add the plugin](#2-add-the-plugin)
  - [3. Register the cmp source](#3-register-the-cmp-source)
  - [4. Prepare the Unity Editor side](#4-prepare-the-unity-editor-side)
  - [5. Verify the setup](#5-verify-the-setup)
- [Usage](#usage)
- [Configuration](#configuration)
- [Health check](#health-check)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Uninstalling](#uninstalling)
- [Documentation](#documentation)
- [License](#license)

## What it does

- Suggests Unity messages while you type inside a class body: MonoBehaviour
  (36 messages), ScriptableObject (6) and Editor (13).
- Inserts the selected message together with its signature and body:

  ```csharp
  void Start()
  {
      █
  }
  ```

- The body can also be a single line: `void Start() { █ }`.
- Hides messages that are already written (can be disabled).
- Resolves the class type from the C# LSP first; without an LSP it scans the
  class declaration, so indirect inheritance such as
  `class Player : BaseEnemy` also works.
- Writes no files and leaves no trace in your project or Neovim config.

## Requirements

| Requirement | Note |
| :-- | :-- |
| **Neovim ≥ 0.10** | Uses the `vim.lsp.get_clients` and `vim.health` APIs. |
| **[nvim-cmp](https://github.com/hrsh7th/nvim-cmp)** | The only required dependency. |
| **Unity project** | `Assets/` and `ProjectSettings/ProjectVersion.txt` must exist at the root. |
| **C# LSP** *(optional)* | Roslyn is recommended. Without one, the plugin only works in classes that declare `: MonoBehaviour`, `: ScriptableObject` or `: Editor` directly. |

## Installation

The steps below are meant for someone installing the plugin for the first time.
Each step builds on the previous one.

### 1. Verify prerequisites

```bash
nvim --version | head -1   # must be v0.10 or later
git --version
```

If `nvim-cmp` is not installed yet, add it first (lazy.nvim example):

```lua
-- lua/plugins/cmp.lua
return {
  "hrsh7th/nvim-cmp",
  dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer" },
  config = function()
    require("cmp").setup()
  end,
}
```

### 2. Add the plugin

Create `lua/plugins/unitykit.lua`:

```lua
return {
  "AliFuatAkyemis/unitykit.nvim",
  dependencies = { "hrsh7th/nvim-cmp" },
  config = function()
    require("unitykit").setup()
  end,
}
```

Restart Neovim; lazy.nvim downloads the plugin. `unitykit.nvim` should appear in
the `:Lazy` window.

> If you use a plugin manager other than lazy.nvim, adapt the same
> `dependencies` + `require("unitykit").setup()` pair to your spec format.

### 3. Register the cmp source

`require("unitykit").setup()` registers the source with cmp, but **priority is
set on the cmp side**:

```lua
require("cmp").setup({
  sources = {
    { name = "unitykit", priority = 1000 },
    { name = "nvim_lsp" },
    { name = "buffer" },
  },
})
```

cmp does not read a `priority` field from the source table; priority is only
configured in the `sources` list. `unitykit.setup()` registers the source once
per process; repeated calls only update the configuration.

### 4. Prepare the Unity Editor side

unitykit is a Neovim plugin; it is not installed into the Unity project as a
package. The Editor side only needs **project file generation** and, optionally,
Unity opening files in Neovim.

1. **Generate project files.** In Unity open
   `Edit ▸ Preferences ▸ External Tools` and under *Generate .csproj files for*
   tick at least **Registry packages** and **Local packages**. Then press
   **Regenerate project files**. `.sln` and `.csproj` files appear at the project
   root; the C# LSP reads them (the LSP is optional — unitykit works without it).
2. **IDE package (recommended).** Install the `Visual Studio Editor` or
   `JetBrains Rider Editor` package from
   `Window ▸ Package Manager ▸ Unity Registry`. These packages provide the
   *Regenerate project files* button and external editor integration.
3. **Make Neovim the external editor (optional).** Unity cannot launch Neovim
   directly; a small wrapper script is required:

   ```bash
   # ~/bin/unity-nvim  (chmod +x ~/bin/unity-nvim)
   #!/usr/bin/env bash
   exec alacritty -e nvim "+call cursor($2, $3)" "$1"
   ```

   Select this script via
   `External Tools ▸ External Script Editor ▸ Browse`. Unity passes the file
   name, line and column as arguments; replace the terminal emulator in the
   script with the one you use.

> Nothing is installed from Neovim into Unity; no changes are made under
> `Assets/`, `Packages/` or `ProjectSettings/`. Step 1 is only needed for the C#
> LSP, not for unitykit itself.

### 5. Verify the setup

Open a C# file (inside a Unity project) and run:

```vim
:checkhealth unitykit
```

A healthy setup shows:

```text
- OK Neovim 0.10+ ...
- OK nvim-cmp is installed
- OK Source: unitykit is registered
- OK Unity project root: /path/to/project
- OK C# LSP: roslyn            (when an LSP is available)
```

Finally, type `Sta` inside a class body and open the completion list; the
`Start()` suggestion should arrive with its body.

## Usage

1. Open a `.cs` file inside a Unity project.
2. Type a few letters of a message name inside a class body.
3. Pick it from the nvim-cmp list; the signature and body are inserted as a
   snippet.

Completions are only offered when:

- the buffer `filetype` is `cs` (configurable),
- the buffer is a regular file (`buftype` empty and `modifiable`),
- the file is under a Unity root,
- the cursor is inside the body of a recognized Unity class.

If the class type cannot be determined (for example indirect inheritance without
`: MonoBehaviour` and without an LSP), no suggestions appear — this is a
deliberate limitation: it stays silent rather than offering wrong suggestions.

## Configuration

All keys are optional.

```lua
require("unitykit").setup({
  filetypes = { "cs" },
  body = "block",            -- "block" | "line"
  access = "none",           -- "none" | "private" | "public" | "protected"
  hide_implemented = true,
  priority = true,           -- sortText prefix; not the cmp source priority
  timeout_ms = 1500,
})
```

| Key | Default | Description |
| :-- | :-- | :-- |
| `filetypes` | `{ "cs" }` | Filetypes for which suggestions are offered. |
| `body` | `"block"` | `"block"` for a multi-line body, `"line"` for a single line. |
| `access` | `"none"` | Access modifier added to messages that do not declare their own. |
| `hide_implemented` | `true` | Removes message names already present in the class from the list (case-sensitive). |
| `priority` | `true` | Gives items `sortText = "0" .. name`, so Unity messages sort above LSP items. |
| `timeout_ms` | `1500` | How long to wait for an LSP response. Completion is not blocked; the regex result returns immediately and a valid LSP response overwrites it afterwards. |

`setup` returns the merged config table. Invalid `body` / `access` values warn
and fall back to the default. Source registration succeeds once; if nvim-cmp is
not loaded at that moment, the next `setup()` call retries the registration.
`require("unitykit").is_registered()` reports the registration state.
Details: `:help unitykit-config`.

## Health check

```vim
:checkhealth unitykit
```

Reports the Neovim version, nvim-cmp, the registered source, the Unity root of
the active buffer and the C# LSP clients. The context source (`lsp` / `fallback`),
class name and type are shown only when present in the cache; `:checkhealth`
does not resolve context and sends no LSP requests.

## Troubleshooting

| Symptom | Likely cause / fix |
| :-- | :-- |
| No suggestions at all | `:checkhealth unitykit` — is the source registered, is the file under a Unity root? |
| `Source: unitykit is not registered` | `setup()` ran before nvim-cmp was loaded. Call `setup()` inside `config = function()` and restart Neovim. |
| Suggestions appear at the bottom of the list | Add `priority = 1000` to the cmp `sources` list; `setup({ priority = true })` only affects `sortText`. |
| Unity root not found | The project root must contain `Assets/` and `ProjectSettings/ProjectVersion.txt`; files outside that tree do not work. |
| No suggestions for indirect inheritance | Install a C# LSP (Roslyn) and make sure `.sln` / `.csproj` files are generated. |

## Limitations

- **`blink.cmp` is not supported.** Only an nvim-cmp source exists, so
  installations using blink.cmp will not see suggestions.
- Message lists ship with the plugin (static); they are not updated
  automatically per Unity version.
- Only three class types are recognized: MonoBehaviour, ScriptableObject and
  `UnityEditor.Editor`.

## Uninstalling

The plugin writes no files, cache directory or Unity project settings. To remove
it, revert only the lines you added:

1. **Delete the plugin spec** — remove `lua/plugins/unitykit.lua` (or the block
   from the file where you added the spec).
2. **Remove the cmp source registration** — remove the
   `{ name = "unitykit", priority = 1000 }` line from
   `require("cmp").setup({ sources = ... })`.
3. **Remove the `setup()` call if present** — if you configured the plugin
   elsewhere with `require("unitykit").setup({...})`, drop that block.
4. **Clean the plugin from disk** — restart Neovim and run:

   ```vim
   :Lazy clean
   ```

   This deletes plugins that no longer have a spec (including unitykit.nvim).
   To remove it by hand:
   `rm -rf ~/.local/share/nvim/lazy/unitykit.nvim`.

5. **Verify** — `:checkhealth unitykit` should now say "not found", and the
   plugin should no longer appear in the `:Lazy` list.

Notes on leftovers:

- If you use `lazy-lock.json`, the `unitykit.nvim` entry drops out by itself
  after `:Lazy clean`; if it does not, delete that line from the file.
- There is nothing to clean up in the Unity project: nothing is written under
  `Assets/`, `Packages/` or `ProjectSettings/`. The `.sln` / `.csproj` files
  mentioned in step 4 belong to Unity and are needed by the LSP; uninstalling
  unitykit does not require deleting them.
- All plugin state is kept in memory (buffer cache, cmp registration) and
  disappears when Neovim exits.

## Documentation

- Help: `:help unitykit` (source: `doc/unitykit.txt`)
- Design: `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md`

## License

MIT — see the `LICENSE` file.
