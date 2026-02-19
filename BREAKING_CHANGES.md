# Breaking Changes

## v2.0.0

### Removed: `:CrushInstall` and `:CrushUpdate` commands

Binary management is now handled by [glaze.nvim](https://github.com/taigrr/glaze.nvim).

**Migration:**

1. Add `glaze.nvim` as a dependency:

```lua
{
  'taigrr/neocrush.nvim',
  dependencies = { 'taigrr/glaze.nvim' },
}
```

2. Use glaze commands for binary management:
   - `:GlazeInstall neocrush` / `:GlazeInstall crush` — Install binaries
   - `:GlazeUpdate neocrush` / `:GlazeUpdate crush` — Update binaries

3. For version-specific installs, use the Crush Version Manager:
   - `:CrushCvmReleases` — Browse and install from GitHub releases
   - `:CrushCvmLocal [path]` — Build from local repository checkout
