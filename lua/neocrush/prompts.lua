---@brief [[
--- Custom prompt injection for neocrush.nvim
--- Allows users to define prompt templates that get sent to the Crush terminal
---@brief ]]

local M = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

---@type table<string, neocrush.Prompt>
local prompts = {}

-------------------------------------------------------------------------------
-- Types
-------------------------------------------------------------------------------

---@class neocrush.Prompt
---@field template string The prompt template (use %s for argument substitution)
---@field desc? string Description for the command
---@field nargs? string|integer Number of arguments ('?', '*', '+', 0, 1, etc.)

---@class neocrush.PromptsConfig
---@field prompts? table<string, neocrush.Prompt|string> Map of command suffix to prompt config

-------------------------------------------------------------------------------
-- Core
-------------------------------------------------------------------------------

--- Send text to the Crush terminal.
--- Opens the terminal if not already open, then sends the text.
---@param text string The text to send
---@param focus? boolean Whether to focus the terminal after sending (default: true)
function M.send(text, focus)
  local terminal = require 'neocrush.terminal'

  -- Get the terminal buffer/channel
  local crush_buf = terminal._get_buf and terminal._get_buf()

  -- If terminal not running, open it first
  if not crush_buf or not vim.api.nvim_buf_is_valid(crush_buf) then
    terminal.open()
    -- Wait a bit for terminal to initialize, then send
    vim.defer_fn(function()
      local buf = terminal._get_buf and terminal._get_buf()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local chan = vim.bo[buf].channel
        if chan and chan ~= 0 then
          vim.api.nvim_chan_send(chan, text)
        end
      end
    end, 100)
    return
  end

  local term_chan = vim.bo[crush_buf].channel
  if term_chan == 0 then
    vim.notify('Crush terminal channel not found', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_chan_send(term_chan, text)

  if focus ~= false then
    terminal.focus()
  end
end

--- Execute a prompt by name with optional arguments.
---@param name string The prompt name (command suffix)
---@param args? string Arguments to substitute into the template
function M.execute(name, args)
  local prompt = prompts[name]
  if not prompt then
    vim.notify('Unknown Crush prompt: ' .. name, vim.log.levels.ERROR)
    return
  end

  local template = type(prompt) == 'string' and prompt or prompt.template
  local text

  if args and args ~= '' then
    -- Substitute %s with arguments, or append if no %s
    if template:find '%%s' then
      text = template:gsub('%%s', args)
    else
      text = template .. ' ' .. args
    end
  else
    -- Remove any %s placeholders if no args provided
    text = template:gsub('%%s', ''):gsub('%s+$', '')
  end

  M.send(text)
end

--- Register prompts and create user commands.
---@param prompt_config table<string, neocrush.Prompt|string>
function M.register(prompt_config)
  for name, config in pairs(prompt_config) do
    prompts[name] = config

    local prompt_def = type(config) == 'string' and { template = config } or config
    local cmd_name = 'Crush' .. name

    -- Determine nargs
    local nargs = prompt_def.nargs
    if nargs == nil then
      -- Auto-detect: if template has %s, default to '?', else '0'
      nargs = prompt_def.template:find '%%s' and '?' or 0
    end

    vim.api.nvim_create_user_command(cmd_name, function(opts)
      M.execute(name, opts.args)
    end, {
      nargs = nargs,
      desc = prompt_def.desc or ('Crush prompt: ' .. name),
    })
  end
end

--- List all registered prompts.
---@return table<string, neocrush.Prompt|string>
function M.list()
  return vim.deepcopy(prompts)
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

---@param config? neocrush.PromptsConfig
function M.setup(config)
  if config and config.prompts then
    M.register(config.prompts)
  end
end

return M
