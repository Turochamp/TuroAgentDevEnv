# Claude desktop app
winget install -e -h --id Anthropic.Claude --accept-package-agreements --accept-source-agreements

# Claude Code CLI
irm https://claude.ai/install.ps1 | iex
# The installer puts the binary in ~/.local/bin which may not be in PATH yet
$claudeBin = "$env:USERPROFILE\.local\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$claudeBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$claudeBin", "User")
}
$env:Path += ";$claudeBin"

# VS Code is required for the Claude Code extension and works well with Cursor too
choco install -y vscode

# Install the official Claude Code extension in VS Code/Cursor (manual)
# Configure MCP servers and skills in Claude Code settings (manual)
