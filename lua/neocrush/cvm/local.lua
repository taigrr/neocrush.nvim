---@brief [[
--- Telescope picker for local repo commits in CVM
---@brief ]]

local M = {}

---Show the Telescope picker with local commit data.
---@param commits neocrush.LocalCommit[] List of commits
---@param repo_path string Path to the repo (for installation)
---@param install_fn fun(repo_path: string, commit: string) Function to call for installing
function M.show(commits, repo_path, install_fn)
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
      { width = 4 },
      { width = 12 },
      { width = 9 },
      { remaining = true },
    },
  }

  ---@param entry table
  ---@return table
  local function make_display(entry)
    local commit = entry.value
    local marker = ''
    local marker_hl = nil
    local hash_hl = nil
    if commit.is_head then
      marker = 'HEAD'
      marker_hl = 'CrushCvmHead'
      hash_hl = 'CrushCvmHead'
    end

    local tag_display = ''
    local tag_hl = nil
    if commit.tag then
      tag_display = commit.tag
      tag_hl = 'CrushCvmCurrent'
    end

    return displayer {
      { marker, marker_hl or 'CrushCvmHead' },
      { tag_display, tag_hl },
      { commit.short_hash, hash_hl },
      { commit.subject, 'Comment' },
    }
  end

  ---@param commit neocrush.LocalCommit
  ---@return table
  local function make_entry(commit)
    return {
      value = commit,
      display = make_display,
      ordinal = commit.short_hash .. ' ' .. (commit.tag or '') .. ' ' .. commit.ref .. ' ' .. commit.subject,
    }
  end

  local detail_previewer = previewers.new_buffer_previewer {
    title = 'Commit Details',
    define_preview = function(self, entry)
      local commit = entry.value
      local lines = {
        'Commit:    ' .. commit.hash,
        'Date:      ' .. commit.timestamp,
      }
      if commit.ref ~= '' then
        table.insert(lines, 'Refs:      ' .. commit.ref)
      end
      table.insert(lines, '')
      table.insert(lines, commit.subject)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      vim.fn.jobstart({ 'git', 'show', '--stat', '--format=', commit.hash }, {
        cwd = repo_path,
        stdout_buffered = true,
        on_stdout = function(_, data)
          if data and #data > 0 then
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(self.state.bufnr) then
                local current = vim.api.nvim_buf_get_lines(self.state.bufnr, 0, -1, false)
                table.insert(current, '')
                table.insert(current, '--- Files Changed ---')
                for _, line in ipairs(data) do
                  if line ~= '' then
                    table.insert(current, line)
                  end
                end
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, current)
              end
            end)
          end
        end,
      })
    end,
  }

  pickers
    .new({}, {
      prompt_title = 'Local Crush Commits (' .. repo_path .. ')',
      layout_strategy = 'horizontal',
      layout_config = {
        height = 0.8,
        width = 0.9,
        preview_width = 0.55,
        prompt_position = 'top',
      },
      finder = finders.new_table {
        results = commits,
        entry_maker = make_entry,
      },
      sorter = conf.generic_sorter {},
      previewer = detail_previewer,
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
            local commit = entry.value
            local label = commit.short_hash
            if commit.ref ~= '' then
              label = label .. ' (' .. commit.ref .. ')'
            end
            vim.ui.select({ 'Yes', 'No' }, {
              prompt = 'Build and install crush from ' .. label .. '?',
            }, function(choice)
              if choice == 'Yes' then
                install_fn(repo_path, commit.hash)
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
