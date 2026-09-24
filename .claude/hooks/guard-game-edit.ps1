# PreToolUse guard for Edit/Write/NotebookEdit: denies any file_path inside the installed game folder.
# The gameRoot pattern must stay in sync with guard-game.ps1.
$ErrorActionPreference = 'Stop'

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch { exit 0 }
$path = [string]$payload.tool_input.file_path
if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$payload.tool_input.notebook_path }
if ([string]::IsNullOrWhiteSpace($path)) { exit 0 }

$gameRoot = '(?i)(\b[a-z]:[\\/]+games?([\\/]|$)|steamapps|[\\/]Lord of Mysteries([\\/]|$))'

if ($path -match $gameRoot) {
    @{ hookSpecificOutput = @{
        hookEventName = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = "AGENTS.md section 1: writing into the game folder is forbidden ($path)"
    } } | ConvertTo-Json -Depth 4 -Compress
}
exit 0
