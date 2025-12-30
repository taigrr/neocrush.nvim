# neocrush.nvim

Neovim plugin for [neocrush](https://github.com/taigrr/neocrush) integration.

## Features

- **Edit Highlighting**: Flash highlights on AI-generated edits (like yank highlight)
- **Auto-focus**: Automatically focus edited files in the leftmost code window
- **Terminal Management**: Toggle/focus Crush terminal with keymaps and commands
- **Cursor Sync**: Send cursor position to neocrush for context awareness

## Requirements

- Neovim >= 0.10
- [neocrush](https://github.com/taigrr/neocrush) binary in PATH
- [crush](https://github.com/charmbracelet/crush) CLI for terminal integration

## Installation

### lazy.nvim

```lua
{
  'taigrr/neocrush.nvim',
  event = 'VeryLazy',
  opts = {},
}
```

**Important**: The plugin starts the LSP server on `VimEnter`, so it should load early.
Using `event = 'VeryLazy'` ensures it loads after UI is ready but before you start editing.

### packer.nvim

```lua
use {
  'taigrr/neocrush.nvim',
  config = function()
    require('neocrush').setup()
  end,
}
```

## Configuration

```lua
require('neocrush').setup {
  -- Highlight group for edit flash effect
  highlight_group = 'IncSearch',

  -- Flash duration in milliseconds
  highlight_duration = 900,

  -- Auto-focus edited files in leftmost window
  auto_focus = true,

  -- Terminal width in columns
  terminal_width = 80,

  -- Command to run in terminal
  terminal_cmd = 'crush',

  -- Enable default keymaps (true, false, or table of overrides)
  keymaps = true,
}
```

### Keymap Customization

```lua
-- Disable all keymaps
keymaps = false,

-- Override specific keymaps
keymaps = {
  ['<leader>cc'] = '<leader>ct',  -- Change toggle keymap
  ['<leader>cf'] = false,          -- Disable focus keymap
},
```

## Commands

| Command             | Description                             |
| ------------------- | --------------------------------------- |
| `:CrushToggle`      | Toggle the Crush terminal window        |
| `:CrushOpen`        | Open the Crush terminal                 |
| `:CrushClose`       | Close the Crush terminal (keeps buffer) |
| `:CrushFocus`       | Focus the Crush terminal                |
| `:CrushWidth <n>`   | Set terminal width to n columns         |
| `:CrushFocusToggle` | Toggle auto-focus behavior              |
| `:CrushFocusOn`     | Enable auto-focus                       |
| `:CrushFocusOff`    | Disable auto-focus                      |

## Default Keymaps

| Keymap       | Action                |
| ------------ | --------------------- |
| `<leader>cc` | Toggle Crush terminal |
| `<leader>cf` | Focus Crush terminal  |

## API

```lua
local crush = require('neocrush')

crush.toggle()              -- Toggle terminal
crush.open()                -- Open terminal
crush.close()               -- Close terminal
crush.focus()               -- Focus terminal
crush.set_width(100)        -- Set terminal width

crush.toggle_auto_focus()   -- Toggle auto-focus
crush.enable_auto_focus()   -- Enable auto-focus
crush.disable_auto_focus()  -- Disable auto-focus

crush.start_lsp()           -- Manually start LSP client
crush.get_client()          -- Get LSP client instance
```

## How It Works

1. **LSP Integration**: The plugin starts `neocrush` on `VimEnter` - no filetype restrictions, so it's ready for edits immediately
2. **Edit Handler**: Overrides `workspace/applyEdit` to detect neocrush edits and flash highlight them
3. **Cursor Sync**: Sends `crush/cursorMoved` notifications to keep the LSP server aware of cursor position
4. **Terminal**: Manages a persistent terminal buffer for running the Crush CLI

## Important Notes

**Do NOT add neocrush to your Mason/lspconfig servers table.**
This plugin manages the LSP client directly via `vim.lsp.start()` on `VimEnter`.
Adding it to Mason would cause duplicate clients or conflicts.

This deviates from typical LSP setup, but is necessary for seamless integration
with agentic coding workflows, allowing the LSP to launch and track Crush edits
without opening a file first.

If you previously had neocrush in your LSP config, remove it:

```lua
-- REMOVE this from your lsp.lua / servers table:
['neocrush'] = {
  cmd = { 'neocrush' },
  filetypes = { ... },
  root_markers = { '.git', '.crush' },
},
```

## Known Limitations

### "buffer not loaded" Warning

When neocrush applies edits to a file that isn't currently open in Neovim, you may see a warning like:

```
neocrush: buffer for file:///path/to/file.go is not loaded. Load buffer to get syntax highlighting.
```

This is expected behavior - the LSP server can edit any file, but Neovim needs to load it into a buffer for the flash highlight to work.
The edit still succeeds; you just won't see the highlight animation until you open that file.
