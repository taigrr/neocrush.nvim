---@brief [[
--- neocrush.nvim locations picker
--- Displays AI-annotated code locations in a custom Telescope picker
---@brief ]]

local M = {}

-------------------------------------------------------------------------------
-- Quickfix Fallback
-------------------------------------------------------------------------------

--- Show locations in quickfix list (fallback when Telescope not available).
---@param title string Title for the quickfix list
---@param items table[] Location items
function M.show_quickfix(title, items)
  local qf_items = {}
  for _, item in ipairs(items) do
    table.insert(qf_items, {
      filename = item.filename,
      lnum = item.lnum,
      col = item.col or 1,
      text = (item.note or '') .. ' | ' .. (item.text or ''),
      type = item.type or 'N',
    })
  end

  vim.fn.setqflist({}, ' ', { title = title or 'AI Locations', items = qf_items })
  vim.cmd 'copen'
end

-------------------------------------------------------------------------------
-- Telescope Picker
-------------------------------------------------------------------------------

--- Show locations in custom Telescope picker with notes panel.
---@param title string Title for the picker
---@param items table[] Location items with filename, lnum, text, note
function M.show_telescope(title, items)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  -- Create notes buffer and window upfront
  local notes_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[notes_buf].buftype = 'nofile'
  vim.bo[notes_buf].filetype = 'markdown'
  local notes_win = nil

  local function update_notes_window(entry)
    if not entry or not entry.value then
      return
    end

    local item = entry.value
    local note = item.note or 'No note provided'

    local lines = {}
    for line in note:gmatch '[^\n]+' do
      table.insert(lines, line)
    end

    vim.api.nvim_buf_set_lines(notes_buf, 0, -1, false, lines)

    -- Create or update floating window
    local ui = vim.api.nvim_list_uis()[1]
    local width = math.floor(ui.width * 0.88)
    local height = 6
    local telescope_height = math.floor(ui.height * 0.7)
    local telescope_top = math.floor((ui.height - telescope_height) / 2)
    local notes_row = telescope_top + telescope_height + 1

    if notes_row + height > ui.height - 1 then
      notes_row = telescope_top - height - 1
      if notes_row < 0 then
        notes_row = 0
      end
    end

    local opts = {
      relative = 'editor',
      width = width,
      height = height,
      col = math.floor((ui.width - width) / 2),
      row = notes_row,
      style = 'minimal',
      border = 'rounded',
      title = ' AI Context ',
      title_pos = 'center',
    }

    if notes_win and vim.api.nvim_win_is_valid(notes_win) then
      vim.api.nvim_win_set_config(notes_win, opts)
    else
      notes_win = vim.api.nvim_open_win(notes_buf, false, opts)
      vim.wo[notes_win].wrap = true
      vim.wo[notes_win].conceallevel = 2
    end
  end

  local function cleanup_notes()
    if notes_win and vim.api.nvim_win_is_valid(notes_win) then
      pcall(vim.api.nvim_win_close, notes_win, true)
    end
    if notes_buf and vim.api.nvim_buf_is_valid(notes_buf) then
      pcall(vim.api.nvim_buf_delete, notes_buf, { force = true })
    end
  end

  pickers
    .new({}, {
      prompt_title = title or 'AI Locations',
      layout_strategy = 'horizontal',
      layout_config = {
        height = 0.7,
        width = 0.9,
        preview_width = 0.55,
        prompt_position = 'top',
      },
      finder = finders.new_table {
        results = items,
        entry_maker = function(item)
          local display = string.format('%s:%d', item.filename, item.lnum)
          return {
            value = item,
            display = display,
            ordinal = display .. ' ' .. (item.text or '') .. ' ' .. (item.note or ''),
            path = item.filename,
            filename = item.filename,
            lnum = item.lnum,
            col = item.col or 1,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.grep_previewer {},
      attach_mappings = function(prompt_bufnr, map)
        -- Update notes on move actions
        local function move_and_update(move_fn)
          return function()
            move_fn(prompt_bufnr)
            local entry = action_state.get_selected_entry()
            update_notes_window(entry)
          end
        end

        map('i', '<Down>', move_and_update(actions.move_selection_next))
        map('i', '<Up>', move_and_update(actions.move_selection_previous))
        map('n', 'j', move_and_update(actions.move_selection_next))
        map('n', 'k', move_and_update(actions.move_selection_previous))
        map('i', '<C-n>', move_and_update(actions.move_selection_next))
        map('i', '<C-p>', move_and_update(actions.move_selection_previous))

        -- Cleanup on close
        actions.close:enhance {
          post = cleanup_notes,
        }

        -- Override default select to jump to location
        actions.select_default:replace(function()
          cleanup_notes()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if entry then
            local neocrush = require 'neocrush'
            local target_win = neocrush._find_edit_target_window()

            if target_win then
              vim.api.nvim_set_current_win(target_win)
            else
              vim.cmd 'topleft vnew'
            end

            vim.cmd('edit ' .. vim.fn.fnameescape(entry.filename))
            vim.api.nvim_win_set_cursor(0, { entry.lnum, (entry.col or 1) - 1 })
            vim.cmd 'normal! zz'
          end
        end)

        -- Ctrl-Q: send all to quickfix
        local function send_all_to_qf()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local qf_items = {}
          for _, entry in ipairs(picker.finder.results) do
            table.insert(qf_items, {
              filename = entry.filename,
              lnum = entry.lnum,
              col = entry.col or 1,
              text = (entry.note or '') .. ' | ' .. (entry.text or ''),
              type = entry.type or 'N',
            })
          end
          cleanup_notes()
          actions.close(prompt_bufnr)
          vim.fn.setqflist({}, ' ', { title = title or 'AI Locations', items = qf_items })
          vim.cmd 'copen'
        end

        map('i', '<C-q>', send_all_to_qf)
        map('n', '<C-q>', send_all_to_qf)

        -- Alt-Q: send selected to quickfix
        local function send_selected_to_qf()
          local entry = action_state.get_selected_entry()
          if entry then
            cleanup_notes()
            actions.close(prompt_bufnr)
            vim.fn.setqflist({}, ' ', {
              title = title or 'AI Locations',
              items = {
                {
                  filename = entry.filename,
                  lnum = entry.lnum,
                  col = entry.col or 1,
                  text = (entry.value.note or '') .. ' | ' .. (entry.value.text or ''),
                  type = entry.value.type or 'N',
                },
              },
            })
            vim.cmd 'copen'
          end
        end

        map('i', '<M-q>', send_selected_to_qf)
        map('n', '<M-q>', send_selected_to_qf)

        return true
      end,
    })
    :find()

  -- Initial update after picker opens
  vim.defer_fn(function()
    local entry = action_state.get_selected_entry()
    update_notes_window(entry)
  end, 100)
end

-------------------------------------------------------------------------------
-- Handler
-------------------------------------------------------------------------------

--- Handler for crush/showLocations notification.
---@param err any
---@param params any { title: string, items: LocationItem[] }
---@param ctx any
---@param config any
function M.handler(err, params, ctx, config)
  if err then
    vim.notify('show_locations error: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  if not params or not params.items or #params.items == 0 then
    vim.notify('No locations to show', vim.log.levels.WARN)
    return
  end

  -- Try to use Telescope, fall back to quickfix
  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    M.show_telescope(params.title, params.items)
  else
    M.show_quickfix(params.title, params.items)
  end
end

return M
