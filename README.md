# neocrush.nvim

Neovim plugin for [neocrush](https://github.com/taigrr/neocrush) integration.

![Demo](assets/demo.gif)

## Features

- **Edit Highlighting**: Flash highlights on AI-generated edits (like yank highlight)
- **Auto-focus**: Automatically focus and scroll to edited files
- **AI Locations Picker**: Custom Telescope picker for AI-annotated code locations with 3-pane UI
- **Terminal Management**: Toggle/focus/restart Crush terminal
- **Cursor Sync**: Send cursor position to neocrush for context awareness
- **Crush Version Manager**: Browse and install specific crush versions from GitHub or local repo
- **Health Check**: Verify setup with `:checkhealth neocrush`

## Requirements

- Neovim >= 0.10
- [neocrush](https://github.com/taigrr/neocrush) binary in PATH
- [crush](https://github.com/charmbracelet/crush) CLI for terminal integration
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for AI locations picker and CVM
- [glaze.nvim](https://github.com/taigrr/glaze.nvim) — manages Go binary installation/updates automatically

## Installation

```lua
-- lazy.nvim
{
  'taigrr/neocrush.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim', 'taigrr/glaze.nvim' },
  event = 'VeryLazy',
  opts = {
    -- All options are optional with sensible defaults
    highlight_group = 'IncSearch',  -- Flash highlight group
    highlight_duration = 900,        -- Flash duration (ms)
    auto_focus = true,               -- Auto-focus edited files
    terminal_width = 80,             -- Terminal width in columns
    terminal_cmd = 'crush',          -- Command to run in terminal

    -- CVM configuration (optional)
    cvm = {
      upstream = 'charmbracelet/crush',  -- GitHub repo for releases
      local_repo = '~/code/crush',       -- Default path for :CrushCvmLocal
    },

    -- Optional keybindings (none set by default)
    keys = {
      toggle = '<leader>cc',
      focus = '<leader>cf',
      logs = '<leader>cl',
      cancel = '<leader>cx',
      restart = '<leader>cr',
      paste = '<leader>cp',  -- Works in normal (clipboard) and visual (selection) mode
      cvm_releases = '<leader>cvr',
      cvm_local = '<leader>cvl',
    },
  },
}
```

**Note**: The plugin starts the LSP on `VimEnter`, so use `event = 'VeryLazy'` to load after UI is ready.

## Breaking Changes

### v2.0.0

**BREAKING**: Removed `:CrushInstall` and `:CrushUpdate` commands.

Binary management is now handled by [glaze.nvim](https://github.com/taigrr/glaze.nvim).
Use `:GlazeInstall` and `:GlazeUpdate` to install/update binaries.

For version-specific installs (pre-releases, testing), use the Crush Version Manager:

- `:CrushCvmReleases` - Browse and install from GitHub releases
- `:CrushCvmLocal` - Build from local repository

## Commands

| Command             | Description                                   |
| ------------------- | --------------------------------------------- |
| `:CrushToggle`      | Toggle the Crush terminal window              |
| `:CrushOpen`        | Open the Crush terminal                       |
| `:CrushClose`       | Close the Crush terminal (keeps buffer)       |
| `:CrushFocus`       | Focus the Crush terminal                      |
| `:CrushWidth <n>`   | Set terminal width to n columns               |
| `:CrushLogs`        | Show Crush logs in a new buffer               |
| `:CrushCancel`      | Cancel current operation (sends `<Esc><Esc>`) |
| `:CrushRestart`     | Kill and restart the Crush terminal           |
| `:CrushPaste [reg]` | Paste register (default: `+`) or selection    |
| `:CrushFocusToggle` | Toggle auto-focus behavior                    |
| `:CrushFocusOn/Off` | Enable/disable auto-focus                     |
| `:CrushCvmReleases` | Browse and install crush releases from GitHub |
| `:CrushCvmLocal`    | Browse and install from local repo commits    |

### Pasting Registers

`:CrushPaste` defaults to system clipboard (`+`).
Pass a register name to paste from a specific register:

```vim
:CrushPaste a   " Paste from register a
:CrushPaste "   " Paste from unnamed register
:CrushPaste *   " Paste from primary selection (X11)
```

In visual mode, `:CrushPaste` pastes the current selection.

## Crush Version Manager (CVM)

CVM lets you browse and install specific crush versions:

### `:CrushCvmReleases`

Opens a Telescope picker with all GitHub releases. The currently installed version is highlighted in green.

**Requirements**: `gh` CLI (authenticated), `go`, `telescope.nvim`

### `:CrushCvmLocal [path]`

Opens a Telescope picker with commits from a local crush repo. HEAD is highlighted in blue.
Selecting a commit checks it out and runs `go install .`.

**Requirements**: `git`, `go`, `telescope.nvim`

If `[path]` is omitted, uses `cvm.local_repo` from config.

### CVM Configuration

```lua
cvm = {
  -- GitHub repo for releases (controls API endpoint and go install path)
  upstream = 'charmbracelet/crush',

  -- Default path for :CrushCvmLocal when no argument given
  local_repo = '~/code/crush',
}
```

Set `upstream` to a fork's `owner/repo` to install from a different source.

## API

```lua
local crush = require('neocrush')

crush.toggle()              -- Toggle terminal
crush.open() / crush.close() / crush.focus()
crush.set_width(100)

crush.logs()                -- Show logs in new buffer
crush.cancel()              -- Cancel operation (<Esc><Esc>)
crush.restart()             -- Kill and restart terminal
crush.paste()               -- Paste clipboard
crush.paste('a')            -- Paste register "a"
crush.paste_selection()     -- Paste visual selection

crush.toggle_auto_focus()   -- Toggle auto-focus
crush.start_lsp()           -- Manually start LSP
crush.get_client()          -- Get LSP client instance
```

## How It Works

1. **LSP Integration**: Starts `neocrush` on `VimEnter` with no filetype restrictions
2. **Edit Handler**: Overrides `workspace/applyEdit` to flash highlight edits and scroll them into view
3. **Cursor Sync**: Sends `crush/cursorMoved` notifications for context awareness
4. **Terminal**: Manages a persistent terminal buffer for the Crush CLI

## AI Locations Picker

When an AI agent calls the `show_locations` MCP tool, neocrush displays a custom Telescope picker:

```
┌─────────────────────┬────────────────────────────┐
│ file.go:42          │                            │
│ other.go:15         │   [file preview]           │
│ > handler.go:88  ◄──│                            │
│ utils.go:23         │                            │
├─────────────────────┴────────────────────────────┤
│ This handler validates user input but doesn't    │
│ sanitize the email field. Relevant because you   │
│ asked about potential security issues.           │
└──────────────────────────────────────────────────┘
```

**Keybindings:**

- `<CR>` - Jump to selected location
- `<C-q>` - Send all locations to quickfix list
- `<M-q>` - Send selected location to quickfix list

The bottom pane shows the AI's explanation of why each location is relevant to your query.

## Important Notes

**Do NOT add neocrush to Mason/lspconfig.**
This plugin manages the LSP client directly.
If you have neocrush in your LSP config, remove it.

## Known Limitations

When Crush edits open files, you may see external modification warnings.
Add `vim.o.autoread = true` to auto-reload unchanged files.
