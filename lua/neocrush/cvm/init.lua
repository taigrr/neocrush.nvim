---@brief [[
--- Crush Version Manager for neocrush.nvim
--- Browse and install crush releases from GitHub or build from local repo
---@brief ]]

local M = {}

---@class neocrush.CvmConfig
---@field upstream? string GitHub repo URL for crush releases (owner/repo format)
---@field local_repo? string Default path to local crush repo for :CrushCvmLocal

---@type neocrush.CvmConfig
local default_cvm_config = {
  upstream = 'charmbracelet/crush',
}

---@type neocrush.CvmConfig
local cvm_config = vim.deepcopy(default_cvm_config)

---@type string Go module base URL derived from upstream
local GO_MODULE = 'github.com/charmbracelet/crush'

-------------------------------------------------------------------------------
-- Highlight Groups
-------------------------------------------------------------------------------

--- Set up CVM-specific highlight groups.
local function setup_highlights()
  vim.api.nvim_set_hl(0, 'CrushCvmCurrent', { link = 'DiagnosticOk', default = true })
  vim.api.nvim_set_hl(0, 'CrushCvmHead', { link = 'DiagnosticInfo', default = true })
end

-------------------------------------------------------------------------------
-- Version Detection
-------------------------------------------------------------------------------

---Get the currently installed crush version.
---@param callback fun(version: string|nil) Called with version string (e.g. "v0.42.0") or nil
function M.get_current_version(callback)
  if vim.fn.executable 'crush' ~= 1 then
    callback(nil)
    return
  end

  vim.fn.jobstart({ 'crush', '--version' }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local output = table.concat(data, ''):gsub('%s+$', '')
        local version = output:match '[Vv]?(%d+%.%d+%.%d+[%w%.%-]*)'
        if version then
          callback('v' .. version)
        else
          callback(nil)
        end
      else
        callback(nil)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(nil)
        end)
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- GitHub API
-------------------------------------------------------------------------------

---Fetch releases from GitHub API.
---@param callback fun(releases: table[]|nil, err: string|nil)
function M.fetch_releases(callback)
  local owner_repo = cvm_config.upstream or default_cvm_config.upstream
  local url = string.format('https://api.github.com/repos/%s/releases?per_page=50', owner_repo)
  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart({ 'gh', 'api', url, '--paginate' }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout_data = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr_data = data
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local msg = table.concat(stderr_data, '\n'):gsub('%s+$', '')
          callback(
            nil,
            msg ~= '' and msg or ('gh api exited with code ' .. code .. '. Is `gh` installed and authenticated?')
          )
          return
        end

        local json_str = table.concat(stdout_data, '')
        if json_str == '' then
          callback(nil, 'No data returned from GitHub API')
          return
        end

        local ok, decoded = pcall(vim.json.decode, json_str)
        if ok and type(decoded) == 'table' then
          callback(decoded)
        else
          callback(nil, 'Failed to parse GitHub API response')
        end
      end)
    end,
  })
end

-------------------------------------------------------------------------------
-- Installation
-------------------------------------------------------------------------------

---Install crush at a specific version tag via go install.
---@param tag string Version tag (e.g. "v0.42.0")
function M.install_tag(tag)
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('Go is not installed. Please install Go first: https://go.dev/dl/', vim.log.levels.ERROR)
    return
  end

  local install_url = GO_MODULE .. '@' .. tag
  vim.notify('Installing crush ' .. tag .. '...', vim.log.levels.INFO)

  vim.fn.jobstart({ 'go', 'install', install_url }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify('crush ' .. tag .. ' installed successfully', vim.log.levels.INFO)
        else
          vim.notify('Failed to install crush ' .. tag, vim.log.levels.ERROR)
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

---Install crush from a local repo at a specific commit.
---@param repo_path string Path to local crush repo
---@param commit string Commit hash to install
function M.install_local_commit(repo_path, commit)
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('Go is not installed. Please install Go first: https://go.dev/dl/', vim.log.levels.ERROR)
    return
  end

  vim.notify('Building crush from local repo at ' .. commit:sub(1, 7) .. '...', vim.log.levels.INFO)

  vim.fn.jobstart({ 'git', 'checkout', commit }, {
    cwd = repo_path,
    on_exit = function(_, checkout_code)
      if checkout_code ~= 0 then
        vim.schedule(function()
          vim.notify('Failed to checkout ' .. commit, vim.log.levels.ERROR)
        end)
        return
      end

      vim.fn.jobstart({ 'go', 'install', '.' }, {
        cwd = repo_path,
        on_exit = function(_, install_code)
          vim.schedule(function()
            if install_code == 0 then
              vim.notify('crush built and installed from ' .. commit:sub(1, 7), vim.log.levels.INFO)
            else
              vim.notify('Failed to build crush from local repo', vim.log.levels.ERROR)
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
    end,
  })
end

-------------------------------------------------------------------------------
-- Local Repo Commits
-------------------------------------------------------------------------------

---@class neocrush.LocalCommit
---@field hash string Full commit hash
---@field short_hash string Short commit hash
---@field ref string Branch/tag decoration
---@field tag string|nil Tag name if this commit has one (e.g. "v0.42.0")
---@field timestamp string Commit timestamp
---@field subject string Commit subject line
---@field is_head boolean Whether this is HEAD

---Fetch commits from a local git repo.
---@param repo_path string Path to the repo
---@param callback fun(commits: neocrush.LocalCommit[]|nil, err: string|nil)
function M.fetch_local_commits(repo_path, callback)
  local stdout_lines = {}
  local stderr_lines = {}

  vim.fn.jobstart({ 'git', 'log', '--pretty=format:%H|||%h|||%D|||%ci|||%s', '-100' }, {
    cwd = repo_path,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout_lines = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr_lines = data
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local msg = table.concat(stderr_lines, '\n'):gsub('%s+$', '')
          callback(nil, msg ~= '' and msg or ('git log exited with code ' .. code))
          return
        end

        local commits = {}
        for _, line in ipairs(stdout_lines) do
          if line ~= '' then
            local parts = vim.split(line, '|||', { plain = true })
            if #parts >= 5 then
              local ref = parts[3]
              local is_head = ref:find 'HEAD' ~= nil
              local tag = ref:match 'tag: ([^,]+)'
              local ref_display = ''
              if ref ~= '' then
                ref_display = ref:gsub('HEAD %-> ', ''):gsub(', ', ' ')
              end
              table.insert(commits, {
                hash = parts[1],
                short_hash = parts[2],
                ref = ref_display,
                tag = tag,
                timestamp = parts[4]:sub(1, 19),
                subject = parts[5],
                is_head = is_head,
              })
            end
          end
        end

        if #commits == 0 then
          callback(nil, 'No commits found')
        else
          callback(commits)
        end
      end)
    end,
  })
end

-------------------------------------------------------------------------------
-- Telescope Pickers (delegated to submodules)
-------------------------------------------------------------------------------

---Show Telescope picker for GitHub releases.
function M.pick_releases()
  local has_telescope = pcall(require, 'telescope')
  if not has_telescope then
    vim.notify('telescope.nvim is required for the version picker', vim.log.levels.ERROR)
    return
  end

  setup_highlights()

  M.get_current_version(function(current_version)
    local releases = require 'neocrush.cvm.releases'
    if releases.cache then
      releases.show(releases.cache, current_version, M.install_tag)
      return
    end

    vim.notify('Fetching crush releases...', vim.log.levels.INFO)
    M.fetch_releases(function(release_data, err)
      if err then
        vim.notify('Failed to fetch releases: ' .. err, vim.log.levels.ERROR)
        return
      end
      if not release_data or #release_data == 0 then
        vim.notify('No releases found', vim.log.levels.WARN)
        return
      end

      releases.cache = release_data
      releases.show(release_data, current_version, M.install_tag)
    end)
  end)
end

---Show Telescope picker for local repo commits.
---@param repo_path? string Path to local crush repo (falls back to cvm.local_repo config)
function M.pick_local(repo_path)
  local has_telescope = pcall(require, 'telescope')
  if not has_telescope then
    vim.notify('telescope.nvim is required for the version picker', vim.log.levels.ERROR)
    return
  end

  if not repo_path or repo_path == '' then
    repo_path = cvm_config.local_repo
  end
  if not repo_path or repo_path == '' then
    vim.notify('No repo path given and cvm.local_repo not configured', vim.log.levels.ERROR)
    return
  end

  repo_path = vim.fn.expand(repo_path)
  if vim.fn.isdirectory(repo_path) ~= 1 then
    vim.notify('Not a directory: ' .. repo_path, vim.log.levels.ERROR)
    return
  end

  setup_highlights()
  vim.notify('Loading commits from ' .. repo_path .. '...', vim.log.levels.INFO)

  M.fetch_local_commits(repo_path, function(commits, err)
    if err then
      vim.notify('Failed to fetch commits: ' .. err, vim.log.levels.ERROR)
      return
    end
    if not commits or #commits == 0 then
      vim.notify('No commits found', vim.log.levels.WARN)
      return
    end

    require('neocrush.cvm.local').show(commits, repo_path, M.install_local_commit)
  end)
end

-------------------------------------------------------------------------------
-- Glow Rendering (shared with releases picker)
-------------------------------------------------------------------------------

---@type table<string, string> Cached temp file paths for release notes keyed by tag_name
M._notes_tmpfiles = {}

---@type boolean|nil Whether glow is available (checked once)
local has_glow = nil

---Check if glow is available (cached).
---@return boolean
function M.is_glow_available()
  if has_glow == nil then
    has_glow = vim.fn.executable 'glow' == 1
  end
  return has_glow
end

---Write release body to a temp file (cached per tag).
---@param tag string Release tag (cache key)
---@param markdown string Raw markdown body
---@return string path Temp file path
function M.get_notes_tmpfile(tag, markdown)
  if M._notes_tmpfiles[tag] then
    return M._notes_tmpfiles[tag]
  end
  local tmpfile = vim.fn.tempname() .. '.md'
  vim.fn.writefile(vim.split(markdown, '\n'), tmpfile)
  M._notes_tmpfiles[tag] = tmpfile
  return tmpfile
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

---Configure the CVM module.
---@param opts? neocrush.CvmConfig
function M.setup(opts)
  cvm_config = vim.tbl_deep_extend('force', default_cvm_config, opts or {})
  GO_MODULE = 'github.com/' .. (cvm_config.upstream or default_cvm_config.upstream)
end

-------------------------------------------------------------------------------
-- Test Helpers
-------------------------------------------------------------------------------

---@return neocrush.CvmConfig
M._get_config = function()
  return cvm_config
end

return M
