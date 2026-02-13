---@brief [[
--- Flash highlight and workspace edit handler for neocrush.nvim
--- Provides edit flash effect and the workspace/applyEdit override
---@brief ]]

local M = {}

local terminal = require 'neocrush.terminal'

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

---@type neocrush.Config|nil
local config

local ns = vim.api.nvim_create_namespace 'neocrush-highlight'
local original_handler = nil
local handler_installed = false

-------------------------------------------------------------------------------
-- Flash Highlight
-------------------------------------------------------------------------------

--- Flash highlight a range in a buffer.
---@param bufnr integer Buffer handle
---@param start_line integer Start line (0-indexed)
---@param end_line integer End line (0-indexed, exclusive)
function M.flash_range(bufnr, start_line, end_line)
  if not config then
    return
  end

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
---@param err any LSP error (if any)
---@param result any LSP result containing the edit
---@param ctx any LSP handler context
---@param conf any LSP handler configuration
---@return table|nil response Applied status or nil on error
function M.apply_edit_handler(err, result, ctx, conf)
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

        M.flash_range(bufnr, start_line, math.max(actual_end, end_line + 1))
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
function M.install()
  if handler_installed then
    return
  end

  original_handler = vim.lsp.handlers['workspace/applyEdit']
  vim.lsp.handlers['workspace/applyEdit'] = M.apply_edit_handler
  handler_installed = true
end

--- Check if the handler has been installed.
---@return boolean
function M.is_installed()
  return handler_installed
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

---@param cfg neocrush.Config
function M.setup(cfg)
  config = cfg
  M.install()
end

return M
