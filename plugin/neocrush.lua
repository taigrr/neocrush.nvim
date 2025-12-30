-- neocrush.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is loaded

if vim.g.loaded_crush_lsp then
  return
end
vim.g.loaded_crush_lsp = true

-- Minimum Neovim version check
if vim.fn.has 'nvim-0.10' ~= 1 then
  vim.notify('neocrush.nvim requires Neovim >= 0.10', vim.log.levels.ERROR)
  return
end

-- Check if neocrush binary is available
if vim.fn.executable 'neocrush' ~= 1 then
  vim.notify('neocrush binary not found in PATH. Install it from: https://github.com/taigrr/neocrush', vim.log.levels.WARN)
end
