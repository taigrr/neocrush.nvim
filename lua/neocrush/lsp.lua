---@brief [[
--- LSP client management for neocrush.nvim
--- Handles client lifecycle, cursor/selection sync autocmds
---@brief ]]

local M = {}

local terminal = require 'neocrush.terminal'
local highlight = require 'neocrush.highlight'

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

---@type boolean
local warned_missing_binary = false

-------------------------------------------------------------------------------
-- Cursor/Selection Sync
-------------------------------------------------------------------------------

--- Set up selection change notifications for a buffer.
---@param client table LSP client instance
---@param bufnr integer Buffer handle
local function setup_selection_sync(client, bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype == 'terminal' or buftype == 'nofile' or buftype == 'prompt' then
    return
  end

  local group = vim.api.nvim_create_augroup('NeocrushSelectionSync' .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd('ModeChanged', {
    buffer = bufnr,
    group = group,
    callback = function(event)
      if vim.bo[bufnr].buftype ~= '' then
        return
      end

      local old_mode = event.match:sub(1, 1)
      local new_mode = event.match:sub(-1)

      if (old_mode == 'v' or old_mode == 'V' or old_mode == '\22') and new_mode == 'n' then
        vim.schedule(function()
          local text = terminal.get_visual_selection_text()
          local uri = vim.uri_from_bufnr(bufnr)

          if uri and uri ~= '' and uri ~= 'file://' then
            client:notify('crush/selectionChanged', {
              textDocument = { uri = uri },
              text = text or '',
              selections = {},
            })
          end
        end)
      end
    end,
  })
end

--- Set up cursor position notifications for a buffer.
---@param client table LSP client instance
---@param bufnr integer Buffer handle
local function setup_cursor_sync(client, bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype == 'terminal' or buftype == 'nofile' or buftype == 'prompt' then
    return
  end

  local group = vim.api.nvim_create_augroup('NeocrushCursorSync' .. bufnr, { clear = true })
  local cursor_timer = nil

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = bufnr,
    group = group,
    callback = function()
      if vim.bo[bufnr].buftype ~= '' then
        return
      end

      if cursor_timer then
        cursor_timer:stop()
      end

      cursor_timer = vim.defer_fn(function()
        local pos = vim.api.nvim_win_get_cursor(0)
        local uri = vim.uri_from_bufnr(bufnr)

        if uri and uri ~= '' and uri ~= 'file://' then
          client:notify('crush/cursorMoved', {
            textDocument = { uri = uri },
            position = { line = pos[1] - 1, character = pos[2] },
          })
        end
      end, 50)
    end,
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = bufnr,
    group = group,
    callback = function()
      if cursor_timer then
        cursor_timer:stop()
        cursor_timer = nil
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Start the neocrush LSP client.
---@param opts? neocrush.LspStartOpts Options for starting the LSP
---@return integer|nil client_id LSP client ID or nil if failed/binary missing
function M.start_lsp(opts)
  if vim.fn.executable 'neocrush' ~= 1 then
    if not warned_missing_binary then
      warned_missing_binary = true
      vim.notify('neocrush binary not found. Install with :GlazeInstall neocrush', vim.log.levels.WARN)
    end
    return nil
  end

  opts = opts or {}
  local cwd = vim.fn.getcwd()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  local root_dir = opts.root_dir
    or ((git_root and git_root ~= '' and vim.fn.isdirectory(git_root) == 1) and git_root or cwd)

  return vim.lsp.start {
    name = 'neocrush',
    cmd = { 'neocrush' },
    root_dir = root_dir,
    handlers = {
      ['workspace/applyEdit'] = highlight.apply_edit_handler,
      ['crush/showLocations'] = require('neocrush.locations').handler,
    },
    on_attach = function(client, bufnr)
      setup_cursor_sync(client, bufnr)
      setup_selection_sync(client, bufnr)
      if opts.on_attach then
        opts.on_attach(client, bufnr)
      end
    end,
  }
end

--- Get the neocrush LSP client instance.
---@return table|nil client The client or nil if not running
function M.get_client()
  local clients = vim.lsp.get_clients { name = 'neocrush' }
  return clients[1]
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

--- Install handler and set up autocmds.
---@param cfg neocrush.Config
function M.setup(cfg)
  highlight.setup(cfg)

  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('NeocrushLspAttach', { clear = true }),
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client.name == 'neocrush' then
        setup_cursor_sync(client, event.buf)
        setup_selection_sync(client, event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = vim.api.nvim_create_augroup('NeocrushLspBufEnter', { clear = true }),
    callback = function(event)
      local clients = vim.lsp.get_clients { name = 'neocrush', bufnr = event.buf }
      if #clients > 0 then
        setup_cursor_sync(clients[1], event.buf)
        setup_selection_sync(clients[1], event.buf)
      end
    end,
  })

  if vim.v.vim_did_enter == 1 then
    M.start_lsp()
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      group = vim.api.nvim_create_augroup('NeocrushLspEarlyStart', { clear = true }),
      callback = function()
        M.start_lsp()
      end,
    })
  end

  vim.api.nvim_create_autocmd('BufEnter', {
    group = vim.api.nvim_create_augroup('NeocrushLspBufStart', { clear = true }),
    callback = function()
      if vim.bo.buftype == '' and vim.bo.filetype ~= '' then
        local clients = vim.lsp.get_clients { name = 'neocrush', bufnr = 0 }
        if #clients == 0 then
          M.start_lsp()
        end
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- Test Helpers
-------------------------------------------------------------------------------

M._flash_range = function(bufnr, start_line, end_line)
  highlight.flash_range(bufnr, start_line, end_line)
end

M._is_handler_installed = function()
  return highlight.is_installed()
end

return M
