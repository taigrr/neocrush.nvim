---@diagnostic disable: undefined-field

local bridge = require 'neocrush.bridge'

local eq = assert.are.same

-- Helper: create a scratch buffer with the given lines, focus its window,
-- and return the buffer handle. Caller is responsible for cleanup.
local function fresh_buffer(lines, name)
  local buf = vim.api.nvim_create_buf(true, false)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

describe('neocrush.bridge', function()
  describe('context()', function()
    it('reports cursor position and surrounding lines', function()
      local lines = { 'one', 'two', 'three', 'four', 'five' }
      fresh_buffer(lines, '/tmp/bridge-test-1.txt')
      vim.api.nvim_win_set_cursor(0, { 3, 1 })

      local ctx = bridge.context()
      eq(2, ctx.line) -- 0-indexed
      eq(1, ctx.column)
      eq('three', ctx.context_line)
      eq(5, ctx.total_lines)
      eq('one\ntwo', ctx.context_before)
      eq('four\nfive', ctx.context_after)
      eq(false, ctx.has_selection)
      eq('', ctx.selection)
    end)

    it('handles unnamed buffer with empty path', function()
      fresh_buffer({ 'x', 'y' }, nil)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local ctx = bridge.context()
      eq('', ctx.path)
      eq('', ctx.uri)
    end)

    it('clamps context near start/end of file', function()
      fresh_buffer({ 'a' }, '/tmp/bridge-test-2.txt')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local ctx = bridge.context()
      eq('', ctx.context_before)
      eq('', ctx.context_after)
      eq('a', ctx.context_line)
      eq(1, ctx.total_lines)
    end)
  end)

  describe('file_changed()', function()
    it('does not error on path that is not loaded', function()
      local missing = '/tmp/no-such-buffer-' .. tostring(os.time())
      assert.has_no.errors(function()
        bridge.file_changed(missing)
      end)
    end)

    it('does not error on empty path', function()
      assert.has_no.errors(function()
        bridge.file_changed ''
      end)
    end)
  end)

  describe('flash_edit()', function()
    it('does not error when buffer is not open', function()
      assert.has_no.errors(function()
        bridge.flash_edit('/tmp/no-such-buffer.txt', 0, 1)
      end)
    end)
  end)

  describe('show_locations()', function()
    it('does not error with empty items list', function()
      assert.has_no.errors(function()
        bridge.show_locations('Test', {})
      end)
    end)

    it('does not error with nil items', function()
      assert.has_no.errors(function()
        bridge.show_locations('Test', nil)
      end)
    end)
  end)
end)
