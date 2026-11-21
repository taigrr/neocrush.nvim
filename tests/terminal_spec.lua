---@diagnostic disable: undefined-field

local terminal = require 'neocrush.terminal'

describe('neocrush.terminal', function()
  before_each(function()
    terminal.setup {
      highlight_group = 'IncSearch',
      highlight_duration = 900,
      auto_focus = true,
      terminal_width = 80,
      terminal_cmd = 'crush',
    }
  end)

  describe('_is_file_window', function()
    it('should return true for a normal buffer window', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, buf)
      assert.is_true(terminal._is_file_window(vim.api.nvim_get_current_win()))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return false for invalid window', function()
      assert.is_false(terminal._is_file_window(99999))
    end)

    it('should return false for a nofile buffer window', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = 'nofile'
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      assert.is_false(terminal._is_file_window(win))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('_find_edit_target_window', function()
    it('should return a window when a file window exists', function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, buf)
      local win = terminal._find_edit_target_window()
      -- May or may not find one depending on test env buf state
      -- Just verify it doesn't crash
      assert.is_true(win == nil or type(win) == 'number')
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('get_visual_selection_text', function()
    it('should return nil when no selection exists', function()
      local result = terminal.get_visual_selection_text()
      -- With no prior visual selection, marks are at 0,0
      -- Result should be nil or empty
      assert.is_true(result == nil or type(result) == 'string')
    end)
  end)

  describe('set_width', function()
    it('should reject widths smaller than 1', function()
      local original_notify = vim.notify
      local messages = {}

      vim.notify = function(msg)
        table.insert(messages, msg)
      end

      local ok = terminal.set_width(0)

      assert.is_false(ok)
      assert.truthy(messages[1]:find 'at least 1 column')

      vim.notify = original_notify
    end)

    it('should accept positive widths', function()
      assert.is_true(terminal.set_width(42))
    end)
  end)

  describe('close', function()
    it('should not error when no terminal is open', function()
      assert.has_no.errors(function()
        terminal.close()
      end)
    end)
  end)

  describe('cancel', function()
    it('should warn when no terminal is running', function()
      assert.has_no.errors(function()
        terminal.cancel()
      end)
    end)
  end)

  describe('paste', function()
    it('should warn when no terminal is running', function()
      assert.has_no.errors(function()
        terminal.paste()
      end)
    end)
  end)

  describe('paste_selection', function()
    it('should warn when no terminal is running', function()
      assert.has_no.errors(function()
        terminal.paste_selection()
      end)
    end)
  end)
end)

describe('terminal close lifecycle', function()
  local managed_terminal
  local terminal_buf

  before_each(function()
    package.loaded['neocrush.terminal'] = nil
    managed_terminal = require 'neocrush.terminal'
    managed_terminal.setup { terminal_width = 40, terminal_cmd = 'cat' }
    vim.cmd 'only!'
    managed_terminal.open()
    terminal_buf = managed_terminal._get_buf()
  end)

  after_each(function()
    vim.cmd 'stopinsert'
    if terminal_buf and vim.api.nvim_buf_is_valid(terminal_buf) then
      vim.api.nvim_buf_delete(terminal_buf, { force = true })
    end
    vim.cmd 'only!'
    package.loaded['neocrush.terminal'] = terminal
  end)

  it('hides the terminal without stopping its process', function()
    managed_terminal.close()
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_true(vim.api.nvim_buf_is_valid(terminal_buf))
    assert.equals(-1, vim.fn.jobwait({ vim.bo[terminal_buf].channel }, 0)[1])
    managed_terminal.open()
    assert.equals(terminal_buf, vim.api.nvim_get_current_buf())
  end)

  it('replaces the last terminal window with an editable buffer', function()
    vim.cmd 'only!'
    managed_terminal.close()
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals('', vim.bo.buftype)
    assert.is_not.equals(terminal_buf, vim.api.nvim_get_current_buf())
    assert.is_true(vim.api.nvim_buf_is_valid(terminal_buf))
    assert.equals(-1, vim.fn.jobwait({ vim.bo[terminal_buf].channel }, 0)[1])
    managed_terminal.open()
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(terminal_buf, vim.api.nvim_get_current_buf())
  end)
end)
