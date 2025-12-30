-- crush-lsp.nvim
-- Neovim plugin for crush-lsp integration (testing edit highlight!)
--
-- Features:
--   - Flash highlights on AI edits (like yank highlight)
--   - Auto-focus edited files in leftmost code window
--   - Crush terminal management (:CrushToggle, <leader>cc)
--   - Cursor position sync with crush-lsp server
--
-- Commands:
--   :CrushToggle / <leader>cc  - Toggle Crush terminal (right split)
--   :CrushFocus / <leader>cf   - Focus Crush terminal
--   :CrushOpen, :CrushClose    - Explicit open/close
--   :CrushWidth <n>            - Set terminal width
--   :CrushFocusToggle/On/Off   - Control auto-focus behavior

local M = {}

-------------------------------------------------------------------------------
-- Default Configuration
-------------------------------------------------------------------------------

---@class CrushLspConfig
---@field highlight_group string Highlight group for edit flash
---@field highlight_duration number Flash duration in milliseconds
---@field auto_focus boolean Auto-focus edited files
---@field terminal_width number Terminal width in columns
---@field terminal_cmd string Command to run in terminal
---@field keymaps boolean|table Enable default keymaps (true/false or table of overrides)

---@type CrushLspConfig
local default_config = {
  highlight_group = 'IncSearch',
  highlight_duration = 900,
  auto_focus = true,
  terminal_width = 80,
  terminal_cmd = 'crush',
  keymaps = true,
}

---@type CrushLspConfig
local config = {}

-------------------------------------------------------------------------------
-- Highlight Namespace
-------------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace 'crush-lsp-highlight'

-------------------------------------------------------------------------------
-- Terminal State
-------------------------------------------------------------------------------

local crush_win = nil
local crush_buf = nil

-------------------------------------------------------------------------------
-- Internal Helpers
-------------------------------------------------------------------------------

-- Check if a window is the Crush terminal window
local function is_crush_window(win)
  return crush_win and win == crush_win and vim.api.nvim_win_is_valid(crush_win)
end

-- Check if a window is a special buffer (filetree, terminal, etc.)
local function is_special_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return true
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype

  -- Special buftypes
  if buftype == 'terminal' or buftype == 'nofile' or buftype == 'prompt' or buftype == 'quickfix' then
    return true
  end

  -- Common filetree/special filetypes
  local special_filetypes = {
    'neo-tree',
    'NvimTree',
    'nvim-tree',
    'nerdtree',
    'CHADTree',
    'fern',
    'dirvish',
    'oil',
    'fugitive',
    'gitcommit',
    'Trouble',
    'qf',
    'help',
    'man',
    'lspinfo',
    'lazy',
    'mason',
    'TelescopePrompt',
  }

  for _, ft in ipairs(special_filetypes) do
    if filetype == ft then
      return true
    end
  end

  return false
end

-- Find the best window to open an edited file in
-- Returns the leftmost non-special, non-crush window, or nil if none found
local function find_edit_target_window()
  local all_wins = vim.api.nvim_tabpage_list_wins(0)
  local candidates = {}

  for _, win in ipairs(all_wins) do
    if not is_crush_window(win) and not is_special_window(win) then
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

-- Flash a range in the current buffer
local function flash_range(bufnr, start_line, end_line)
  -- Clear any existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Add highlight to the changed lines
  for line = start_line, end_line - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns, config.highlight_group, line, 0, -1)
  end

  -- Clear after duration
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end, config.highlight_duration)
end

-- Focus a buffer and jump to a line
local function focus_edit(bufnr, line)
  if not config.auto_focus then
    return
  end

  -- Find a window already displaying this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    -- Buffer already visible, just focus that window
    vim.api.nvim_set_current_win(wins[1])
  else
    -- Buffer not visible - find the best target window
    local target_win = find_edit_target_window()

    if target_win then
      -- Use the found window
      vim.api.nvim_set_current_win(target_win)
      vim.api.nvim_set_current_buf(bufnr)
    else
      -- No suitable window found, create a new split to the left of crush
      if crush_win and vim.api.nvim_win_is_valid(crush_win) then
        vim.api.nvim_set_current_win(crush_win)
        vim.cmd 'leftabove vsplit'
      else
        vim.cmd 'vsplit'
      end
      vim.api.nvim_set_current_buf(bufnr)
    end
  end

  -- Jump to the edited line
  vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
  vim.cmd 'normal! zz'
end

-------------------------------------------------------------------------------
-- LSP Handler Override
-------------------------------------------------------------------------------

local original_handler = nil
local handler_installed = false

local function install_apply_edit_handler()
  if handler_installed then
    return
  end

  original_handler = vim.lsp.handlers['workspace/applyEdit']

  vim.lsp.handlers['workspace/applyEdit'] = function(err, result, ctx, conf)
    -- Check if this is from crush-lsp
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local is_crush = client and client.name == 'crush-lsp'

    -- Call original handler first
    local response = original_handler(err, result, ctx, conf)

    -- If from crush-lsp, highlight the changes and optionally focus
    if is_crush and result and result.edit and result.edit.changes then
      for uri, edits in pairs(result.edit.changes) do
        local bufnr = vim.uri_to_bufnr(uri)

        if not vim.api.nvim_buf_is_loaded(bufnr) then
          vim.fn.bufload(bufnr)
        end

        for _, edit in ipairs(edits) do
          local start_line = edit.range.start.line
          local end_line = edit.range['end'].line
          local new_lines = vim.split(edit.newText or '', '\n', { plain = true })
          local actual_end = start_line + #new_lines

          focus_edit(bufnr, start_line)
          flash_range(bufnr, start_line, math.max(actual_end, end_line + 1))
        end
      end
    end

    return response
  end

  handler_installed = true
end

-------------------------------------------------------------------------------
-- LSP Attachment (cursor sync)
-------------------------------------------------------------------------------

local function setup_cursor_sync(client, bufnr)
  local cursor_timer = nil

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = bufnr,
    group = vim.api.nvim_create_augroup('CrushLspCursorSync' .. bufnr, { clear = true }),
    callback = function()
      if cursor_timer then
        cursor_timer:stop()
      end
      cursor_timer = vim.defer_fn(function()
        local pos = vim.api.nvim_win_get_cursor(0)
        local uri = vim.uri_from_bufnr(bufnr)
        client:notify('crush/cursorMoved', {
          textDocument = { uri = uri },
          position = { line = pos[1] - 1, character = pos[2] },
        })
      end, 50)
    end,
  })
end

-------------------------------------------------------------------------------
-- Public API: Auto-focus
-------------------------------------------------------------------------------

function M.toggle_auto_focus()
  config.auto_focus = not config.auto_focus
  vim.notify('Crush auto-focus: ' .. (config.auto_focus and 'ON' or 'OFF'), vim.log.levels.INFO)
end

function M.enable_auto_focus()
  config.auto_focus = true
  vim.notify('Crush auto-focus: ON', vim.log.levels.INFO)
end

function M.disable_auto_focus()
  config.auto_focus = false
  vim.notify('Crush auto-focus: OFF', vim.log.levels.INFO)
end

function M.is_auto_focus_enabled()
  return config.auto_focus
end

-------------------------------------------------------------------------------
-- Public API: Terminal Management
-------------------------------------------------------------------------------

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

function M.close()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_hide(crush_win)
    crush_win = nil
  end
end

function M.toggle()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    M.close()
  else
    M.open()
  end
end

function M.focus()
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_set_current_win(crush_win)
    vim.cmd 'startinsert'
  else
    M.open()
  end
end

function M.set_width(width)
  config.terminal_width = width
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_set_width(crush_win, config.terminal_width)
  end
end

-------------------------------------------------------------------------------
-- Public API: LSP Client Management
-------------------------------------------------------------------------------

function M.start_lsp(opts)
  opts = opts or {}
  local cwd = vim.fn.getcwd()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  local root_dir = opts.root_dir or ((git_root and git_root ~= '' and vim.fn.isdirectory(git_root) == 1) and git_root or cwd)

  return vim.lsp.start {
    name = 'crush-lsp',
    cmd = { 'crush-lsp' },
    root_dir = root_dir,
    on_attach = function(client, bufnr)
      setup_cursor_sync(client, bufnr)
      if opts.on_attach then
        opts.on_attach(client, bufnr)
      end
    end,
  }
end

function M.get_client()
  local clients = vim.lsp.get_clients { name = 'crush-lsp' }
  return clients[1]
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

local function create_commands()
  vim.api.nvim_create_user_command('CrushOpen', function()
    M.open()
  end, { desc = 'Open Crush in right split terminal' })

  vim.api.nvim_create_user_command('CrushClose', function()
    M.close()
  end, { desc = 'Close Crush terminal' })

  vim.api.nvim_create_user_command('CrushToggle', function()
    M.toggle()
  end, { desc = 'Toggle Crush terminal' })

  vim.api.nvim_create_user_command('CrushFocus', function()
    M.focus()
  end, { desc = 'Focus Crush terminal' })

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
end

local function create_keymaps()
  if not config.keymaps then
    return
  end

  local maps = {
    { 'n', '<leader>cc', M.toggle, { desc = 'Toggle Crush terminal' } },
    { 'n', '<leader>cf', M.focus, { desc = 'Focus Crush terminal' } },
  }

  -- Allow keymap overrides via config.keymaps table
  if type(config.keymaps) == 'table' then
    for _, map in ipairs(maps) do
      local override = config.keymaps[map[2]]
      if override == false then
        goto continue
      elseif type(override) == 'string' then
        map[2] = override
      end
      vim.keymap.set(map[1], map[2], map[3], map[4])
      ::continue::
    end
  else
    for _, map in ipairs(maps) do
      vim.keymap.set(map[1], map[2], map[3], map[4])
    end
  end
end

local function setup_lsp_attach()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('CrushLspAttach', { clear = true }),
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client.name == 'crush-lsp' then
        setup_cursor_sync(client, event.buf)
      end
    end,
  })
end

local function setup_early_start()
  -- If VimEnter already fired (e.g., plugin loaded lazily), start immediately
  if vim.v.vim_did_enter == 1 then
    M.start_lsp()
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      group = vim.api.nvim_create_augroup('CrushLspEarlyStart', { clear = true }),
      callback = function()
        M.start_lsp()
      end,
    })
  end
end

---@param opts CrushLspConfig|nil
function M.setup(opts)
  config = vim.tbl_deep_extend('force', default_config, opts or {})

  install_apply_edit_handler()
  create_commands()
  create_keymaps()
  setup_lsp_attach()
  setup_early_start()
end

return M
