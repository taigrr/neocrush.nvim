---@diagnostic disable: undefined-field

local neocrush = require 'neocrush'

local eq = assert.are.same

describe('neocrush', function()
  describe('setup', function()
    it('should accept empty options', function()
      assert.has_no.errors(function()
        neocrush.setup {}
      end)
    end)

    it('should accept custom highlight_group', function()
      assert.has_no.errors(function()
        neocrush.setup { highlight_group = 'Visual' }
      end)
    end)

    it('should accept custom highlight_duration', function()
      assert.has_no.errors(function()
        neocrush.setup { highlight_duration = 500 }
      end)
    end)

    it('should accept custom terminal_width', function()
      assert.has_no.errors(function()
        neocrush.setup { terminal_width = 100 }
      end)
    end)
  end)

  describe('auto_focus', function()
    before_each(function()
      neocrush.setup { auto_focus = true }
    end)

    it('should start enabled by default', function()
      neocrush.setup {}
      assert.is_true(neocrush.is_auto_focus_enabled())
    end)

    it('should toggle auto_focus', function()
      local initial = neocrush.is_auto_focus_enabled()
      neocrush.toggle_auto_focus()
      eq(not initial, neocrush.is_auto_focus_enabled())
    end)

    it('should enable auto_focus', function()
      neocrush.disable_auto_focus()
      neocrush.enable_auto_focus()
      assert.is_true(neocrush.is_auto_focus_enabled())
    end)

    it('should disable auto_focus', function()
      neocrush.enable_auto_focus()
      neocrush.disable_auto_focus()
      assert.is_false(neocrush.is_auto_focus_enabled())
    end)
  end)
end)
