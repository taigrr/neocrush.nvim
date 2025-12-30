-- crush-lsp.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is loaded

if vim.g.loaded_crush_lsp then
  return
end
vim.g.loaded_crush_lsp = true

-- Minimum Neovim version check
if vim.fn.has 'nvim-0.10' ~= 1 then
  vim.notify('crush-lsp.nvim requires Neovim >= 0.10', vim.log.levels.ERROR)
  return
end

-- Check if crush-lsp binary is available
if vim.fn.executable 'crush-lsp' ~= 1 then
  vim.notify('crush-lsp binary not found in PATH. Install it from: https://github.com/taigrr/crush-lsp', vim.log.levels.WARN)
end
