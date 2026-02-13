---@brief [[
--- Terminal management for neocrush.nvim
--- Persistent Crush terminal in a right split with open/close/toggle/focus
---@brief ]]

local M = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

---@type integer|nil Window handle for the Crush terminal
local crush_win = nil

---@type integer|nil Buffer handle for the Crush terminal
local crush_buf = nil

---@type neocrush.Config
local config

-------------------------------------------------------------------------------
-- Window Helpers
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

  return buftype == '' or buftype == 'acwrite'
end

--- Find the best window to open an edited file in.
--- Returns the leftmost non-special, non-crush window.
---@return integer|nil win Window handle or nil if none found
function M.find_edit_target_window()
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

  table.sort(candidates, function(a, b)
    return a.col < b.col
  end)

  return candidates[1].win
end

--- Get the text from the last visual selection.
---@return string|nil text Selected text or nil if no valid selection
function M.get_visual_selection_text()
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

-------------------------------------------------------------------------------
-- Public API
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
    local wins = vim.api.nvim_tabpage_list_wins(0)
    if #wins <= 1 then
      vim.cmd 'enew'
    end
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

--- Run `crush logs` and load the output into a new buffer.
function M.logs()
  vim.fn.jobstart({ 'crush', 'logs' }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 and (data[1] ~= '' or #data > 1) then
        vim.schedule(function()
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, data)
          vim.bo[buf].buftype = 'nofile'
          vim.bo[buf].bufhidden = 'wipe'
          vim.bo[buf].swapfile = false
          vim.bo[buf].filetype = 'markdown'
          vim.api.nvim_buf_set_name(buf, 'Crush Logs')

          local target_win = M.find_edit_target_window()
          if target_win then
            vim.api.nvim_win_set_buf(target_win, buf)
          else
            vim.cmd 'topleft vnew'
            local new_win = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_buf(new_win, buf)
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= '' then
        vim.schedule(function()
          vim.notify('crush logs error: ' .. table.concat(data, '\n'), vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

--- Send escape sequence to cancel the current Crush operation.
--- Sends <Esc><Esc> to the Crush terminal buffer.
function M.cancel()
  if not crush_buf or not vim.api.nvim_buf_is_valid(crush_buf) then
    vim.notify('Crush terminal not running', vim.log.levels.WARN)
    return
  end

  local term_chan = vim.bo[crush_buf].channel
  if term_chan == 0 then
    vim.notify('Crush terminal channel not found', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_chan_send(term_chan, '\27')
  vim.defer_fn(function()
    if crush_buf and vim.api.nvim_buf_is_valid(crush_buf) then
      local chan = vim.bo[crush_buf].channel
      if chan and chan ~= 0 then
        vim.api.nvim_chan_send(chan, '\27')
      end
    end
  end, 50)
end

--- Restart the Crush terminal by killing the current process and starting a new one.
function M.restart()
  if crush_buf and vim.api.nvim_buf_is_valid(crush_buf) then
    local term_chan = vim.bo[crush_buf].channel
    if term_chan and term_chan ~= 0 then
      vim.fn.jobstop(term_chan)
    end
    vim.api.nvim_buf_delete(crush_buf, { force = true })
    crush_buf = nil
  end

  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_close(crush_win, true)
    crush_win = nil
  end

  M.open()
end

--- Paste text into the Crush terminal.
--- Can paste from a register or the current visual selection.
---@param register? string Register to paste from (default: '+' for system clipboard)
function M.paste(register)
  if not crush_buf or not vim.api.nvim_buf_is_valid(crush_buf) then
    vim.notify('Crush terminal not running', vim.log.levels.WARN)
    return
  end

  local term_chan = vim.bo[crush_buf].channel
  if term_chan == 0 then
    vim.notify('Crush terminal channel not found', vim.log.levels.WARN)
    return
  end

  register = register or '+'
  local content = vim.fn.getreg(register)

  if content == '' then
    vim.notify('Register "' .. register .. '" is empty', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_chan_send(term_chan, content)
end

--- Paste the current visual selection into the Crush terminal.
function M.paste_selection()
  if not crush_buf or not vim.api.nvim_buf_is_valid(crush_buf) then
    vim.notify('Crush terminal not running', vim.log.levels.WARN)
    return
  end

  local term_chan = vim.bo[crush_buf].channel
  if term_chan == 0 then
    vim.notify('Crush terminal channel not found', vim.log.levels.WARN)
    return
  end

  local text = M.get_visual_selection_text()
  if not text or text == '' then
    vim.notify('No visual selection', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_chan_send(term_chan, text)
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

---@param cfg neocrush.Config
function M.setup(cfg)
  config = cfg
end

-------------------------------------------------------------------------------
-- Test Helpers
-------------------------------------------------------------------------------

M._is_file_window = is_file_window
M._find_edit_target_window = M.find_edit_target_window

return M
