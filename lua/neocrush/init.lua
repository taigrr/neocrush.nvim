---@brief [[
--- neocrush.nvim - Neovim plugin for neocrush LSP integration
---
--- Features:
---   - Flash highlights on AI edits (like yank highlight)
---   - Auto-focus edited files in leftmost code window
---   - Crush terminal management (:CrushToggle, :CrushFocus)
---   - Cursor position sync with neocrush server
---
--- Commands:
---   :CrushToggle            - Toggle Crush terminal (right split)
---   :CrushFocus             - Focus Crush terminal
---   :CrushOpen, :CrushClose - Explicit open/close
---   :CrushWidth <n>         - Set terminal width
---   :CrushFocusToggle/On/Off - Control auto-focus behavior
---   :CrushInstallBinaries   - Install neocrush and crush binaries
---   :CrushUpdateBinaries    - Update neocrush and crush binaries
---   :CrushLogs              - Show Crush logs in a new buffer
---   :CrushCancel            - Cancel current operation (sends <Esc><Esc>)
---   :CrushRestart           - Kill and restart Crush terminal
---   :CrushPaste [reg]       - Paste register or selection into terminal
---   :CrushCvmReleases       - Browse and install crush releases from GitHub
---   :CrushCvmLocal <path>   - Browse and install crush from local repo commits
---@brief ]]

local M = {}

-------------------------------------------------------------------------------
-- Type Definitions
-------------------------------------------------------------------------------

---@class neocrush.Config
---@field highlight_group string Highlight group for edit flash effect
---@field highlight_duration integer Flash duration in milliseconds
---@field auto_focus boolean Auto-focus edited files in leftmost window
---@field terminal_width integer Terminal width in columns
---@field terminal_cmd string Command to run in terminal (default: 'crush')
---@field keys? neocrush.Keys Optional keybindings to set up
---@field cvm? neocrush.CvmConfig Crush Version Manager configuration

---@class neocrush.LspStartOpts
---@field root_dir? string Override the root directory for the LSP server
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer) Additional on_attach callback

---@class neocrush.Keys
---@field toggle? string Keymap for :CrushToggle
---@field focus? string Keymap for :CrushFocus
---@field logs? string Keymap for :CrushLogs
---@field cancel? string Keymap for :CrushCancel
---@field restart? string Keymap for :CrushRestart
---@field paste? string Keymap for :CrushPaste
---@field cvm_releases? string Keymap for :CrushCvmReleases
---@field cvm_local? string Keymap for :CrushCvmLocal

-------------------------------------------------------------------------------
-- Default Configuration
-------------------------------------------------------------------------------

---@type neocrush.Config
local default_config = {
  highlight_group = 'IncSearch',
  highlight_duration = 900,
  auto_focus = true,
  terminal_width = 80,
  terminal_cmd = 'crush',
  cvm = {},
}

---@type neocrush.Config
local config = vim.deepcopy(default_config)

-------------------------------------------------------------------------------
-- Public API: Auto-focus
-------------------------------------------------------------------------------

--- Toggle auto-focus behavior for edited files.
function M.toggle_auto_focus()
  config.auto_focus = not config.auto_focus
  vim.notify('Crush auto-focus: ' .. (config.auto_focus and 'ON' or 'OFF'), vim.log.levels.INFO)
end

--- Enable auto-focus behavior for edited files.
function M.enable_auto_focus()
  config.auto_focus = true
  vim.notify('Crush auto-focus: ON', vim.log.levels.INFO)
end

--- Disable auto-focus behavior for edited files.
function M.disable_auto_focus()
  config.auto_focus = false
  vim.notify('Crush auto-focus: OFF', vim.log.levels.INFO)
end

--- Check if auto-focus is enabled.
---@return boolean
function M.is_auto_focus_enabled()
  return config.auto_focus
end

-------------------------------------------------------------------------------
-- Public API: Delegated to submodules
-------------------------------------------------------------------------------

-- Terminal management (delegated to neocrush.terminal)
function M.open()
  require('neocrush.terminal').open()
end
function M.close()
  require('neocrush.terminal').close()
end
function M.toggle()
  require('neocrush.terminal').toggle()
end
function M.focus()
  require('neocrush.terminal').focus()
end
function M.set_width(width)
  require('neocrush.terminal').set_width(width)
end
function M.logs()
  require('neocrush.terminal').logs()
end
function M.cancel()
  require('neocrush.terminal').cancel()
end
function M.restart()
  require('neocrush.terminal').restart()
end
function M.paste(register)
  require('neocrush.terminal').paste(register)
end
function M.paste_selection()
  require('neocrush.terminal').paste_selection()
end

-- LSP management (delegated to neocrush.lsp)
function M.start_lsp(opts)
  return require('neocrush.lsp').start_lsp(opts)
end
function M.get_client()
  return require('neocrush.lsp').get_client()
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

--- Initialize the neocrush plugin.
---@param opts? neocrush.Config Configuration options
function M.setup(opts)
  config = vim.tbl_deep_extend('force', default_config, opts or {})

  require('neocrush.terminal').setup(config)
  require('neocrush.lsp').setup(config)
  require('neocrush.commands').create(M)
  require('neocrush.cvm').setup(config.cvm)

  if opts and opts.keys then
    require('neocrush.commands').setup_keybindings(opts.keys)
  end
end

-------------------------------------------------------------------------------
-- Test Helpers (exposed for unit testing)
-------------------------------------------------------------------------------

M._is_file_window = function(...)
  return require('neocrush.terminal')._is_file_window(...)
end
M._find_edit_target_window = function(...)
  return require('neocrush.terminal')._find_edit_target_window(...)
end
M._flash_range = function(...)
  return require('neocrush.lsp')._flash_range(...)
end
M._is_handler_installed = function()
  return require('neocrush.lsp')._is_handler_installed()
end

return M
