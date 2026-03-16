---@diagnostic disable: undefined-field

local locations = require 'neocrush.locations'

describe('neocrush.locations', function()
  describe('show_quickfix', function()
    it('should set quickfix list with items', function()
      local items = {
        { filename = 'test.lua', lnum = 10, text = 'some code', note = 'relevant because X' },
        { filename = 'other.lua', lnum = 20, col = 5, text = 'other code' },
      }

      locations.show_quickfix('Test Locations', items)

      local qf = vim.fn.getqflist { title = true, items = true }
      assert.are.same('Test Locations', qf.title)
      assert.are.same(2, #qf.items)

      vim.cmd 'cclose'
    end)

    it('should use default title when nil', function()
      locations.show_quickfix(nil, {
        { filename = 'a.lua', lnum = 1 },
      })

      local qf = vim.fn.getqflist { title = true }
      assert.are.same('AI Locations', qf.title)

      vim.cmd 'cclose'
    end)

    it('should combine note and text in quickfix text field', function()
      locations.show_quickfix('Test', {
        { filename = 'a.lua', lnum = 1, text = 'code here', note = 'because reasons' },
      })

      local qf = vim.fn.getqflist { items = true }
      local text = qf.items[1].text
      assert.truthy(text:find 'because reasons')
      assert.truthy(text:find 'code here')

      vim.cmd 'cclose'
    end)

    it('should handle items with only note', function()
      locations.show_quickfix('Test', {
        { filename = 'a.lua', lnum = 1, note = 'just a note' },
      })

      local qf = vim.fn.getqflist { items = true }
      assert.are.same('just a note', qf.items[1].text)

      vim.cmd 'cclose'
    end)

    it('should handle items with only text', function()
      locations.show_quickfix('Test', {
        { filename = 'a.lua', lnum = 1, text = 'just text' },
      })

      local qf = vim.fn.getqflist { items = true }
      assert.are.same('just text', qf.items[1].text)

      vim.cmd 'cclose'
    end)
  end)

  describe('handler', function()
    it('should handle error parameter', function()
      -- Should not crash when called with error
      assert.has_no.errors(function()
        locations.handler('some error', nil, nil, nil)
      end)
    end)

    it('should handle nil params', function()
      assert.has_no.errors(function()
        locations.handler(nil, nil, nil, nil)
      end)
    end)

    it('should handle empty items', function()
      assert.has_no.errors(function()
        locations.handler(nil, { items = {} }, nil, nil)
      end)
    end)

    it('should fall back to quickfix when telescope is not available', function()
      -- In test env telescope is not available, so it should use quickfix
      locations.handler(nil, {
        title = 'Handler Test',
        items = {
          { filename = 'test.lua', lnum = 5, text = 'hello' },
        },
      }, nil, nil)

      local qf = vim.fn.getqflist { title = true, items = true }
      assert.are.same('Handler Test', qf.title)
      assert.are.same(1, #qf.items)

      vim.cmd 'cclose'
    end)
  end)
end)
