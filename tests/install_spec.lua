---@diagnostic disable: undefined-field

local install = require 'neocrush.install'

describe('neocrush.install', function()
  describe('is_installed', function()
    it('should return a boolean for neocrush', function()
      local result = install.is_installed 'neocrush'
      assert.is_boolean(result)
    end)

    it('should return a boolean for crush', function()
      local result = install.is_installed 'crush'
      assert.is_boolean(result)
    end)

    it('should return false for unknown binary', function()
      local result = install.is_installed 'nonexistent-binary-12345'
      assert.is_false(result)
    end)
  end)
end)
