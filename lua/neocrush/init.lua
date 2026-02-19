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
---   :CrushLogs              - Show Crush logs in a new buffer
---   :CrushCancel            - Cancel current operation (sends <Esc><Esc>)
---   :CrushRestart           - Kill and restart Crush terminal
---   :CrushPaste [reg]       - Paste register or selection into terminal
---   :CrushCvmReleases       - Browse and install crush releases from GitHub
---   :CrushCvmLocal <path>   - Browse and install crush from local repo commits
---@brief ]]

local M = {}

-- Register binaries with glaze.nvim if available
local _glaze_ok, _glaze = pcall(require, 'glaze')
if _glaze_ok then
  _glaze.register('neocrush', 'github.com/taigrr/neocrush/cmd/neocrush', {
    plugin = 'neocrush.nvim',
  })
  _glaze.register('crush', 'github.com/charmbracelet/crush', {
    plugin = 'neocrush.nvim',
  })
  _glaze.register('glow', 'github.com/charmbracelet/glow', {
    plugin = 'neocrush.nvim',
  })
end

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
---@field on_attach? fun(client: table, bufnr: integer) Additional on_attach callback

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

--- Open the Crush terminal.
function M.open()
  require('neocrush.terminal').open()
end

--- Close the Crush terminal.
function M.close()
  require('neocrush.terminal').close()
end

--- Toggle the Crush terminal.
function M.toggle()
  require('neocrush.terminal').toggle()
end

--- Focus the Crush terminal.
function M.focus()
  require('neocrush.terminal').focus()
end

--- Set the terminal width.
---@param width integer Width in columns
function M.set_width(width)
  require('neocrush.terminal').set_width(width)
end

--- Show Crush logs in a buffer.
function M.logs()
  require('neocrush.terminal').logs()
end

--- Cancel current Crush operation.
function M.cancel()
  require('neocrush.terminal').cancel()
end

--- Restart the Crush terminal.
function M.restart()
  require('neocrush.terminal').restart()
end

--- Paste register contents into the Crush terminal.
---@param register? string Register to paste from (default: '+')
function M.paste(register)
  require('neocrush.terminal').paste(register)
end

--- Paste the current visual selection into the Crush terminal.
function M.paste_selection()
  require('neocrush.terminal').paste_selection()
end

--- Start the neocrush LSP client.
---@param opts? neocrush.LspStartOpts
---@return integer|nil client_id
function M.start_lsp(opts)
  return require('neocrush.lsp').start_lsp(opts)
end

--- Get the neocrush LSP client instance.
---@return table|nil client
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

---@param win integer
---@return boolean
M._is_file_window = function(win)
  return require('neocrush.terminal')._is_file_window(win)
end

---@return integer|nil
M._find_edit_target_window = function()
  return require('neocrush.terminal')._find_edit_target_window()
end

---@param bufnr integer
---@param start_line integer
---@param end_line integer
M._flash_range = function(bufnr, start_line, end_line)
  return require('neocrush.lsp')._flash_range(bufnr, start_line, end_line)
end

---@return boolean
M._is_handler_installed = function()
  return require('neocrush.lsp')._is_handler_installed()
end

return M
