---@brief [[
--- neocrush.bridge - Direct RPC bridge between Crush (the binary) and this Neovim instance.
---
--- This module is the entire wire protocol Crush v2 uses. Crush dials the
--- $NVIM socket of the Neovim instance that spawned it (via :terminal),
--- then calls these functions over msgpack-rpc using nvim_exec_lua. No
--- LSP, no daemon, no socket discovery: the (nvim, crush) pair is
--- pinned by the OS.
---
--- Functions exposed:
---   context()                 -> table with cursor / surrounding lines / selection.
---   show_locations(t, items)  -> opens the Telescope picker (or quickfix).
---   flash_edit(p, s, e)       -> highlights a freshly-edited region.
---   file_changed(p)           -> reloads a buffer Crush wrote on disk; kills the W11 prompt.
---   set_cwd(p)                -> changes the editor's working dir (worktree switch).
---@brief ]]

local M = {}

local CONTEXT_RADIUS = 5

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

---Find the buffer holding the given absolute path, if any. Returns 0 when
---no buffer matches; callers treat 0 as "buffer not loaded".
---@param path string
---@return integer bufnr 0 when no match
local function find_buffer(path)
  if path == nil or path == '' then
    return 0
  end
  local target = vim.fn.fnamemodify(path, ':p')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= '' and vim.fn.fnamemodify(name, ':p') == target then
        return buf
      end
    end
  end
  return 0
end

---Return up to `radius` lines before and after the given 0-indexed line
---in `bufnr`. Always returns three strings (before / line / after) so
---callers can pass them straight through to JSON.
---@param bufnr integer
---@param line integer 0-indexed
---@param radius integer
---@return string before
---@return string current
---@return string after
local function surrounding(bufnr, line, radius)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local before_start = math.max(0, line - radius)
  local after_end = math.min(total, line + radius + 1)

  local before = vim.api.nvim_buf_get_lines(bufnr, before_start, line, false)
  local current = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
  local after = vim.api.nvim_buf_get_lines(bufnr, line + 1, after_end, false)

  return table.concat(before, '\n'), table.concat(current, '\n'), table.concat(after, '\n')
end

---Read the current visual selection. Empty string when nothing is
---selected. Uses the '< / '> marks so it works after the user has left
---visual mode.
---@param bufnr integer
---@return boolean has_selection
---@return string text
local function visual_selection(bufnr)
  local s = vim.api.nvim_buf_get_mark(bufnr, '<')
  local e = vim.api.nvim_buf_get_mark(bufnr, '>')
  if s[1] == 0 or e[1] == 0 then
    return false, ''
  end
  if s[1] == e[1] and s[2] == e[2] then
    return false, ''
  end
  -- nvim_buf_get_text uses 0-indexed rows but inclusive columns.
  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, s[1] - 1, s[2], e[1] - 1, e[2] + 1, {})
  if not ok or not lines or #lines == 0 then
    return false, ''
  end
  local text = table.concat(lines, '\n')
  return text ~= '', text
end

---------------------------------------------------------------------------
-- API: context()
---------------------------------------------------------------------------

---Snapshot the current editor state. Pull-based on every call, so the
---result always reflects the cursor position at the moment Crush asked.
---@return table
function M.context()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]

  local path = vim.api.nvim_buf_get_name(buf)
  if path ~= '' then
    path = vim.fn.fnamemodify(path, ':p')
  end

  local before, current, after = surrounding(buf, row, CONTEXT_RADIUS)
  local has_sel, sel = visual_selection(buf)

  return {
    path = path,
    uri = path ~= '' and ('file://' .. path) or '',
    line = row,
    column = col,
    context_before = before,
    context_line = current,
    context_after = after,
    total_lines = vim.api.nvim_buf_line_count(buf),
    has_selection = has_sel,
    selection = sel,
  }
end

---------------------------------------------------------------------------
-- API: show_locations(title, items)
---------------------------------------------------------------------------

---Forward the AI's annotated locations to the Telescope picker (with
---fallback to quickfix). Delegates to the existing locations module so
---the picker UI is unchanged from v1.
---@param title string|nil
---@param items table
function M.show_locations(title, items)
  local ok, locations = pcall(require, 'neocrush.locations')
  if not ok then
    vim.notify('neocrush.locations module missing: ' .. tostring(locations), vim.log.levels.ERROR)
    return
  end
  -- Schedule because Crush may call us from the RPC thread.
  vim.schedule(function()
    locations.handler(nil, { title = title, items = items or {} }, nil, nil)
  end)
end

---------------------------------------------------------------------------
-- API: flash_edit(path, start_line, end_line)
---------------------------------------------------------------------------

---Briefly highlight the region [start_line, end_line) in the buffer for
---path. Does nothing if the file isn't open in this Neovim. Best-effort:
---never raises so a transient API change can't cascade into a Crush tool
---failure.
---@param path string absolute file path
---@param start_line integer 0-indexed
---@param end_line integer 0-indexed exclusive
function M.flash_edit(path, start_line, end_line)
  vim.schedule(function()
    local highlight = require 'neocrush.highlight'
    local bufnr = find_buffer(path)
    if bufnr == 0 then
      return
    end
    -- Keep buffer in sync with disk before we paint extmarks; otherwise
    -- the line range may already be stale.
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, 'silent! checktime')
    end)
    pcall(highlight.flash_range, bufnr, start_line, end_line)
  end)
end

---------------------------------------------------------------------------
-- API: file_changed(path)
---------------------------------------------------------------------------

---Tell Neovim that path was just written by Crush. If the buffer is
---loaded and unmodified, reload silently (suppressing the W11 "file has
---been edited since you opened" prompt). If the buffer has unsaved user
---edits, leave it alone — clobbering the user's work would be worse than
---a prompt.
---@param path string absolute file path
function M.file_changed(path)
  vim.schedule(function()
    local bufnr = find_buffer(path)
    if bufnr == 0 then
      return
    end
    if vim.bo[bufnr].modified then
      -- User has unsaved edits; do not touch.
      return
    end
    -- autoread + checktime is the standard incantation: it reloads the
    -- buffer from disk if the on-disk mtime is newer, no prompt.
    vim.bo[bufnr].autoread = true
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, 'silent! checktime')
    end)
  end)
end

---------------------------------------------------------------------------
-- API: set_cwd(path)
---------------------------------------------------------------------------

---Change Neovim's working directory to path, e.g. when Crush switches
---the active worktree so the editor follows the agent into the new
---tree. Uses global :cd so the change is instance-wide: new buffers,
---:terminal jobs, and floating terminals all spawn in the worktree.
---Best-effort: never raises, and silently ignores a missing/empty path
---or a directory that no longer exists.
---@param path string absolute directory path
function M.set_cwd(path)
  if path == nil or path == '' then
    return
  end
  vim.schedule(function()
    local dir = vim.fn.fnamemodify(path, ':p')
    if vim.fn.isdirectory(dir) == 0 then
      return
    end
    -- Quote against spaces/specials in the path.
    pcall(vim.cmd, 'cd ' .. vim.fn.fnameescape(dir))
  end)
end

return M
