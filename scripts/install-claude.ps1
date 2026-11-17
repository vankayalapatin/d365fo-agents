<#
.SYNOPSIS
  Installs the d365fo agents for Claude Code — the desktop app's Code tab or the terminal.
  No plugin install and no command-line tool needed.

.DESCRIPTION
  1. Copies claude/.claude/agents/d365fo-*.md and claude/.claude/skills/d365fo-*/ into
     <RepoPath>/.claude/ — or, with -User, into your user folder (~/.claude/), so they work in
     every repo and none of them sit inside your D365 repo. Only d365fo-* files are added or
     replaced; nothing else is touched.
     Also installs the hooks (approval stamps and write gates, src/hooks/README.md) into
     <dest>/hooks/d365fo/ and merges them into <dest>/settings.json: a backup
     (settings.json.bak) is written first, only d365fo hook entries are replaced, everything
     else is kept. -SkipHooks leaves them out; -RemoveHooks takes only them out again.
     -Uninstall removes the d365fo agents, skills and hooks from <dest> (approval stamps and
     .mcp.json are kept).
  Steps 2 and 3 need -RepoPath.
  2. Adds a "microsoft-learn" server to <RepoPath>/.mcp.json if it is not there yet (backup:
     .mcp.json.bak). Existing servers are kept.
  3. Copies the d365fo-mcp-server rules to <RepoPath>/CLAUDE.md if that file does not exist
     (pass -McpInstructionsPath; never overwrites an existing CLAUDE.md).

  Then open a Claude Code session on <RepoPath> and type /d365fo-architect with your ticket.
  Run scripts/build.ps1 first if you changed anything in src/.

.EXAMPLE
  ./scripts/install-claude.ps1 -RepoPath <D365 repo> -McpInstructionsPath <d365fo-mcp-server>/.github/copilot-instructions.md
.EXAMPLE
  ./scripts/install-claude.ps1 -User -RepoPath <D365 repo>     # agents at user level, MCP config in the repo
.EXAMPLE
  ./scripts/install-claude.ps1 -User -Uninstall                # remove agents, skills and hooks
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RepoPath,
    [switch] $User,
    [string] $McpInstructionsPath,
    [switch] $SkipMcpConfig,
    [switch] $SkipHooks,
    [switch] $RemoveHooks,
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude/.claude'
if (-not $Uninstall -and -not (Test-Path (Join-Path $src 'skills'))) { throw "No generated Claude files found. Run scripts/build.ps1 first." }
if (-not $User -and -not $RepoPath) { throw "Pass -RepoPath <D365 repo>, or -User to install at user level." }
if ($RepoPath -and -not (Test-Path $RepoPath)) { throw "Repo path not found: $RepoPath" }
$dest = if ($User) { Join-Path $HOME '.claude' } else { Join-Path $RepoPath '.claude' }

# 1. agents and skills -------------------------------------------------------------------
$agentDest = Join-Path $dest 'agents'
$skillDest = Join-Path $dest 'skills'
if ($Uninstall) {
    $gone = 0
    foreach ($item in @(Get-ChildItem -Path $agentDest -Filter 'd365fo-*.md' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $skillDest -Filter 'd365fo-*' -Directory -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove')) { Remove-Item -Recurse -Force $item.FullName; $gone++ }
    }
    Write-Host "Removed $gone d365fo agents and skills from $dest" -ForegroundColor Green
    $RemoveHooks = $true
} elseif (-not $RemoveHooks) {
    if (-not (Test-Path $agentDest)) { New-Item -ItemType Directory -Force -Path $agentDest | Out-Null }
    # Remove d365fo agents that no longer exist in the build (e.g. renamed or now shipped as a skill).
    $current = @(Get-ChildItem -Path (Join-Path $src 'agents') -Filter 'd365fo-*.md' -File | ForEach-Object Name)
    Get-ChildItem -Path $agentDest -Filter 'd365fo-*.md' -File | Where-Object { $_.Name -notin $current } | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove stale agent')) { Remove-Item $_.FullName -Force }
    }
    foreach ($f in Get-ChildItem -Path (Join-Path $src 'agents') -Filter 'd365fo-*.md' -File) {
        if ($PSCmdlet.ShouldProcess((Join-Path $agentDest $f.Name), 'Copy')) { Copy-Item $f.FullName $agentDest -Force }
    }

    if (-not (Test-Path $skillDest)) { New-Item -ItemType Directory -Force -Path $skillDest | Out-Null }
    $skills = @(Get-ChildItem -Path (Join-Path $src 'skills') -Directory -Filter 'd365fo-*')
    foreach ($d in $skills) {
        $target = Join-Path $skillDest $d.Name
        if ($PSCmdlet.ShouldProcess($target, 'Replace skill')) {
            if (Test-Path $target) { Remove-Item -Recurse -Force $target }
            Copy-Item -Recurse $d.FullName $target
        }
    }
    Write-Host "Installed $($current.Count) agents and $($skills.Count) skills into $dest" -ForegroundColor Green
}

# 1b. hooks: scripts into <dest>/hooks/d365fo, entries merged into <dest>/settings.json -------
# Merge, never overwrite: a backup is written first, only entries whose command points at
# hooks/d365fo/ are replaced or removed, and every other setting and hook is kept.
$hookSrc = Join-Path $src 'hooks/d365fo'
$hookDest = Join-Path $dest 'hooks/d365fo'
$settingsPath = Join-Path $dest 'settings.json'
function Test-OurGroup($group) {
    foreach ($h in @($group.hooks)) {
        $cmdText = ([string]$h.command) + ' ' + ((@($h.PSObject.Properties | Where-Object Name -eq 'args' | ForEach-Object { $_.Value }) | ForEach-Object { $_ }) -join ' ')
        if ($cmdText -match 'hooks[\\/]d365fo[\\/]') { return $true }
    }
    return $false
}
function Update-HookSettings([switch] $Remove) {
    $cfg = $null
    if (Test-Path $settingsPath) { $cfg = Get-Content -Raw -Encoding UTF8 $settingsPath | ConvertFrom-Json }
    if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }
    if (-not ($cfg.PSObject.Properties.Name -contains 'hooks')) { $cfg | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    # drop our old entries
    foreach ($ev in @($cfg.hooks.PSObject.Properties | ForEach-Object { $_.Name })) {
        $kept = @($cfg.hooks.$ev | Where-Object { -not (Test-OurGroup $_) })
        if ($kept.Count) { $cfg.hooks.$ev = $kept } else { $cfg.hooks.PSObject.Properties.Remove($ev) }
    }
    if (-not $Remove) {
        $dirFwd = $hookDest -replace '\\', '/'
        $frag = (Get-Content -Raw -Encoding UTF8 (Join-Path $hookSrc 'settings-fragment.json')).Replace('{HOOKS_DIR}', $dirFwd) | ConvertFrom-Json
        foreach ($ev in @($frag.hooks.PSObject.Properties | ForEach-Object { $_.Name })) {
            $has = @($cfg.hooks.PSObject.Properties | ForEach-Object { $_.Name }) -contains $ev
            $existing = @(); if ($has) { $existing = @($cfg.hooks.$ev) }
            $merged = @($existing) + @($frag.hooks.$ev)
            if ($has) { $cfg.hooks.$ev = $merged } else { $cfg.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue $merged }
        }
    }
    if (-not @($cfg.hooks.PSObject.Properties).Count) { $cfg.PSObject.Properties.Remove('hooks') }
    if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak" -Force }
    [System.IO.File]::WriteAllText($settingsPath, ($cfg | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))
}
if ($RemoveHooks) {
    if ($PSCmdlet.ShouldProcess($settingsPath, 'Remove d365fo hooks')) {
        if (Test-Path $settingsPath) { Update-HookSettings -Remove }
        if (Test-Path $hookDest) { Remove-Item -Recurse -Force $hookDest }
        Write-Host "Removed the d365fo hooks from $settingsPath (backup: settings.json.bak). Approval stamps in ~/.claude/d365fo-stamps are kept." -ForegroundColor Green
    }
} elseif (-not $SkipHooks -and (Test-Path $hookSrc)) {
    if ($PSCmdlet.ShouldProcess($settingsPath, 'Install and merge d365fo hooks')) {
        if (Test-Path $hookDest) { Remove-Item -Recurse -Force $hookDest }
        New-Item -ItemType Directory -Force -Path $hookDest | Out-Null
        Get-ChildItem -Path $hookSrc -File | Where-Object Name -ne 'settings-fragment.json' | Copy-Item -Destination $hookDest
        Update-HookSettings
        Write-Host "Installed the d365fo hooks into $hookDest and merged them into $settingsPath (backup: settings.json.bak if it existed)." -ForegroundColor Green
    }
}

if ($Uninstall -or $RemoveHooks) { return }
if (-not $RepoPath) {
    Write-Host "No -RepoPath given: skipped .mcp.json and CLAUDE.md. The repo needs 'd365fo-mcp-tools' and 'microsoft-learn' in its .mcp.json."
    return
}

# 2. Microsoft Learn MCP server in .mcp.json ---------------------------------------------
if (-not $SkipMcpConfig) {
    $mcpPath = Join-Path $RepoPath '.mcp.json'
    $cfg = $null
    if (Test-Path $mcpPath) { $cfg = Get-Content -Raw -Encoding UTF8 $mcpPath | ConvertFrom-Json }
    if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }
    if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers')) { $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    if ($cfg.mcpServers.PSObject.Properties.Name -contains 'microsoft-learn') {
        Write-Host "microsoft-learn is already in $mcpPath"
    } elseif ($PSCmdlet.ShouldProcess($mcpPath, 'Add microsoft-learn MCP server')) {
        if (Test-Path $mcpPath) { Copy-Item $mcpPath "$mcpPath.bak" -Force }
        $cfg.mcpServers | Add-Member -NotePropertyName 'microsoft-learn' -NotePropertyValue ([pscustomobject]@{ type = 'http'; url = 'https://learn.microsoft.com/api/mcp' })
        $json = $cfg | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($mcpPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Added microsoft-learn to $mcpPath (backup: .mcp.json.bak)" -ForegroundColor Green
    }
    if (-not ($cfg.mcpServers.PSObject.Properties.Name -contains 'd365fo-mcp-tools')) {
        Write-Warning "No 'd365fo-mcp-tools' server in $mcpPath. The agents call the d365fo MCP server by that name - register it there or in your user config."
    }
}

# 3. server rules as CLAUDE.md -------------------------------------------------------------
$claudeMd = Join-Path $RepoPath 'CLAUDE.md'
if (Test-Path $claudeMd) {
    Write-Host "CLAUDE.md already exists in $RepoPath - not changed. Make sure it includes the d365fo-mcp-server rules."
} elseif ($McpInstructionsPath) {
    if (-not (Test-Path $McpInstructionsPath)) { throw "Not found: $McpInstructionsPath" }
    if ($PSCmdlet.ShouldProcess($claudeMd, 'Copy d365fo-mcp-server rules')) {
        Copy-Item $McpInstructionsPath $claudeMd
        Write-Host "Copied the d365fo-mcp-server rules to $claudeMd" -ForegroundColor Green
    }
} else {
    Write-Warning "No CLAUDE.md in $RepoPath. Pass -McpInstructionsPath <d365fo-mcp-server>/.github/copilot-instructions.md to install the server's rules."
}

Write-Host @"
Next: open a Claude Code session on $RepoPath (desktop app Code tab, or 'claude' in a terminal there),
approve the project MCP servers if asked, then type:  /d365fo-architect <paste your ticket>
"@
