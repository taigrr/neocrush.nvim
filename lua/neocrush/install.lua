---@brief [[
--- neocrush.nvim binary utilities
--- Simple helpers for checking binary availability.
--- Binary installation is handled by glaze.nvim (general) or CVM (crush versions).
---@brief ]]

local M = {}

--- Check if a binary is installed and executable.
---@param name string Binary name
---@return boolean
function M.is_installed(name)
  return vim.fn.executable(name) == 1
end

return M
