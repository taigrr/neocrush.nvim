---@brief [[
--- neocrush.nvim health check
--- Run with :checkhealth neocrush
---@brief ]]

local M = {}

function M.check()
  vim.health.start 'neocrush.nvim'

  -- Check Neovim version
  if vim.fn.has 'nvim-0.10' == 1 then
    vim.health.ok 'Neovim >= 0.10'
  else
    vim.health.error('Neovim >= 0.10 required', { 'Upgrade Neovim to 0.10 or later' })
  end

  -- Check neocrush binary
  if vim.fn.executable 'neocrush' == 1 then
    local version = vim.fn.system('neocrush --version 2>/dev/null'):gsub('%s+$', '')
    if version ~= '' then
      vim.health.ok('neocrush binary found: ' .. version)
    else
      vim.health.ok 'neocrush binary found'
    end
  else
    vim.health.error('neocrush binary not found', {
      'Install with :CrushInstallBinaries (requires Go)',
      'Or manually: go install github.com/taigrr/neocrush/cmd/neocrush@latest',
      'See: https://github.com/taigrr/neocrush',
    })
  end

  -- Check crush CLI
  if vim.fn.executable 'crush' == 1 then
    local version = vim.fn.system('crush --version 2>/dev/null'):gsub('%s+$', '')
    if version ~= '' then
      vim.health.ok('crush CLI found: ' .. version)
    else
      vim.health.ok 'crush CLI found'
    end
  else
    vim.health.error('crush CLI not found', {
      'Install with :CrushInstallBinaries (requires Go)',
      'Or manually: go install github.com/charmbracelet/crush@latest',
      'See: https://github.com/charmbracelet/crush',
    })
  end

  -- Check Go (required for installation)
  if vim.fn.executable 'go' == 1 then
    local go_version = vim.fn.system('go version'):gsub('%s+$', '')
    vim.health.ok('Go found: ' .. go_version)
  else
    vim.health.warn('Go not found (required for :CrushInstallBinaries/:CrushUpdateBinaries)', {
      'Install from: https://go.dev/dl/',
    })
  end

  -- Check LSP client status
  local clients = vim.lsp.get_clients { name = 'neocrush' }
  if #clients > 0 then
    vim.health.ok 'neocrush LSP client running'
  else
    if vim.fn.executable 'neocrush' == 1 then
      vim.health.info 'neocrush LSP client not running (starts on VimEnter or BufEnter)'
    else
      vim.health.info 'neocrush LSP client not running (binary not installed)'
    end
  end
end

return M
