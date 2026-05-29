---@brief [[
--- neocrush.lsp - DEPRECATED in v2.
---
--- v1 of neocrush spoke LSP/MCP through a separate `neocrush` daemon
--- binary. v2 replaces that with direct msgpack-rpc to this Neovim
--- instance via $NVIM. The daemon is gone; the lua module that drove it
--- is gone.
---
--- This file is kept only as a compatibility shim so user configs that
--- still call `require('neocrush').start_lsp()` or `get_client()` don't
--- break loudly. They'll get a one-time deprecation notice and
--- otherwise become no-ops. Removed in a future release.
---@brief ]]

local M = {}

local notified = false

---No-op deprecation shim. Returns nil to satisfy the v1 signature.
---@param _opts? table
---@return nil
function M.start_lsp(_opts)
  if not notified then
    notified = true
    vim.notify(
      'neocrush.nvim v2: the LSP/daemon layer was removed. Crush now talks to this nvim '
        .. 'directly via $NVIM. start_lsp() is a no-op and will be deleted in a future release.',
      vim.log.levels.WARN
    )
  end
  return nil
end

---No-op deprecation shim.
---@return nil
function M.get_client()
  return nil
end

---v2 setup wires the command-side autocmds (terminal, cursor sync) and
---initializes highlight defaults. The bridge module is loaded
---on-demand by Crush via nvim_exec_lua, so there is nothing to start
---here.
---@param cfg neocrush.Config
---@param opts? { auto_focus_check?: fun(): boolean }
function M.setup(cfg, opts)
  local highlight = require 'neocrush.highlight'
  highlight.setup(cfg, opts)
end

return M
