---@diagnostic disable: undefined-field

local prompts = require 'neocrush.prompts'

local eq = assert.are.same

describe('neocrush.prompts', function()
  before_each(function()
    -- Reset prompts state between tests by re-requiring the module
    package.loaded['neocrush.prompts'] = nil
    prompts = require 'neocrush.prompts'
  end)

  describe('setup', function()
    it('should accept empty config', function()
      assert.has_no.errors(function()
        prompts.setup {}
      end)
    end)

    it('should accept nil config', function()
      assert.has_no.errors(function()
        prompts.setup(nil)
      end)
    end)
  end)

  describe('register', function()
    it('should register string prompts', function()
      prompts.register {
        Test = 'run tests',
      }
      local list = prompts.list()
      eq('run tests', list.Test)
    end)

    it('should register table prompts', function()
      prompts.register {
        Lint = { template = 'fix lint errors', desc = 'Fix linting' },
      }
      local list = prompts.list()
      eq('fix lint errors', list.Lint.template)
      eq('Fix linting', list.Lint.desc)
    end)

    it('should create user commands for prompts', function()
      prompts.register {
        MyCmd = 'hello world',
      }
      -- Check that the command exists
      local commands = vim.api.nvim_get_commands {}
      assert.is_not_nil(commands.CrushMyCmd)
    end)

    it('should create commands with correct nargs for templates with %s', function()
      prompts.register {
        Review = { template = 'review PR #%s', desc = 'Review a PR' },
      }
      local commands = vim.api.nvim_get_commands {}
      -- nargs should be '?' for optional arg when %s is present
      eq('?', commands.CrushReview.nargs)
    end)

    it('should create commands with nargs=0 for templates without %s', function()
      prompts.register {
        Simple = { template = 'do something simple' },
      }
      local commands = vim.api.nvim_get_commands {}
      eq('0', commands.CrushSimple.nargs)
    end)

    it('should respect explicit nargs override', function()
      prompts.register {
        Multi = { template = 'process files', nargs = '*' },
      }
      local commands = vim.api.nvim_get_commands {}
      eq('*', commands.CrushMulti.nargs)
    end)
  end)

  describe('list', function()
    it('should return empty table initially', function()
      local list = prompts.list()
      eq({}, list)
    end)

    it('should return all registered prompts', function()
      prompts.register {
        A = 'prompt a',
        B = { template = 'prompt b' },
      }
      local list = prompts.list()
      assert.is_not_nil(list.A)
      assert.is_not_nil(list.B)
    end)

    it('should return a copy not a reference', function()
      prompts.register {
        X = 'original',
      }
      local list = prompts.list()
      list.X = 'modified'
      local list2 = prompts.list()
      eq('original', list2.X)
    end)
  end)

  describe('execute', function()
    -- Note: execute() calls terminal functions which we can't easily test
    -- without mocking. Test the error case for unknown prompts.

    it('should error for unknown prompt', function()
      local notified = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match 'Unknown Crush prompt' and level == vim.log.levels.ERROR then
          notified = true
        end
      end

      prompts.execute('NonExistent', '')

      vim.notify = original_notify
      assert.is_true(notified)
    end)
  end)
end)
