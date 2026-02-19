# AGENTS.md - neocrush.nvim

## Project Overview

Neovim plugin (Lua) for [neocrush](https://github.com/taigrr/neocrush) LSP integration. Provides flash highlights on AI edits, auto-focus of edited files, a Crush terminal manager, cursor/selection sync, and a Telescope-based AI locations picker.

**Requirements**: Neovim >= 0.10, `neocrush` binary, `crush` CLI, `glaze.nvim` for binary management, optional `telescope.nvim`.

## Commands

```bash
make test       # Run tests (requires nvim + plenary.nvim)
make lint       # Check formatting with stylua
make format     # Auto-format lua/ and tests/ with stylua
make demo       # Generate demo GIF (requires vhs: brew install vhs)
```

### Test Details

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted-style runner. They run headless inside Neovim:

```bash
nvim --headless --noplugin -u scripts/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = './scripts/minimal_init.vim' }"
```

The minimal init at `scripts/minimal_init.vim` adds plenary.nvim from `~/.local/share/nvim/lazy/plenary.nvim/` to runtimepath. Tests use `describe`, `it`, `before_each`, `after_each`, `assert` globals (declared in `.luarc.json`).

**CI**: Only the `lint` job runs in GitHub Actions (`.github/workflows/ci.yml`). The unit test job is commented out. The VHS demo workflow is manual dispatch only.

## Project Structure

```
lua/neocrush/
  init.lua        # Thin orchestrator: types, config, auto-focus API, setup(), delegates to submodules
  terminal.lua    # Terminal state & management: open/close/toggle/focus/restart/paste/cancel/logs
  lsp.lua         # LSP client, workspace/applyEdit handler, flash highlights, cursor/selection sync
  commands.lua    # User command registration and keybinding setup
  health.lua      # :checkhealth neocrush implementation
  install.lua     # Simple utility: is_installed() helper (binary management via glaze.nvim)
  locations.lua   # Telescope picker for AI-annotated code locations (with quickfix fallback)
  cvm/            # Crush Version Manager directory
    init.lua      # CVM entry point: config, setup, version detection, install functions
    releases.lua  # Telescope picker for GitHub releases
    local.lua     # Telescope picker for local repo commits
plugin/
  neocrush.lua    # Plugin loader (guard, version check, binary check)
tests/
  neocrush_spec.lua   # Tests for setup() and auto_focus API
  install_spec.lua    # Tests for install.is_installed()
  cvm_spec.lua        # Tests for CVM setup and version detection
scripts/
  minimal_init.vim    # Test harness init (loads plenary + plugin)
  vhs_init.lua        # VHS demo recording init
doc/
  neocrush.txt        # Vim help documentation
demo/
  demo.tape           # VHS tape for generating demo GIF
```

## Code Conventions

### Formatting (StyLua)

Configured in `.stylua.toml`:

- **Indent**: 2 spaces
- **Column width**: 120
- **Quote style**: `AutoPreferSingle` (single quotes preferred)
- **Call parentheses**: `None` (omit parens on single-string/table args)
- **Line endings**: Unix

This means function calls look like `vim.cmd 'startinsert'` not `vim.cmd('startinsert')`, and `require 'neocrush'` not `require('neocrush')`. Multi-arg calls still use parens normally.

### Lua Style

- **Runtime**: LuaJIT (configured in `.luarc.json`)
- **Type annotations**: EmmyLua-style `---@class`, `---@field`, `---@param`, `---@return`, `---@type`
- **Module pattern**: Each file returns a table `M = {}` with public functions
- **Private functions**: Local functions above `M`, not on the module table
- **Test helpers**: Exposed as `M._name` (underscore prefix) for unit testing — see `M._is_file_window`, `M._find_edit_target_window`, `M._flash_range`, `M._is_handler_installed`
- **Section separators**: `-------------------------------------------------------------------------------` comment blocks with section titles
- **Doc blocks**: `---@brief [[ ... ---@brief ]]` at file top for vimdoc generation

### Naming

- **Functions**: `snake_case` for both public and private
- **Variables**: `snake_case`
- **Constants**: `snake_case` (e.g., `local ns = ...`)
- **User commands**: `CamelCase` with `Crush` prefix (e.g., `:CrushToggle`, `:CrushFocusOn`)
- **Autocommand groups**: `Neocrush` prefix + `CamelCase` (e.g., `NeocrushCursorSync`, `NeocrushLspAttach`)
- **Highlight namespace**: `neocrush-highlight`

### API Pattern

- Public API exposed via `require('neocrush')` module table
- `setup(opts)` merges user config with defaults via `vim.tbl_deep_extend('force', ...)`
- User commands are created in `setup()`, not at load time
- LSP starts automatically on `VimEnter`/`BufEnter` (not via lspconfig/Mason)
- Keybindings are opt-in via `opts.keys` table

## Architecture

### Module Organization

The plugin is split into focused submodules, all orchestrated by `init.lua`:

- **`init.lua`** — Config, types, auto-focus API, `setup()`. Delegates terminal/LSP/commands to submodules. Preserves backward-compatible public API (`require('neocrush').open()`, etc.). Registers binaries with glaze.nvim if available.
- **`terminal.lua`** — Owns terminal state (`crush_win`, `crush_buf`). Exposes `find_edit_target_window()` and `get_visual_selection_text()` used by other modules.
- **`lsp.lua`** — LSP client lifecycle, `workspace/applyEdit` handler override, flash highlights, cursor/selection sync autocmds.
- **`commands.lua`** — All `nvim_create_user_command` registrations and keybinding setup. Receives the main module table to call auto-focus API.
- **`install.lua`** — Simple utility module with `is_installed()` helper. Binary management is handled by glaze.nvim.
- **`locations.lua`** — Telescope picker for `crush/showLocations`. Uses `terminal.find_edit_target_window()`.
- **`cvm/`** — Crush Version Manager directory with `init.lua`, `releases.lua`, `local.lua`. Self-contained module for version-specific installs.

### LSP Integration

The plugin manages its own LSP client directly — **do not add neocrush to Mason or lspconfig**. Key details:

- `start_lsp()` calls `vim.lsp.start` with `name = 'neocrush'` and `cmd = { 'neocrush' }`
- Root dir: git root if available, else `cwd`
- Custom handlers for `workspace/applyEdit` (flash highlight) and `crush/showLocations` (Telescope picker)
- Cursor sync via `crush/cursorMoved` notification (50ms debounce)
- Selection sync via `crush/selectionChanged` notification on visual mode exit

### Terminal Management

- Persistent terminal buffer (`crush_buf`) survives window close
- Terminal opens in `botright vsplit` with configurable width
- Close hides the window but keeps the buffer/process alive
- Guard against closing last window when hiding terminal

### Workspace Edit Handler

The `workspace/applyEdit` handler is globally overridden. For neocrush edits: applies edit, flash highlights changed ranges, scrolls to edit, restores focus. For other LSP clients: delegates to original handler.

### Locations Picker

`lua/neocrush/locations.lua` handles `crush/showLocations` LSP notifications. Uses Telescope 3-pane layout (file list + preview + floating notes window) if available, otherwise falls back to quickfix. Supports `<C-q>` (send all to quickfix) and `<M-q>` (send selected to quickfix).

### Crush Version Manager (CVM)

`lua/neocrush/cvm/` provides two Telescope pickers for managing crush versions:

- **`:CrushCvmReleases`** — Fetches releases from GitHub via `gh api`, displays tag + release name with markdown release notes in the preview pane. Currently installed version is highlighted with `CrushCvmCurrent` (green). Selecting a release prompts to `go install` that tag.
- **`:CrushCvmLocal <path>`** — Reads commits from a local git clone, displays short hash + refs with commit details + `git show --stat` in preview. HEAD is highlighted with `CrushCvmHead` (blue). Selecting a commit prompts to `git checkout` + `go install .`.

**Config**: `cvm.upstream` (default `'charmbracelet/crush'`) controls the GitHub repo and Go module path. Set to a fork's `owner/repo` to install from a different source.

**Dependencies**: `gh` CLI (authenticated) for remote releases, `go` for installation, `git` for local repo browsing, `telescope.nvim` for the picker UI, optional `glow` for formatted release notes (falls back to plain markdown). Release data and rendered notes are cached in-memory per session.

## Gotchas

- **Plugin loader guard**: `plugin/neocrush.lua` uses `vim.g.loaded_crush_lsp` to prevent double-loading
- **Handler installation**: The `workspace/applyEdit` override is global and uses `handler_installed` flag to avoid re-installation. It saves/restores the original handler for non-neocrush clients
- **Swap file suppression**: The edit handler temporarily disables `vim.o.swapfile` during `apply_workspace_edit` to suppress E325 prompts, then restores it
- **Terminal buffer is unlisted**: `vim.bo[crush_buf].buflisted = false` — the terminal won't show in buffer lists
- **Cursor sync skips special buffers**: `setup_cursor_sync` and `setup_selection_sync` return early for `terminal`, `nofile`, and `prompt` buftypes
- **Test diagnostic suppression**: Test files start with `---@diagnostic disable: undefined-field` to suppress Lua LS warnings about plenary test globals
- **VHS demo**: Requires `PLUGIN_PATH` env var pointing to plugin root. Uses `--clean` Neovim with custom init to avoid user config interference
