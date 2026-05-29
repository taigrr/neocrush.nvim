-- neocrush.nvim plugin loader (v2)
--
-- v2 removes the standalone neocrush daemon binary. Crush now talks
-- directly to this Neovim instance over msgpack-rpc using the $NVIM
-- environment variable that Neovim exports into its :terminal jobs.
-- That means there is nothing to install beyond `crush` itself, and
-- multiple (nvim, crush) pairs no longer collide.

if vim.g.loaded_neocrush then
  return
end
vim.g.loaded_neocrush = true

if vim.fn.has 'nvim-0.10' ~= 1 then
  vim.notify('neocrush.nvim requires Neovim >= 0.10', vim.log.levels.ERROR)
  return
end

if vim.fn.executable 'crush' ~= 1 then
  vim.notify(
    'neocrush.nvim: `crush` binary not found in PATH. Install from https://github.com/charmbracelet/crush',
    vim.log.levels.WARN
  )
end
