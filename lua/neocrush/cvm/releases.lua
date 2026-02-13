---@brief [[
--- Telescope picker for GitHub releases in CVM
---@brief ]]

local M = {}

---@type table[]|nil Cached releases from GitHub API
M.cache = nil

---Show the Telescope picker with release data.
---@param releases table[] GitHub release objects
---@param current_version string|nil Currently installed version
---@param install_fn fun(tag: string) Function to call for installing a tag
function M.show(releases, current_version, install_fn)
  local cvm = require 'neocrush.cvm'
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local previewers = require 'telescope.previewers'
  local entry_display = require 'telescope.pickers.entry_display'

  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = 3 },
      { width = 12 },
      { remaining = true },
    },
  }

  ---@param entry table
  ---@return table
  local function make_display(entry)
    local release = entry.value
    local marker = ''
    local tag_hl = nil
    if current_version and release.tag_name == current_version then
      marker = ' *'
      tag_hl = 'CrushCvmCurrent'
    end

    return displayer {
      { marker, 'CrushCvmCurrent' },
      { release.tag_name, tag_hl },
      { release.name or release.tag_name, 'Comment' },
    }
  end

  ---@param release table
  ---@return table
  local function make_entry(release)
    return {
      value = release,
      display = make_display,
      ordinal = release.tag_name .. ' ' .. (release.name or ''),
    }
  end

  local notes_previewer
  if cvm.is_glow_available() then
    notes_previewer = previewers.new_termopen_previewer {
      title = 'Release Notes',
      get_command = function(entry)
        local release = entry.value
        local body = release.body or 'No release notes.'
        local tag = release.tag_name or ''
        local tmpfile = cvm.get_notes_tmpfile(tag, body)
        return { 'glow', '-s', 'dark', '-p', tmpfile }
      end,
    }
  else
    notes_previewer = previewers.new_buffer_previewer {
      title = 'Release Notes',
      define_preview = function(self, entry)
        local release = entry.value
        local body = release.body or 'No release notes.'
        local lines = vim.split(body, '\r?\n')
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = 'markdown'
      end,
    }
  end

  local picker_title = 'Crush Releases'
  if current_version then
    picker_title = picker_title .. ' (current: ' .. current_version .. ')'
  else
    picker_title = picker_title .. ' (crush not installed)'
  end

  pickers
    .new({}, {
      prompt_title = picker_title,
      layout_strategy = 'horizontal',
      layout_config = {
        height = 0.8,
        width = 0.9,
        preview_width = 0.55,
        prompt_position = 'top',
      },
      finder = finders.new_table {
        results = releases,
        entry_maker = make_entry,
      },
      sorter = conf.generic_sorter {},
      previewer = notes_previewer,
      attach_mappings = function(prompt_bufnr, map)
        map('i', '<Down>', actions.preview_scrolling_down)
        map('i', '<Up>', actions.preview_scrolling_up)
        map('i', '<C-n>', actions.move_selection_next)
        map('i', '<C-p>', actions.move_selection_previous)
        map('n', '<Down>', actions.preview_scrolling_down)
        map('n', '<Up>', actions.preview_scrolling_up)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            local tag = entry.value.tag_name
            vim.ui.select({ 'Yes', 'No' }, {
              prompt = 'Install crush ' .. tag .. '?',
            }, function(choice)
              if choice == 'Yes' then
                install_fn(tag)
              end
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
