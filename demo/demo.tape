# neocrush.nvim Demo
# Records the main features of the plugin
#
# Requirements:
#   - vhs (brew install vhs)
#   - nvim >= 0.10
#   - neocrush and crush binaries in PATH
#
# Run locally: make demo
# Run in CI: Uses docker with vhs-action

Output assets/demo.gif

Require nvim
Require crush

Set Shell bash
Set FontSize 14
Set Width 1000
Set Height 600
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set Padding 15
Set TypingSpeed 20ms
Set CursorBlink false

# Hidden setup - create test file and isolate config
Hide
Type "export XDG_CONFIG_HOME=/tmp/vhs-config"
Enter
Type "mkdir -p /tmp/vhs-config/crush /tmp/neocrush-demo && cd /tmp/neocrush-demo"
Enter
Sleep 200ms

# Create minimal crush.json with neocrush MCP server
Type `cat > /tmp/vhs-config/crush/crush.json << 'CRUSHEOF'`
Enter
Type `{"$schema":"https://charm.land/crush.json","lsp":{"*":{"command":"neocrush"}},"mcp":{"neocrush":{"command":"neocrush","type":"stdio"}}}`
Enter
Type "CRUSHEOF"
Enter
Sleep 200ms

Type "echo 'local M = {}' > example.lua"
Enter
Type "echo '' >> example.lua"
Enter
Type "echo 'function M.greet(name)' >> example.lua"
Enter
Type `echo '  print("Hello, " .. name)' >> example.lua`
Enter
Type "echo 'end' >> example.lua"
Enter
Type "echo '' >> example.lua"
Enter
Type "echo 'return M' >> example.lua"
Enter
Sleep 200ms
Type "clear"
Enter
Sleep 200ms

# Start nvim with minimal config
Type `nvim --clean -u $PLUGIN_PATH/scripts/vhs_init.lua --cmd "set rtp+=$PLUGIN_PATH" example.lua`
Enter
Sleep 2s

Show
# Show file contents
Type "gg"
Sleep 500ms

# Toggle Crush terminal (space + cc)
Type " cc"
Sleep 1500ms

# Enable yolo mode (Ctrl+P then y then Enter)
Ctrl+P
Sleep 120ms
Type "y"
Sleep 120ms
Enter
Sleep 500ms

# Type a prompt to change greet to goodbye
Type@25ms `change the greet function to say "Goodbye, " instead of "Hello, "`
Enter
Sleep 18s

# Exit terminal mode (Ctrl+\) and move to text buffer (Ctrl+W w)
Ctrl+\
Sleep 300ms
Ctrl+W
Type "w"
Sleep 300ms
Type "gg"
Sleep 300ms
Type "V"
Sleep 200ms
Type "2j"
Sleep 500ms

# Use CrushPaste to send selection to Crush (space + cp)
Type " cp"
Sleep 5s

# Hidden cleanup
Hide
Ctrl+\
Sleep 200ms
Type ":qa!"
Enter
Sleep 300ms
