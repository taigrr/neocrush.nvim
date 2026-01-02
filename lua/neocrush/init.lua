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

---@class neocrush.LspStartOpts
---@field root_dir? string Override the root directory for the LSP server
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer) Additional on_attach callback

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
-- Constants
-------------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace 'neocrush-highlight'

-------------------------------------------------------------------------------
-- Terminal State
-------------------------------------------------------------------------------

---@type integer|nil Window handle for the Crush terminal
local crush_win = nil

---@type integer|nil Buffer handle for the Crush terminal
local crush_buf = nil

-------------------------------------------------------------------------------
-- Internal Helpers
-------------------------------------------------------------------------------

--- Check if a window is the Crush terminal window.
---@param win integer Window handle
---@return boolean
local function is_crush_window(win)
  return crush_win ~= nil and win == crush_win and vim.api.nvim_win_is_valid(crush_win)
end

--- Check if a window is a normal file window (not special UI).
---@param win integer Window handle
---@return boolean true if this is a normal file or scratch buffer window
local function is_file_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local buftype = vim.bo[buf].buftype

  -- Only accept normal file buffers (buftype='') or scratch buffers (buftype='acwrite')
  return buftype == '' or buftype == 'acwrite'
end

--- Find the best window to open an edited file in.
--- Returns the leftmost non-special, non-crush window.
---@return integer|nil win Window handle or nil if none found
local function find_edit_target_window()
  local all_wins = vim.api.nvim_tabpage_list_wins(0)
  local candidates = {}

  for _, win in ipairs(all_wins) do
    if not is_crush_window(win) and is_file_window(win) then
      local pos = vim.api.nvim_win_get_position(win)
      table.insert(candidates, { win = win, col = pos[2] })
    end
  end

  if #candidates == 0 then
    return nil
  end

  -- Sort by column (leftmost first)
  table.sort(candidates, function(a, b)
    return a.col < b.col
  end)

  return candidates[1].win
end

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
  -- Make sure buffer is valid and loaded
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  -- Check if buffer is already visible in some window
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    return wins[1]
  end

  -- Find the leftmost non-special window
  local all_wins = vim.api.nvim_tabpage_list_wins(0)
  local candidates = {}

  for _, win in ipairs(all_wins) do
    if not is_crush_window(win) and is_file_window(win) then
      local pos = vim.api.nvim_win_get_position(win)
      table.insert(candidates, { win = win, col = pos[2] })
    end
  end

  if #candidates > 0 then
    -- Sort by column (leftmost first)
    table.sort(candidates, function(a, b)
      return a.col < b.col
    end)
    local target_win = candidates[1].win
    local ok = pcall(vim.api.nvim_win_set_buf, target_win, bufnr)
    if ok then
      return target_win
    end
  end

  -- No suitable window found, create a new window with the target buffer
  -- Use enew + set_buf to avoid issues when current window is terminal/nofile
  local width = math.floor(vim.o.columns / 2)
  vim.cmd 'topleft vnew'
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(new_win, width)
  vim.api.nvim_win_set_buf(new_win, bufnr)
  return new_win
end

-------------------------------------------------------------------------------
-- LSP Handler Override
-------------------------------------------------------------------------------

local original_handler = nil
local handler_installed = false

--- Install the workspace/applyEdit handler override.
--- This intercepts edits from neocrush to add flash highlighting
--- and suppress the default "Workspace edit" notification.
local function install_apply_edit_handler()
  if handler_installed then
    return
  end

  original_handler = vim.lsp.handlers['workspace/applyEdit']

  vim.lsp.handlers['workspace/applyEdit'] = function(err, result, ctx, conf)
    local client = vim.lsp.get_client_by_id(ctx.client_id) or {}
    local is_crush = client and client.name == 'neocrush'

    if is_crush and result and result.edit then
      -- Save current window/buffer state before edit
      local original_win = vim.api.nvim_get_current_win()
      local original_buf = vim.api.nvim_win_get_buf(original_win)

      -- Suppress swap file prompts (E325) during the edit
      local swapfile = vim.o.swapfile
      vim.o.swapfile = false

      -- Apply edit silently (without the "Workspace edit" notification)
      local offset_encoding = client.offset_encoding or 'utf-16'
      local ok, applied = pcall(vim.lsp.util.apply_workspace_edit, result.edit, offset_encoding)

      vim.o.swapfile = swapfile

      if not ok then
        vim.notify('apply_workspace_edit failed: ' .. tostring(applied), vim.log.levels.ERROR)
        return { applied = false }
      end

      -- Collect edits from either changes or documentChanges format
      local edits_by_uri = {}

      if result.edit.changes then
        -- Simple format: { [uri]: TextEdit[] }
        for uri, text_edits in pairs(result.edit.changes) do
          edits_by_uri[uri] = text_edits
        end
      elseif result.edit.documentChanges then
        -- Versioned format: TextDocumentEdit[] or (TextDocumentEdit | CreateFile | RenameFile | DeleteFile)[]
        for _, change in ipairs(result.edit.documentChanges) do
          if change.textDocument and change.edits then
            -- TextDocumentEdit
            local uri = change.textDocument.uri
            edits_by_uri[uri] = change.edits
          end
        end
      end

      -- Flash highlight the changes
      for uri, edits in pairs(edits_by_uri) do
        local bufnr = vim.uri_to_bufnr(uri)

        -- Load buffer if needed (suppress E325 prompts)
        if not vim.api.nvim_buf_is_loaded(bufnr) then
          pcall(vim.fn.bufload, bufnr)
        end

        -- Ensure buffer is visible (this may create a split)
        ensure_buffer_visible(bufnr)

        for _, edit in ipairs(edits) do
          local start_line = edit.range.start.line
          local end_line = edit.range['end'].line
          local new_lines = vim.split(edit.newText or '', '\n', { plain = true })
          local actual_end = start_line + #new_lines

          flash_range(bufnr, start_line, math.max(actual_end, end_line + 1))
        end
      end

      -- Restore focus if original window's buffer wasn't replaced
      -- (i.e., the edit went to a different window)
      if vim.api.nvim_win_is_valid(original_win) then
        local current_buf_in_original_win = vim.api.nvim_win_get_buf(original_win)
        if current_buf_in_original_win == original_buf then
          -- Original window still has its original buffer, restore focus
          vim.api.nvim_set_current_win(original_win)
        end
        -- If buffer was replaced, focus is already on the edit (do nothing)
      end

      return { applied = applied }
    end

    -- For non-neocrush clients, use the original handler
    return original_handler(err, result, ctx, conf)
  end

  handler_installed = true
end

-------------------------------------------------------------------------------
-- LSP Cursor/Selection Sync
-------------------------------------------------------------------------------

--- Get the text from the last visual selection.
---@return string|nil text Selected text or nil if no valid selection
local function get_visual_selection_text()
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"

  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  return table.concat(lines, '\n')
end

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

      -- Leaving visual mode (v, V, or ctrl-v)
      if (old_mode == 'v' or old_mode == 'V' or old_mode == '\22') and new_mode == 'n' then
        vim.schedule(function()
          local text = get_visual_selection_text()
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

  -- Clean up timer when buffer is deleted
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
-- Public API: Terminal Management
-------------------------------------------------------------------------------

--- Open the Crush terminal in a right split.
--- If already open, focuses the existing terminal.
function M.open()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_set_current_win(crush_win)
    vim.cmd 'startinsert'
    return
  end

  vim.cmd 'botright vsplit'
  crush_win = vim.api.nvim_get_current_win()
  vim.w[crush_win].is_crush_terminal = true
  vim.api.nvim_win_set_width(crush_win, config.terminal_width)

  if crush_buf and vim.api.nvim_buf_is_valid(crush_buf) then
    vim.api.nvim_win_set_buf(crush_win, crush_buf)
  else
    vim.cmd('terminal ' .. config.terminal_cmd)
    crush_buf = vim.api.nvim_get_current_buf()
    vim.bo[crush_buf].buflisted = false
  end

  vim.cmd 'startinsert'
end

--- Close the Crush terminal window (buffer remains alive).
function M.close()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_hide(crush_win)
    crush_win = nil
  end
end

--- Toggle the Crush terminal window.
function M.toggle()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    M.close()
  else
    M.open()
  end
end

--- Focus the Crush terminal window.
--- Opens the terminal if not already open.
function M.focus()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_set_current_win(crush_win)
    vim.cmd 'startinsert'
  else
    M.open()
  end
end

--- Set the terminal width.
---@param width integer Width in columns
function M.set_width(width)
  config.terminal_width = width
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_set_width(crush_win, config.terminal_width)
  end
end

-------------------------------------------------------------------------------
-- Public API: LSP Client Management
-------------------------------------------------------------------------------

--- Track whether we've already warned about missing binary (only warn once)
local warned_missing_binary = false

--- Start the neocrush LSP client.
--- Will not start if the neocrush binary is not installed.
---@param opts? neocrush.LspStartOpts Options for starting the LSP
---@return integer|nil client_id LSP client ID or nil if failed/binary missing
function M.start_lsp(opts)
  -- Check if neocrush binary exists
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

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

--- Create user commands for the plugin.
local function create_commands()
  vim.api.nvim_create_user_command('CrushOpen', function()
    M.open()
  end, { desc = 'Open Crush terminal in right split' })

  vim.api.nvim_create_user_command('CrushClose', function()
    M.close()
  end, { desc = 'Close Crush terminal window' })

  vim.api.nvim_create_user_command('CrushToggle', function()
    M.toggle()
  end, { desc = 'Toggle Crush terminal window' })

  vim.api.nvim_create_user_command('CrushFocus', function()
    M.focus()
  end, { desc = 'Focus Crush terminal window' })

  vim.api.nvim_create_user_command('CrushWidth', function(opts)
    local width = tonumber(opts.args)
    if width then
      M.set_width(width)
    else
      vim.notify('Usage: CrushWidth <number>', vim.log.levels.ERROR)
    end
  end, { nargs = 1, desc = 'Set Crush terminal width' })

  vim.api.nvim_create_user_command('CrushFocusToggle', function()
    M.toggle_auto_focus()
  end, { desc = 'Toggle Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushFocusOn', function()
    M.enable_auto_focus()
  end, { desc = 'Enable Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushFocusOff', function()
    M.disable_auto_focus()
  end, { desc = 'Disable Crush edit auto-focus' })

  vim.api.nvim_create_user_command('CrushInstallBinaries', function()
    require('neocrush.install').install_all()
  end, { desc = 'Install neocrush and crush binaries' })

  vim.api.nvim_create_user_command('CrushUpdateBinaries', function()
    require('neocrush.install').update_all()
  end, { desc = 'Update neocrush and crush binaries' })
end

--- Set up LSP attach autocmds for cursor/selection sync.
local function setup_lsp_attach()
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
end

--- Set up early LSP start on VimEnter and BufEnter.
local function setup_early_start()
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

--- Initialize the neocrush plugin.
---@param opts? neocrush.Config Configuration options
function M.setup(opts)
  config = vim.tbl_deep_extend('force', default_config, opts or {})

  install_apply_edit_handler()
  create_commands()
  setup_lsp_attach()
  setup_early_start()
end

-------------------------------------------------------------------------------
-- Test Helpers (exposed for unit testing)
-------------------------------------------------------------------------------

M._is_file_window = is_file_window
M._find_edit_target_window = find_edit_target_window
M._flash_range = flash_range

return M
