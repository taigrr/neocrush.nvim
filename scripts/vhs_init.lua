-- Minimal init.lua for VHS recordings
-- Loads only this plugin with no colorscheme or other plugins
-- Usage: nvim -u /path/to/vhs_init.lua --cmd "set rtp+=/path/to/neocrush.nvim"

-- Get the plugin directory from runtimepath (set via --cmd)
-- This allows CI to set the path dynamically

-- Basic settings for clean recording
vim.o.number = true
vim.o.relativenumber = false
vim.o.signcolumn = 'yes'
vim.o.termguicolors = true
vim.o.showmode = false
vim.o.ruler = false
vim.o.laststatus = 2
vim.o.cmdheight = 1
vim.o.updatetime = 100
vim.o.timeoutlen = 300
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.autoread = true

-- Disable intro message and other noise
vim.opt.shortmess:append 'I'
vim.opt.shortmess:append 'c'

-- Simple statusline
vim.o.statusline = ' %f %m%=%l:%c '

-- Set leader key
vim.g.mapleader = ' '

-- Terminal mode keymaps: Ctrl+\ to exit terminal mode, Ctrl+W for window nav
vim.keymap.set('t', '<C-\\>', '<C-\\><C-N>', { desc = 'Exit terminal mode' })
vim.keymap.set('t', '<C-W>', '<C-\\><C-N><C-W>', { desc = 'Window navigation from terminal' })

-- Normal mode: Ctrl+W for window navigation (default behavior, but explicit)
vim.keymap.set('n', '<C-W>', '<C-W>', { desc = 'Window navigation' })

-- Source the plugin file (--clean doesn't auto-load plugin/ dir)
vim.cmd 'runtime! plugin/neocrush.lua'

-- Load the plugin
-- Note: neocrush LSP starts on VimEnter and connects to crush via MCP
require('neocrush').setup {
  highlight_duration = 1500,
  terminal_width = 60,
  keys = {
    toggle = '<leader>cc',
    focus = '<leader>cf',
    paste = '<leader>cp',
  },
}
