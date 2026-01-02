# neocrush.nvim

Neovim plugin for [neocrush](https://github.com/taigrr/neocrush) integration.

## Features

- **Edit Highlighting**: Flash highlights on AI-generated edits (like yank highlight)
- **Auto-focus**: Automatically focus edited files in the leftmost code window
- **Terminal Management**: Toggle/focus Crush terminal with commands
- **Cursor Sync**: Send cursor position to neocrush for context awareness
- **Binary Management**: Install/update binaries with `:CrushInstallBinaries`/`:CrushUpdateBinaries`
- **Health Check**: Verify setup with `:checkhealth neocrush`

## Requirements

- Neovim >= 0.10
- [neocrush](https://github.com/taigrr/neocrush) binary in PATH
- [crush](https://github.com/charmbracelet/crush) CLI for terminal integration
- Go (for `:CrushInstallBinaries`/`:CrushUpdateBinaries` commands)

## Installation

### lazy.nvim

```lua
{
  'taigrr/neocrush.nvim',
  event = 'VeryLazy',
  opts = {},
  keys = {
    { '<leader>cc', '<cmd>CrushToggle<cr>', desc = 'Toggle Crush terminal' },
    { '<leader>cf', '<cmd>CrushFocus<cr>', desc = 'Focus Crush terminal' },
  },
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

    -- Add your keymaps
    vim.keymap.set('n', '<leader>cc', '<cmd>CrushToggle<cr>', { desc = 'Toggle Crush terminal' })
    vim.keymap.set('n', '<leader>cf', '<cmd>CrushFocus<cr>', { desc = 'Focus Crush terminal' })
  end,
}
```

## Configuration

```lua
require('neocrush').setup({
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
})
```

## Commands

| Command                 | Description                                       |
| ----------------------- | ------------------------------------------------- |
| `:CrushToggle`          | Toggle the Crush terminal window                  |
| `:CrushOpen`            | Open the Crush terminal                           |
| `:CrushClose`           | Close the Crush terminal (keeps buffer)           |
| `:CrushFocus`           | Focus the Crush terminal                          |
| `:CrushWidth <n>`       | Set terminal width to n columns                   |
| `:CrushFocusToggle`     | Toggle auto-focus behavior                        |
| `:CrushFocusOn`         | Enable auto-focus                                 |
| `:CrushFocusOff`        | Disable auto-focus                                |
| `:CrushInstallBinaries` | Install neocrush and crush binaries (requires Go) |
| `:CrushUpdateBinaries`  | Update neocrush and crush binaries (requires Go)  |

## Suggested Keymaps

The plugin does not set any keymaps by default.
Add these to your configuration:

```lua
vim.keymap.set('n', '<leader>cc', '<cmd>CrushToggle<cr>', { desc = 'Toggle Crush terminal' })
vim.keymap.set('n', '<leader>cf', '<cmd>CrushFocus<cr>', { desc = 'Focus Crush terminal' })
```

Or with lazy.nvim's `keys` option (see Installation above).

## API

```lua
local crush = require('neocrush')

-- Terminal management
crush.toggle()              -- Toggle terminal
crush.open()                -- Open terminal
crush.close()               -- Close terminal
crush.focus()               -- Focus terminal
crush.set_width(100)        -- Set terminal width

-- Auto-focus control
crush.toggle_auto_focus()   -- Toggle auto-focus
crush.enable_auto_focus()   -- Enable auto-focus
crush.disable_auto_focus()  -- Disable auto-focus
crush.is_auto_focus_enabled() -- Check if enabled

-- LSP management
crush.start_lsp()           -- Manually start LSP client
crush.get_client()          -- Get LSP client instance
```

## How It Works

1. **LSP Integration**: The plugin starts `neocrush` on `VimEnter` - no filetype restrictions, so it's ready for edits immediately
2. **Edit Handler**: Overrides `workspace/applyEdit` to detect neocrush edits and flash highlight them
3. **Cursor Sync**: Sends `crush/cursorMoved` notifications to keep the LSP server aware of cursor position
4. **Terminal**: Manages a persistent terminal buffer for running the Crush CLI

## Health Check

Run `:checkhealth neocrush` to verify your setup:

```
neocrush.nvim
- OK Neovim >= 0.10
- OK neocrush binary found
- OK crush CLI found
- OK Go found: go version go1.21.0 darwin/arm64
- OK neocrush LSP client running
```

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

### External File Modification Warning

When Crush edits a file that's open in Neovim, you may see a prompt like:

```
WARNING: The file has been changed since reading it!!!
Do you really want to write to it (y/n)?
```

Or when re-entering a buffer:

```
W11: Warning: File "filename" has changed since editing started
[O]K, (L)oad File:
```

This happens because Crush modifies files on disk, and Neovim detects the external change.
To minimize this, consider adding to your config:

```lua
vim.o.autoread = true
```

This tells Neovim to automatically reload files when they change on disk (if you have no unsaved changes).

## License

MIT - See [LICENSE](LICENSE) for details.
