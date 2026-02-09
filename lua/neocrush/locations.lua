---@brief [[
--- AI-annotated code locations picker for neocrush.nvim
--- Displays locations in Telescope with a notes panel, falls back to quickfix
---@brief ]]

local M = {}

---@class LocationItem
---@field filename string Absolute or relative path to file
---@field lnum integer 1-indexed line number
---@field col? integer 1-indexed column number (default: 1)
---@field text? string Code snippet at this location
---@field note? string AI explanation of why this location is relevant
---@field type? string Quickfix type: N (note), I (info), W (warning), E (error)

---@class ShowLocationsParams
---@field title? string Title for the picker/quickfix list
---@field items LocationItem[] List of locations to display

-------------------------------------------------------------------------------
-- Quickfix Fallback
-------------------------------------------------------------------------------

---Convert LocationItem to quickfix item format.
---@param item LocationItem
---@return table
local function to_qf_item(item)
  local text = item.note or ''
  if item.text and item.text ~= '' then
    text = text .. (text ~= '' and ' | ' or '') .. item.text
  end
  return {
    filename = item.filename,
    lnum = item.lnum,
    col = item.col or 1,
    text = text,
  }
end

---Show locations in quickfix list (fallback when Telescope not available).
---@param title? string Title for the quickfix list
---@param items LocationItem[] Location items
function M.show_quickfix(title, items)
  local qf_items = vim.tbl_map(to_qf_item, items)
  vim.fn.setqflist({}, ' ', { title = title or 'AI Locations', items = qf_items })
  vim.cmd('botright copen')
end

-------------------------------------------------------------------------------
-- Telescope Picker
-------------------------------------------------------------------------------

---@class PickerState
---@field notes_buf integer Buffer for notes window
---@field notes_win? integer Window for notes display
---@field title string Picker title

---Calculate floating window position below Telescope picker.
---@param height integer Desired window height
---@return table Window configuration options
local function calc_notes_win_opts(height)
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.9)
  local telescope_height = math.floor(ui.height * 0.7)
  local telescope_top = math.floor((ui.height - telescope_height) / 2)
  local row = telescope_top + telescope_height + 1

  if row + height > ui.height - 1 then
    row = math.max(0, telescope_top - height - 1)
  end

  return {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((ui.width - width) / 2),
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' AI Context ',
    title_pos = 'center',
  }
end

---Update the notes floating window with entry's note.
---@param state PickerState
---@param entry? table Telescope entry
local function update_notes_window(state, entry)
  if not entry or not entry.value then
    return
  end

  local note = entry.value.note or 'No note provided'
  local lines = vim.split(note, '\n', { plain = true })

  vim.api.nvim_buf_set_lines(state.notes_buf, 0, -1, false, lines)

  local opts = calc_notes_win_opts(6)
  if state.notes_win and vim.api.nvim_win_is_valid(state.notes_win) then
    vim.api.nvim_win_set_config(state.notes_win, opts)
  else
    state.notes_win = vim.api.nvim_open_win(state.notes_buf, false, opts)
    vim.wo[state.notes_win].wrap = true
    vim.wo[state.notes_win].conceallevel = 2
  end
end

---Clean up notes buffer and window.
---@param state PickerState
local function cleanup_notes(state)
  if state.notes_win and vim.api.nvim_win_is_valid(state.notes_win) then
    pcall(vim.api.nvim_win_close, state.notes_win, true)
  end
  if state.notes_buf and vim.api.nvim_buf_is_valid(state.notes_buf) then
    pcall(vim.api.nvim_buf_delete, state.notes_buf, { force = true })
  end
end

---Create entry maker for Telescope finder.
---@param item LocationItem
---@return table
local function make_entry(item)
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
end

---Jump to selected location in appropriate window.
---@param entry table Telescope entry
local function jump_to_location(entry)
  local neocrush = require 'neocrush'
  local target_win = neocrush._find_edit_target_window()

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd 'topleft vnew'
  end

  vim.cmd.edit(vim.fn.fnameescape(entry.filename))
  vim.api.nvim_win_set_cursor(0, { entry.lnum, (entry.col or 1) - 1 })
  vim.cmd 'normal! zz'
end

---Send items to quickfix and open it.
---@param title string Quickfix title
---@param items LocationItem[]
local function send_to_quickfix(title, items)
  local qf_items = vim.tbl_map(to_qf_item, items)
  vim.fn.setqflist({}, ' ', { title = title, items = qf_items })
  vim.cmd('botright copen')
end

---Show locations in custom Telescope picker with notes panel.
---@param title? string Title for the picker
---@param items LocationItem[] Location items
function M.show_telescope(title, items)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  local picker_title = title or 'AI Locations'

  ---@type PickerState
  local state = {
    notes_buf = vim.api.nvim_create_buf(false, true),
    notes_win = nil,
    title = picker_title,
  }
  vim.bo[state.notes_buf].buftype = 'nofile'
  vim.bo[state.notes_buf].filetype = 'markdown'

  ---Wrap movement action to also update notes.
  ---@param move_fn function
  ---@return function
  local function move_and_update(move_fn)
    return function()
      move_fn()
      update_notes_window(state, action_state.get_selected_entry())
    end
  end

  pickers
    .new({}, {
      prompt_title = picker_title,
      layout_strategy = 'horizontal',
      layout_config = {
        height = 0.7,
        width = 0.9,
        preview_width = 0.55,
        prompt_position = 'top',
      },
      finder = finders.new_table {
        results = items,
        entry_maker = make_entry,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.grep_previewer {},
      attach_mappings = function(prompt_bufnr, map)
        local function close_and_cleanup()
          cleanup_notes(state)
          actions.close(prompt_bufnr)
        end

        -- Movement with notes update
        local movements = {
          { 'i', '<Down>', actions.move_selection_next },
          { 'i', '<Up>', actions.move_selection_previous },
          { 'i', '<C-n>', actions.move_selection_next },
          { 'i', '<C-p>', actions.move_selection_previous },
          { 'n', 'j', actions.move_selection_next },
          { 'n', 'k', actions.move_selection_previous },
        }
        for _, m in ipairs(movements) do
          map(
            m[1],
            m[2],
            move_and_update(function()
              m[3](prompt_bufnr)
            end)
          )
        end

        -- Cleanup on close
        actions.close:enhance {
          post = function()
            cleanup_notes(state)
          end,
        }

        -- Select: jump to location
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          close_and_cleanup()
          if entry then
            jump_to_location(entry)
          end
        end)

        -- C-q: send all to quickfix
        local function send_all_to_qf()
          local picker = action_state.get_current_picker(prompt_bufnr)
          close_and_cleanup()
          send_to_quickfix(picker_title, picker.finder.results)
        end
        map('i', '<C-q>', send_all_to_qf)
        map('n', '<C-q>', send_all_to_qf)

        -- M-q: send selected to quickfix
        local function send_selected_to_qf()
          local entry = action_state.get_selected_entry()
          if entry then
            close_and_cleanup()
            send_to_quickfix(picker_title, { entry.value })
          end
        end
        map('i', '<M-q>', send_selected_to_qf)
        map('n', '<M-q>', send_selected_to_qf)

        return true
      end,
    })
    :find()

  -- Initial notes update after picker opens
  vim.defer_fn(function()
    update_notes_window(state, action_state.get_selected_entry())
  end, 100)
end

-------------------------------------------------------------------------------
-- LSP Handler
-------------------------------------------------------------------------------

---Handler for crush/showLocations LSP notification.
---@param err any LSP error (if any)
---@param params ShowLocationsParams Notification parameters
---@param _ any LSP context, config (unused)
function M.handler(err, params, _, _)
  if err then
    vim.notify('show_locations error: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  if not params or not params.items or #params.items == 0 then
    vim.notify('No locations to show', vim.log.levels.WARN)
    return
  end

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    M.show_telescope(params.title, params.items)
  else
    M.show_quickfix(params.title, params.items)
  end
end

return M
