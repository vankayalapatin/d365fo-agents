# PostToolUse (Claude) / postToolUse (Copilot), on file writes.
# Records every agent write to a work document (tdd, fdd, task, analysis), with the hash of its
# body and the session that wrote it. The gate uses this to tell an agent's edit from the
# user's own edit ("no agent wrote this hash") and from another session's edit. A write to a
# build-log.md records which ticket that agent is building.
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $p = Read-HookInput
    if ($null -eq $p -or (Test-HooksOff)) { exit 0 }
    $n = Get-Normalized $p
    if ($n.Tool -notmatch '^(Write|Edit|MultiEdit|create|edit|write)$') { exit 0 }
    $path = [string](Get-Prop $n.Input @('file_path', 'path', 'filePath'))
    # A build log names the ticket this agent is building: the object gate checks only that one.
    $b = [regex]::Match($path, '(?i)[\\/]d365fo-work[\\/]([^\\/]+)[\\/]build-log\.md$')
    if ($b.Success) {
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $n.Cwd $path }
        $root = Find-ProjectRoot (Split-Path -Parent $path)
        if ($root) { Add-Record $root @{ type = 'build'; session = $n.Session; agentId = $n.AgentId; agent = $n.AgentType; ticket = $b.Groups[1].Value } }
        exit 0
    }
    $m = [regex]::Match($path, '(?i)[\\/]d365fo-work[\\/]([^\\/]+)[\\/](tdd|fdd|task|analysis)\.md$')
    if (-not $m.Success) { exit 0 }
    if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $n.Cwd $path }
    $root = Find-ProjectRoot (Split-Path -Parent $path)
    if (-not $root) { exit 0 }
    $doc = Read-WorkDoc $path
    if (-not $doc) { exit 0 }
    $ticket = $m.Groups[1].Value; $name = $m.Groups[2].Value.ToLowerInvariant()
    Add-Record $root @{ type = 'write'; session = $n.Session; agent = $n.AgentType; file = "d365fo-work/$ticket/$name.md"
        version = $doc.Version; hash = $doc.BodyHash }
    exit 0
} catch {
    [Console]::Error.WriteLine("d365fo record hook error: $($_.Exception.Message)")
    exit 0
}
