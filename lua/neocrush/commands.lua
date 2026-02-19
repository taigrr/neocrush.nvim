---@brief [[
--- User commands and keybindings for neocrush.nvim
---@brief ]]

local M = {}

-------------------------------------------------------------------------------
-- Commands
-------------------------------------------------------------------------------

--- Create user commands for the plugin.
---@param neocrush table The main neocrush module (for public API access)
function M.create(neocrush)
  local terminal = require 'neocrush.terminal'

  vim.api.nvim_create_user_command('CrushOpen', function()
    terminal.open()
  end, { desc = 'Open Crush terminal in right split' })

  vim.api.nvim_create_user_command('CrushClose', function()
    terminal.close()
  end, { desc = 'Close Crush terminal window' })

  vim.api.nvim_create_user_command('CrushToggle', function()
    terminal.toggle()
  end, { desc = 'Toggle Crush terminal window' })

  vim.api.nvim_create_user_command('CrushFocus', function()
    terminal.focus()
  end, { desc = 'Focus Crush terminal window' })

  vim.api.nvim_create_user_command('CrushWidth', function(opts)
    local width = tonumber(opts.args)
    if width then
      terminal.set_width(width)
    else
      vim.notify('Usage: CrushWidth <number>', vim.log.levels.ERROR)
    end
  end, { nargs = 1, desc = 'Set Crush terminal width' })

  vim.api.nvim_create_user_command('CrushFocusToggle', function()
    neocrush.toggle_auto_focus()
  end, { desc = 'Toggle Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushFocusOn', function()
    neocrush.enable_auto_focus()
  end, { desc = 'Enable Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushFocusOff', function()
    neocrush.disable_auto_focus()
  end, { desc = 'Disable Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushLogs', function()
    terminal.logs()
  end, { desc = 'Show Crush logs in a new buffer' })

  vim.api.nvim_create_user_command('CrushCancel', function()
    terminal.cancel()
  end, { desc = 'Cancel current Crush operation (sends <Esc><Esc>)' })

  vim.api.nvim_create_user_command('CrushRestart', function()
    terminal.restart()
  end, { desc = 'Kill and restart the Crush terminal' })

  vim.api.nvim_create_user_command('CrushPaste', function(opts)
    if opts.range > 0 then
      terminal.paste_selection()
    elseif opts.args ~= '' then
      terminal.paste(opts.args)
    else
      terminal.paste()
    end
  end, { nargs = '?', range = true, desc = 'Paste register or selection into Crush terminal' })

  vim.api.nvim_create_user_command('CrushCvmReleases', function()
    require('neocrush.cvm').pick_releases()
  end, { desc = 'Browse and install crush releases from GitHub' })

  vim.api.nvim_create_user_command('CrushCvmLocal', function(opts)
    require('neocrush.cvm').pick_local(opts.args)
  end, { nargs = '?', desc = 'Browse and install crush from local repo commits' })
end

-------------------------------------------------------------------------------
-- Keybindings
-------------------------------------------------------------------------------

--- Set up user-defined keybindings.
---@param keys neocrush.Keys Keybinding configuration
function M.setup_keybindings(keys)
  if keys.toggle then
    vim.keymap.set('n', keys.toggle, '<cmd>CrushToggle<cr>', { desc = 'Toggle Crush terminal' })
  end
  if keys.focus then
    vim.keymap.set('n', keys.focus, '<cmd>CrushFocus<cr>', { desc = 'Focus Crush terminal' })
  end
  if keys.logs then
    vim.keymap.set('n', keys.logs, '<cmd>CrushLogs<cr>', { desc = 'Show Crush logs' })
  end
  if keys.cancel then
    vim.keymap.set('n', keys.cancel, '<cmd>CrushCancel<cr>', { desc = 'Cancel Crush operation' })
  end
  if keys.restart then
    vim.keymap.set('n', keys.restart, '<cmd>CrushRestart<cr>', { desc = 'Restart Crush terminal' })
  end
  if keys.paste then
    vim.keymap.set('n', keys.paste, '<cmd>CrushPaste<cr>', { desc = 'Paste clipboard into Crush' })
    vim.keymap.set('v', keys.paste, ':CrushPaste<cr>', { desc = 'Paste selection into Crush' })
  end
  if keys.cvm_releases then
    vim.keymap.set('n', keys.cvm_releases, '<cmd>CrushCvmReleases<cr>', { desc = 'Browse crush releases' })
  end
  if keys.cvm_local then
    vim.keymap.set('n', keys.cvm_local, '<cmd>CrushCvmLocal<cr>', { desc = 'Browse local crush commits' })
  end
end

return M
