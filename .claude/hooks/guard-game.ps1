# PreToolUse guard for the PowerShell tool.
# Blocks commands that modify the installed game (D:\Games\..., D:\Game\..., steamapps, "Lord of Mysteries\"),
# launch the patcher/installer/game, or force-push. Reading and copying FROM the game folder stays allowed.
$ErrorActionPreference = 'Stop'

function Deny([string]$reason) {
    @{ hookSpecificOutput = @{
        hookEventName = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = "AGENTS.md sections 1-2: $reason"
    } } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch { exit 0 }
$cmd = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

$gameRoot   = '(?i)(\b[a-z]:[\\/]+games?([\\/]|$)|steamapps|[\\/]Lord of Mysteries([\\/]|$))'
$launchName = '(?i)(PatcherEngine|Lord-of-Mysteries-Russian-Patch)(\.exe|\.ps1)?$|(^|[\\/])Install\.bat$|GMZZLauncher|^steam://'
$writeVerbs = '^(remove-item|rm|del|erase|rd|rmdir|ri|move-item|mv|move|mi|rename-item|ren|rni|set-content|sc|add-content|ac|out-file|clear-content|clc|new-item|ni|mkdir|md|set-itemproperty|sp|expand-archive|tar|set-acl|takeown|icacls|attrib)$'
$copyVerbs  = '^(copy-item|cp|copy|cpi|robocopy|xcopy)$'
$startVerbs = '^(start-process|saps|start|invoke-item|ii|cmd|cmd\.exe|powershell|powershell\.exe|pwsh|explorer|explorer\.exe)$'

$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)

# Variables assigned a game path in the same command ($g = 'D:\Games\LOTM') count as game paths.
$gameVars = @{}
foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    if ($a.Right.Extent.Text -match $gameRoot -and $a.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $gameVars[$a.Left.VariablePath.UserPath.ToLower()] = $true
    }
}

function Test-Game($elementAst) {
    if ($null -eq $elementAst) { return $false }
    if ($elementAst.Extent.Text -match $gameRoot) { return $true }
    foreach ($v in $elementAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        if ($gameVars.ContainsKey($v.VariablePath.UserPath.ToLower())) { return $true }
    }
    return $false
}

function Get-Text($elementAst) {
    if ($elementAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $elementAst.Value }
    if ($elementAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $elementAst.Value }
    return $elementAst.Extent.Text
}

foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $elements = @($c.CommandElements)
    $head = $elements[0]
    $name = (Get-Text $head).Trim('"', "'")
    $nameLower = $name.ToLower()
    $leaf = ($nameLower -split '[\\/]')[-1]
    $cargs = @($elements | Select-Object -Skip 1)

    # Launching the patcher, installer, launcher or anything from the game folder
    if ($name -match $launchName) { Deny "launching the patcher/installer/launcher is forbidden ($name)" }
    if (Test-Game $head) { Deny "running programs from the game folder is forbidden ($name)" }
    if ($leaf -match $startVerbs) {
        foreach ($a in $cargs) {
            $t = Get-Text $a
            if ($t -match $launchName -or (Test-Game $a)) { Deny "starting the game, launcher or installer is forbidden ($t)" }
        }
    }

    # Force push
    if ($leaf -eq 'git' -and $cargs.Count -gt 0 -and (Get-Text $cargs[0]) -eq 'push') {
        foreach ($a in $cargs) {
            $t = Get-Text $a
            if ($t -match '^(--force(-with-lease)?(=.*)?|-f|--mirror|--delete|-d)$' -or $t -match '^\+') {
                Deny "force-push / remote deletion requires an explicit request from the user ($t)"
            }
        }
    }

    # File-modifying cmdlets aimed at the game folder
    if ($leaf -match $writeVerbs) {
        foreach ($a in $cargs) { if (Test-Game $a) { Deny "modifying the game folder is forbidden ($name $($a.Extent.Text))" } }
    }
    if ($leaf -match $copyVerbs) {
        # Copying FROM the game is allowed; only the destination matters.
        $positional = @()
        for ($i = 0; $i -lt $cargs.Count; $i++) {
            $a = $cargs[$i]
            if ($a -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($a.ParameterName -match '^(destination|dest|d)$') {
                    $val = if ($a.Argument) { $a.Argument } elseif ($i + 1 -lt $cargs.Count) { $cargs[$i + 1] } else { $null }
                    if (Test-Game $val) { Deny "copying INTO the game folder is forbidden" }
                    if (-not $a.Argument) { $i++ }
                } elseif ($a.ParameterName -match '^(path|literalpath|filter|include|exclude)$' -and -not $a.Argument) {
                    $i++
                }
                continue
            }
            $positional += $a
        }
        if ($positional.Count -ge 2 -and (Test-Game $positional[1])) { Deny "copying INTO the game folder is forbidden" }
    }

    # Redirection into the game folder (> / >>)
    foreach ($r in $c.Redirections) {
        if ($r -is [System.Management.Automation.Language.FileRedirectionAst] -and (Test-Game $r.Location)) {
            Deny "redirecting output into the game folder is forbidden"
        }
    }
}

# .NET file APIs: [IO.File]::WriteAllText('D:\Games\...'), [IO.Directory]::Delete(...), etc.
foreach ($m in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
    $member = $m.Member.Extent.Text.Trim('"', "'")
    $margs = @($m.Arguments)
    if ($member -match '^(Copy|Move)') {
        if ($margs.Count -ge 2 -and (Test-Game $margs[1])) { Deny ".NET copy/move into the game folder is forbidden" }
        if ($member -match '^Move' -and $margs.Count -ge 1 -and (Test-Game $margs[0])) { Deny ".NET move out of the game folder is forbidden" }
    } elseif ($member -match '^(Write|Append|Delete|Create|Replace|SetAttributes|SetLastWriteTime|SetCreationTime|SetAccessControl|Encrypt|Decrypt|OpenWrite)|^Open$') {
        foreach ($a in $margs) { if (Test-Game $a) { Deny ".NET write to the game folder is forbidden ($member)" } }
    }
}

exit 0
