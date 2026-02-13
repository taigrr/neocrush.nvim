---@brief [[
--- LSP client management for neocrush.nvim
--- Handles workspace/applyEdit override, flash highlights, cursor/selection sync
---@brief ]]

local M = {}

local terminal = require 'neocrush.terminal'

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

---@type neocrush.Config
local config

local ns = vim.api.nvim_create_namespace 'neocrush-highlight'
local original_handler = nil
local handler_installed = false

--- Track whether we've already warned about missing binary (only warn once)
local warned_missing_binary = false

-------------------------------------------------------------------------------
-- Flash Highlight
-------------------------------------------------------------------------------

--- Flash highlight a range in a buffer.
---@param bufnr integer Buffer handle
---@param start_line integer Start line (0-indexed)
---@param end_line integer End line (0-indexed, exclusive)
local function flash_range(bufnr, start_line, end_line)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for line = start_line, end_line - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      end_row = line,
      end_col = 0,
      hl_group = config.highlight_group,
      hl_eol = true,
      line_hl_group = config.highlight_group,
    })
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end, config.highlight_duration)
end

--- Ensure a buffer is visible in some window (for highlighting).
---@param bufnr integer Buffer handle
---@return integer|nil win Window handle where buffer is displayed, or nil
local function ensure_buffer_visible(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    return wins[1]
  end

  local target_win = terminal.find_edit_target_window()
  if target_win then
    local ok = pcall(vim.api.nvim_win_set_buf, target_win, bufnr)
    if ok then
      return target_win
    end
  end

  local width = math.floor(vim.o.columns / 2)
  vim.cmd 'topleft vnew'
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(new_win, width)
  vim.api.nvim_win_set_buf(new_win, bufnr)
  return new_win
end

-------------------------------------------------------------------------------
-- Workspace Edit Handler
-------------------------------------------------------------------------------

--- The workspace/applyEdit handler for neocrush.
---@param err any
---@param result any
---@param ctx any
---@param conf any
local function apply_edit_handler(err, result, ctx, conf)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local is_crush = client ~= nil and client.name == 'neocrush'

  if client and is_crush and result and result.edit then
    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_win_get_buf(original_win)

    local swapfile = vim.o.swapfile
    vim.o.swapfile = false

    local ok, applied = pcall(vim.lsp.util.apply_workspace_edit, result.edit, client.offset_encoding or 'utf-16')

    vim.o.swapfile = swapfile

    if not ok then
      vim.notify('apply_workspace_edit failed: ' .. tostring(applied), vim.log.levels.ERROR)
      return { applied = false }
    end

    local edits_by_uri = {}

    if result.edit.changes then
      for uri, text_edits in pairs(result.edit.changes) do
        edits_by_uri[uri] = text_edits
      end
    elseif result.edit.documentChanges then
      for _, change in ipairs(result.edit.documentChanges) do
        if change.textDocument and change.edits then
          local uri = change.textDocument.uri
          edits_by_uri[uri] = change.edits
        end
      end
    end

    for uri, edits in pairs(edits_by_uri) do
      local bufnr = vim.uri_to_bufnr(uri)

      if not vim.api.nvim_buf_is_loaded(bufnr) then
        pcall(vim.fn.bufload, bufnr)
      end

      local win = ensure_buffer_visible(bufnr)

      for _, edit in ipairs(edits) do
        local start_line = edit.range.start.line
        local end_line = edit.range['end'].line
        local new_lines = vim.split(edit.newText or '', '\n', { plain = true })
        local actual_end = start_line + #new_lines

        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_cursor(win, { start_line + 1, 0 })
          vim.api.nvim_win_call(win, function()
            vim.cmd 'normal! zz'
          end)
        end

        flash_range(bufnr, start_line, math.max(actual_end, end_line + 1))
      end
    end

    if vim.api.nvim_win_is_valid(original_win) then
      local current_buf_in_original_win = vim.api.nvim_win_get_buf(original_win)
      if current_buf_in_original_win == original_buf then
        vim.api.nvim_set_current_win(original_win)
      end
    end

    return { applied = applied }
  end

  if original_handler then
    return original_handler(err, result, ctx, conf)
  end
  return vim.lsp.util.apply_workspace_edit(result.edit, 'utf-16')
end

--- Install the workspace/applyEdit handler override.
local function install_apply_edit_handler()
  if handler_installed then
    return
  end

  original_handler = vim.lsp.handlers['workspace/applyEdit']
  vim.lsp.handlers['workspace/applyEdit'] = apply_edit_handler
  handler_installed = true
end

-------------------------------------------------------------------------------
-- Cursor/Selection Sync
-------------------------------------------------------------------------------

--- Set up selection change notifications for a buffer.
---@param client vim.lsp.Client LSP client instance
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
---@param client vim.lsp.Client LSP client instance
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
      vim.notify('neocrush binary not found. Install with :CrushInstallBinaries (requires Go)', vim.log.levels.WARN)
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
      ['workspace/applyEdit'] = apply_edit_handler,
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
---@return vim.lsp.Client|nil client The client or nil if not running
function M.get_client()
  local clients = vim.lsp.get_clients { name = 'neocrush' }
  return clients[1]
end

--- Install handler and set up autocmds.
---@param cfg neocrush.Config
function M.setup(cfg)
  config = cfg

  install_apply_edit_handler()

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

M._flash_range = flash_range
M._is_handler_installed = function()
  return handler_installed
end

return M
