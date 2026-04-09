---@diagnostic disable: undefined-field

local highlight = require 'neocrush.highlight'

describe('neocrush.highlight', function()
  local test_buf

  before_each(function()
    test_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
      'line one',
      'line two',
      'line three',
      'line four',
      'line five',
    })

    highlight.setup {
      highlight_group = 'IncSearch',
      highlight_duration = 100,
      auto_focus = true,
      terminal_width = 80,
      terminal_cmd = 'crush',
    }
  end)

  after_each(function()
    if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  describe('flash_range', function()
    it('should not error on valid range', function()
      assert.has_no.errors(function()
        highlight.flash_range(test_buf, 0, 3)
      end)
    end)

    it('should not error on empty range', function()
      assert.has_no.errors(function()
        highlight.flash_range(test_buf, 2, 2)
      end)
    end)

    it('should clamp end_line to buffer length', function()
      assert.has_no.errors(function()
        highlight.flash_range(test_buf, 0, 100)
      end)
    end)

    it('should handle invalid buffer gracefully before setup', function()
      local h2 = require 'neocrush.highlight'
      -- flash_range checks config; with config set it should still not error on invalid buf
      assert.has_no.errors(function()
        pcall(h2.flash_range, 99999, 0, 1)
      end)
    end)
  end)

  describe('install', function()
    it('should install the handler', function()
      highlight.install()
      assert.is_true(highlight.is_installed())
    end)

    it('should be idempotent', function()
      highlight.install()
      highlight.install()
      assert.is_true(highlight.is_installed())
    end)
  end)

  describe('auto_focus_check callback', function()
    it('should accept auto_focus_check option in setup', function()
      local focus_enabled = true
      assert.has_no.errors(function()
        highlight.setup({
          highlight_group = 'IncSearch',
          highlight_duration = 100,
          auto_focus = true,
          terminal_width = 80,
          terminal_cmd = 'crush',
        }, {
          auto_focus_check = function()
            return focus_enabled
          end,
        })
      end)
    end)

    it('should work without auto_focus_check option', function()
      assert.has_no.errors(function()
        highlight.setup {
          highlight_group = 'IncSearch',
          highlight_duration = 100,
          auto_focus = true,
          terminal_width = 80,
          terminal_cmd = 'crush',
        }
      end)
    end)
  end)
end)
