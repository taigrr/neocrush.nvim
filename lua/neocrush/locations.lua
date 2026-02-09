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

--- Show locations in custom Telescope picker with 3 panes.
---@param title string Title for the picker
---@param items table[] Location items with filename, lnum, text, note
function M.show_telescope(title, items)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local previewers = require 'telescope.previewers'

  -- Store items for note display
  local items_by_display = {}

  pickers
    .new({}, {
      prompt_title = title or 'AI Locations',
      layout_strategy = 'vertical',
      layout_config = {
        height = 0.9,
        width = 0.9,
        preview_height = 0.5,
        preview_cutoff = 10,
      },
      finder = finders.new_table {
        results = items,
        entry_maker = function(item)
          local display = string.format('%s:%d', item.filename, item.lnum)
          items_by_display[display] = item
          return {
            value = item,
            display = display,
            ordinal = display .. ' ' .. (item.text or '') .. ' ' .. (item.note or ''),
            filename = item.filename,
            lnum = item.lnum,
            col = item.col or 1,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'Preview',
        define_preview = function(self, entry, status)
          -- Show file preview in main preview area
          conf.file_previewer({}):preview(entry, status)
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        -- Override default select to jump to location
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if entry then
            vim.cmd('edit ' .. vim.fn.fnameescape(entry.filename))
            vim.api.nvim_win_set_cursor(0, { entry.lnum, (entry.col or 1) - 1 })
            vim.cmd 'normal! zz'
          end
        end)

        -- Ctrl-Q: send all to quickfix
        local function send_all_to_qf()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local qf_items = {}
          for _, entry in ipairs(current_picker.finder.results) do
            table.insert(qf_items, {
              filename = entry.filename,
              lnum = entry.lnum,
              col = entry.col or 1,
              text = (entry.note or '') .. ' | ' .. (entry.text or ''),
              type = entry.type or 'N',
            })
          end
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

  -- Create floating window for AI notes that updates on selection change
  vim.defer_fn(function()
    M._setup_notes_display(items_by_display)
  end, 100)
end

-------------------------------------------------------------------------------
-- Notes Display (Floating Window)
-------------------------------------------------------------------------------

--- Setup floating window to display AI notes for selected item.
---@param items_by_display table Map of display strings to items
function M._setup_notes_display(items_by_display)
  local notes_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[notes_buf].buftype = 'nofile'
  vim.bo[notes_buf].filetype = 'markdown'

  local notes_win = nil
  local last_display = nil

  -- Create autocmd group for cleanup
  local group = vim.api.nvim_create_augroup('NeocrushNotesDisplay', { clear = true })

  -- Function to update notes window
  local function update_notes()
    -- Find the Telescope prompt buffer
    local prompt_bufnr = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'TelescopePrompt' then
        prompt_bufnr = buf
        break
      end
    end

    if not prompt_bufnr then
      -- Telescope closed, cleanup
      if notes_win and vim.api.nvim_win_is_valid(notes_win) then
        vim.api.nvim_win_close(notes_win, true)
      end
      vim.api.nvim_del_augroup_by_id(group)
      return
    end

    -- Get current selection from Telescope
    local ok, action_state = pcall(require, 'telescope.actions.state')
    if not ok then
      return
    end

    local picker = action_state.get_current_picker(prompt_bufnr)
    if not picker then
      return
    end

    local entry = action_state.get_selected_entry()
    if not entry then
      return
    end

    local display = entry.display
    if display == last_display then
      return
    end
    last_display = display

    local item = items_by_display[display]
    if not item then
      return
    end

    -- Update notes buffer content
    local lines = {}
    table.insert(lines, '## Why this matters')
    table.insert(lines, '')
    for line in (item.note or 'No note provided'):gmatch '[^\n]+' do
      table.insert(lines, line)
    end
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '`' .. item.filename .. ':' .. item.lnum .. '`')

    vim.api.nvim_buf_set_lines(notes_buf, 0, -1, false, lines)

    -- Create or update floating window at bottom
    local ui = vim.api.nvim_list_uis()[1]
    local width = math.floor(ui.width * 0.88)
    local height = 6

    local opts = {
      relative = 'editor',
      width = width,
      height = height,
      col = math.floor((ui.width - width) / 2),
      row = ui.height - height - 2,
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

  -- Update on cursor movement and mode changes
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    callback = update_notes,
  })

  -- Initial update
  vim.defer_fn(update_notes, 50)
end

-------------------------------------------------------------------------------
-- Handler
-------------------------------------------------------------------------------

--- Handler for crush/showLocations notification.
---@param err any
---@param params any { title: string, items: LocationItem[] }
---@param ctx any
---@param conf any
function M.handler(err, params, ctx, conf)
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
