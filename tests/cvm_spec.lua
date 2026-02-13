---@diagnostic disable: undefined-field

local cvm = require 'neocrush.cvm'

describe('neocrush.cvm', function()
  describe('setup', function()
    it('should accept empty config', function()
      assert.has_no.errors(function()
        cvm.setup {}
      end)
    end)

    it('should accept custom upstream', function()
      cvm.setup { upstream = 'myorg/mycrush' }
      local cfg = cvm._get_config()
      assert.are.same('myorg/mycrush', cfg.upstream)
    end)

    it('should use default upstream when not specified', function()
      cvm.setup {}
      local cfg = cvm._get_config()
      assert.are.same('charmbracelet/crush', cfg.upstream)
    end)

    it('should handle nil opts', function()
      assert.has_no.errors(function()
        cvm.setup()
      end)
      local cfg = cvm._get_config()
      assert.are.same('charmbracelet/crush', cfg.upstream)
    end)
  end)

  describe('get_current_version', function()
    it('should call callback with nil when crush is not installed', function()
      local original = vim.fn.executable
      vim.fn.executable = function()
        return 0
      end

      local result = 'not_called'
      cvm.get_current_version(function(version)
        result = version
      end)

      assert.is_nil(result)
      vim.fn.executable = original
    end)
  end)
end)
