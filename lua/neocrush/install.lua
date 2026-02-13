---@brief [[
--- neocrush.nvim binary installer
--- Installs/updates the neocrush and crush binaries via `go install`.
---@brief ]]

local M = {}

local NEOCRUSH_MODULE = 'github.com/taigrr/neocrush/cmd/neocrush'
local DEFAULT_CRUSH_MODULE = 'github.com/charmbracelet/crush'

--- Resolve the Go module URL for crush using the cvm upstream config.
---@return string url Go module URL for crush
local function get_crush_module()
  local ok, cvm = pcall(require, 'neocrush.cvm')
  if ok then
    local cfg = cvm._get_config()
    if cfg and cfg.upstream then
      return 'github.com/' .. cfg.upstream
    end
  end
  return DEFAULT_CRUSH_MODULE
end

--- Build the binaries table with the current upstream.
---@return table<string, string>
local function get_binaries()
  return {
    neocrush = NEOCRUSH_MODULE,
    crush = get_crush_module(),
  }
end

--- Check if a binary is installed and executable.
---@param name string Binary name
---@return boolean
function M.is_installed(name)
  return vim.fn.executable(name) == 1
end

--- Run `go install` for a binary.
---@param name string Binary name
---@param url string Go module URL
---@private
function M._go_install(name, url)
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('Go is not installed. Please install Go first: https://go.dev/dl/', vim.log.levels.ERROR)
    return
  end

  local install_url = url .. '@latest'
  vim.notify('Installing ' .. name .. '...', vim.log.levels.INFO)

  vim.fn.jobstart({ 'go', 'install', install_url }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify(name .. ' installed successfully', vim.log.levels.INFO)
        else
          vim.notify('Failed to install ' .. name .. '. Check :messages for details.', vim.log.levels.ERROR)
        end
      end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        local msg = table.concat(data, '\n')
        if msg ~= '' then
          vim.schedule(function()
            vim.notify(msg, vim.log.levels.WARN)
          end)
        end
      end
    end,
  })
end

--- Install all binaries (neocrush and crush) if not already installed.
function M.install_all()
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('Go is not installed. Please install Go first: https://go.dev/dl/', vim.log.levels.ERROR)
    return
  end

  local binaries = get_binaries()
  local to_install = {}
  for name, _ in pairs(binaries) do
    if not M.is_installed(name) then
      table.insert(to_install, name)
    end
  end

  if #to_install == 0 then
    vim.notify('All binaries already installed. Use :CrushUpdateBinaries to update.', vim.log.levels.INFO)
    return
  end

  for _, name in ipairs(to_install) do
    M._go_install(name, binaries[name])
  end
end

--- Update all binaries (neocrush and crush) to the latest version.
function M.update_all()
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('Go is not installed. Please install Go first: https://go.dev/dl/', vim.log.levels.ERROR)
    return
  end

  local binaries = get_binaries()
  for name, url in pairs(binaries) do
    M._go_install(name, url)
  end
end

return M
