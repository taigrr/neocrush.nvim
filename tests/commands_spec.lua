---@diagnostic disable: undefined-field

local neocrush = require 'neocrush'
local terminal = require 'neocrush.terminal'

describe('neocrush.commands', function()
  before_each(function()
    neocrush.setup {}
  end)

  describe('user commands', function()
    it('should register CrushToggle command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushToggle)
    end)

    it('should register CrushOpen command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushOpen)
    end)

    it('should register CrushClose command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushClose)
    end)

    it('should register CrushFocus command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushFocus)
    end)

    it('should register CrushWidth command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushWidth)
    end)

    it('should register CrushFocusToggle command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushFocusToggle)
    end)

    it('should register CrushFocusOn command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushFocusOn)
    end)

    it('should register CrushFocusOff command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushFocusOff)
    end)

    it('should register CrushLogs command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushLogs)
    end)

    it('should register CrushCancel command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushCancel)
    end)

    it('should register CrushRestart command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushRestart)
    end)

    it('should register CrushPaste command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushPaste)
    end)

    it('should register CrushCvmReleases command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushCvmReleases)
    end)

    it('should register CrushCvmLocal command', function()
      local cmds = vim.api.nvim_get_commands {}
      assert.is_not_nil(cmds.CrushCvmLocal)
    end)
  end)

  describe('CrushWidth validation', function()
    it('should reject widths smaller than 1', function()
      local original_notify = vim.notify
      local original_set_width = terminal.set_width
      local messages = {}
      local called = false

      vim.notify = function(msg)
        table.insert(messages, msg)
      end
      terminal.set_width = function(width)
        called = true
        return original_set_width(width)
      end

      vim.cmd 'CrushWidth 0'

      assert.is_false(called)
      assert.truthy(messages[1]:find 'number >= 1')

      terminal.set_width = original_set_width
      vim.notify = original_notify
    end)
  end)
end)
