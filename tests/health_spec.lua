---@diagnostic disable: undefined-field

local health = require 'neocrush.health'

describe('neocrush.health', function()
  local original_health
  local original_executable
  local original_system

  before_each(function()
    original_health = vim.health
    original_executable = vim.fn.executable
    original_system = vim.fn.system
  end)

  after_each(function()
    vim.health = original_health
    vim.fn.executable = original_executable
    vim.fn.system = original_system
  end)

  it('should not require the removed neocrush daemon binary', function()
    local errors = {}
    local infos = {}

    vim.health = {
      start = function() end,
      ok = function() end,
      warn = function() end,
      info = function(msg)
        table.insert(infos, msg)
      end,
      error = function(msg)
        table.insert(errors, msg)
      end,
    }

    vim.fn.executable = function(name)
      if name == 'neocrush' then
        return 0
      end
      return 1
    end

    vim.fn.system = function(cmd)
      if cmd:find 'crush --version' then
        return 'crush test\n'
      end
      if cmd:find 'go version' then
        return 'go version go1.25.0 linux/amd64\n'
      end
      return ''
    end

    health.check()

    for _, msg in ipairs(errors) do
      assert.is_nil(msg:find 'neocrush')
    end

    assert.is_true(
      vim.tbl_contains(infos, 'No neocrush daemon required in v2; Crush connects directly to this Neovim instance')
    )
  end)
end)
