# PreToolUse (Claude) / preToolUse (Copilot). Blocks with exit 2 and a reason on stderr.
#
#   1. Stamp store   - no model write to the stamp folder (Write/Edit or terminal).
#   2. AOT files     - no Write/Edit, and no terminal write/copy/move/delete, of .xml/.xpp under
#                      Metadata or PackagesLocalDirectory. Reads pass.
#   3. Work docs     - no terminal writes to tdd/fdd/task/analysis.md (use Write/Edit, which the
#                      record hook logs, so the gate can tell who changed a document).
#   4. Write gate    - d365fo_file create/modify/delete/undo/project, labels create/update/rename
#                      and build_d365fo_project need a valid stamp: the current TDD body approved
#                      by the user (or changed by the user's own instruction), or a stamped task.
#   5. Object gate   - d365fo_file only on objects in the Name column of TDD section 4, or named
#                      in the task request, the approved task card, or "approve object X".
#                      Only the ticket being built counts (the last build-log.md this agent
#                      wrote); stamps from every session count.
# Gates 4-5 apply to d365fo-* subagents and to sessions started with /d365fo-architect.
. (Join-Path $PSScriptRoot 'common.ps1')

$failClosed = $false
try {
    $p = Read-HookInput
    if ($null -eq $p -or (Test-HooksOff)) { exit 0 }
    $n = Get-Normalized $p
    $tool = $n.Tool
    $in = $n.Input
    $isCopilot = [bool]$p.PSObject.Properties['toolName']

    $kind = ''
    if ($tool -match '^(Write|Edit|MultiEdit|NotebookEdit|create|edit|write)$') { $kind = 'file' }
    elseif ($tool -match '^(Bash|PowerShell|bash|powershell|shell)$' -or $tool -match 'run_in_terminal$') { $kind = 'terminal' }
    elseif ($tool -match '(^|__|/)(d365fo_file|labels|build_d365fo_project)$') { $kind = 'd365fo'; $tail = $Matches[2] }
    if (-not $kind) { exit 0 }

    $aotPath = '(?i)[\\/](Metadata|PackagesLocalDirectory)[\\/]'
    $stampMsg = "The approval store is written only by the hooks, from the user's own messages. Ask the user."

    # ---------------------------------------------------------------- 1-2: file tools
    if ($kind -eq 'file') {
        $path = [string](Get-Prop $in @('file_path', 'path', 'notebook_path', 'filePath'))
        if ($path -match '(?i)d365fo-stamps') { Exit-Block $stampMsg }
        if ($path -match '(?i)\.(xml|xpp)$' -and $path -match $aotPath) {
            Exit-Block "AOT files (.xml/.xpp under Metadata) are written only through the d365fo MCP tool d365fo_file. Stop and report; do not work around it."
        }
        exit 0
    }

    # ---------------------------------------------------------------- 1-3: terminal
    if ($kind -eq 'terminal') {
        $c = [string](Get-Prop $in @('command', 'cmd', 'script', 'raw'))
        if (-not $c) { exit 0 }
        $s = $c -replace '<[^<>\s]+@[^<>\s]+>', ' '   # e-mail addresses (a commit's Co-Authored-By line)
        if ($s -match '(?i)\bgit\s+commit\b|\bgh\s+(pr|issue|release)\b') {
            # A commit message or PR body is text, not a command: drop heredoc bodies and -m strings.
            $s = [regex]::Replace($s, "(?s)<<-?\s*['""]?(\w+)['""]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", ' ')
            $s = [regex]::Replace($s, '(?s)(-m|--message|--body|--title)\s+("[^"]*"|''[^'']*'')', ' ')
        }
        $s = $s -replace '(?i)\d?>\s*(\$null|/dev/null|nul)\b', ' ' -replace '\d>&\d', ' '
        # A redirect is a '>' outside quotes: grep -o "<tag>[^<]*" is a read, not a write.
        $unquoted = [regex]::Replace($s, '"[^"]*"|''[^'']*''', ' ')
        $redirect = $unquoted -match '(?<![<>=\-])>{1,2}(?!=)'
        $writeVerb = '(?i)(\b(Set-Content|Add-Content|Clear-Content|Out-File|Copy-Item|Move-Item|Remove-Item|Rename-Item|New-Item|Tee-Object|cpi|mi|ri|rni|cp|mv|rm|rmdir|rd|del|erase|copy|xcopy|robocopy|move|ren|rename|tee|truncate|mklink)\b|\bsed\s+(-[a-z]*\s+)*-i|\bperl\s+-[a-z]*i|::(Write|Append|Copy|Move|Delete|Replace|Create)|\.(Write|Save|Delete|MoveTo|CopyTo)\w*\(|\bgit\s+(checkout|restore|rm|mv|reset|clean|apply|stash|switch|merge|rebase|pull|cherry-pick)\b|\b(python3?|py|node|ruby|perl)\b)'
        if ($redirect -or $s -match $writeVerb) {
            # Reads of the stamp folder (ls, cat, grep) pass; any write near it is blocked.
            if ($s -match '(?i)d365fo-stamps') { Exit-Block $stampMsg }
            if ($s -match '(?i)(Metadata|PackagesLocalDirectory)' -and ($s -match '(?i)\.(xml|xpp)\b' -or $s -match '(?i)-Recurse|\*|\brm\s+-[a-z]*r|\bgit\s')) {
                Exit-Block "Terminal writes, copies, moves and deletes of AOT files under Metadata are blocked; reads are allowed. Use d365fo_file, or stop and report."
            }
            if ($s -match '(?i)d365fo-work[\\/]+[^\\/\s''"]+[\\/]+(tdd|fdd|task|analysis)\.md') {
                Exit-Block "Change work documents with the Write/Edit tools, not the terminal, so the hooks can record who changed them."
            }
        }
        exit 0
    }

    # ---------------------------------------------------------------- 4-5: d365fo writes and builds
    $action = [string](Get-Arg $in @('action'))
    if ($tail -eq 'labels' -and $action -notmatch '^(?i)(create|update|rename|delete)$') { exit 0 }
    if ($tail -eq 'd365fo_file' -and $action -match '^(?i)generate$') { exit 0 }

    $root = Find-ProjectRoot $n.Cwd
    if (-not $root) { $root = $n.Cwd }
    $records = @(Get-Records $root)
    $inScope = ($n.AgentType -match '(^|:)d365fo-') -or
               (@($records | Where-Object { $_.type -eq 'run' -and $_.session -eq $n.Session }).Count -gt 0) -or
               ($isCopilot -and (Test-Path (Join-Path $root 'd365fo-work')))
    if (-not $inScope) { exit 0 }
    $failClosed = $true

    # Object names this call writes (none for builds, labels and project-level operations).
    $names = @()
    if ($tail -eq 'd365fo_file') {
        $objType = [string](Get-Arg $in @('objectType'))
        $op = [string](Get-Arg $in @('operation'))
        $exempt = ($objType -match '(?i)label|descriptor|^model$') -or ($op -match '(?i)module-reference') -or
                  ($action -match '^(?i)project$' -and $op -notmatch '(?i)object')
        if (-not $exempt) {
            foreach ($v in @((Get-Arg $in @('objectName')), (Get-Arg $in @('name')))) { if ($v) { $names += [string]$v } }
            $fp = [string](Get-Arg $in @('filePath', 'path'))
            if ($fp) { $names += [System.IO.Path]::GetFileNameWithoutExtension($fp) }
            $names = @($names | Select-Object -Unique)
        }
    }
    $what = if ($tail -eq 'build_d365fo_project') { 'build' } elseif ($tail -eq 'labels') { "label $action" } else { "d365fo_file $action" }

    # The ticket being built: the last build log this agent (or this session's main
    # conversation) wrote. Only that ticket's approval counts for its writes. Unknown (no build
    # log yet): every approved ticket counts.
    $build = @($records | Where-Object { $_.type -eq 'build' -and $_.session -eq $n.Session -and "$($_.agentId)" -eq $n.AgentId }) | Select-Object -Last 1
    $tickets = @(Get-Tickets $root)
    if ($build) { $tickets = @($tickets | Where-Object { $_ -eq $build.ticket }) }

    # ---- pass 1: authorisations that hold as they are. Every valid stamp in the project counts,
    # whichever session the user typed it in.
    $auths = @()
    foreach ($tk in $tickets) {
        $task = Read-WorkDoc (Get-DocPath $root $tk 'task')
        if ($task) {
            $allowed = @(); $ok = $false
            $reqPlain = ConvertTo-Plain (Get-TaskRequest $task)
            foreach ($r in @($records | Where-Object { $_.type -eq 'task' })) {
                if ($r.plain -and $reqPlain.Contains($r.plain)) {
                    $allowed += @(Get-Words $r.request)
                    $allowed += @($records | Where-Object { $_.type -eq 'object' -and $_.time -gt $r.time } | ForEach-Object { $_.name })
                    $ok = $true; break
                }
            }
            # The user's "go" on the task card: the objects it listed when they approved it.
            $card = @($records | Where-Object { $_.type -eq 'stamp' -and $_.ticket -eq $tk -and $_.doc -eq 'task' }) | Select-Object -Last 1
            if ($card) { $allowed += @($card.objects); $ok = $true }
            if ($ok) { $auths += [pscustomobject]@{ Ticket = $tk; Kind = 'task'; Allowed = @($allowed) } }
        }
        $tdd = Read-WorkDoc (Get-DocPath $root $tk 'tdd')
        if ($tdd -and $tdd.Status -ne 'superseded') {
            $st = @($records | Where-Object { $_.type -eq 'stamp' -and $_.ticket -eq $tk -and $_.doc -eq 'tdd' -and $_.bodyHash -eq $tdd.BodyHash }) | Select-Object -Last 1
            if ($st) { $auths += [pscustomobject]@{ Ticket = $tk; Kind = 'tdd'; Allowed = @(Get-TddObjects $tdd) } }
        }
    }
    $use = $auths

    function Test-Covered($auth) {
        foreach ($nm in $names) { if (-not (Test-NameAllowed $nm $auth.Allowed)) { return $false } }
        return $true
    }
    foreach ($a in $use) { if (Test-Covered $a) { exit 0 } }

    # ---- pass 2: a TDD approved earlier whose body has changed since
    $stamped = @($records | Where-Object { $_.type -eq 'stamp' -and $_.doc -eq 'tdd' -and $_.ticket -in $tickets })
    $order = @($stamped | Sort-Object time -Descending | ForEach-Object { $_.ticket } | Select-Object -Unique)
    $changed = @()
    foreach ($tk in $order) {
        if (@($use | Where-Object { $_.Ticket -eq $tk -and $_.Kind -eq 'tdd' }).Count) { continue }
        $tdd = Read-WorkDoc (Get-DocPath $root $tk 'tdd')
        if (-not $tdd -or $tdd.Status -eq 'superseded') { continue }
        $objs = @(Get-TddObjects $tdd)
        $ok = $true; foreach ($nm in $names) { if (-not (Test-NameAllowed $nm $objs)) { $ok = $false } }
        if ($ok) { $changed += [pscustomobject]@{ Ticket = $tk; Doc = $tdd; Objects = $objs } }
    }

    if (-not $changed.Count) {
        if ($use.Count -and $names.Count) {
            Exit-Block "$($names -join ', ') is not in TDD section 4 or the task card of $(($use | ForEach-Object { $_.Ticket } | Select-Object -Unique) -join ', '). Do not write it: ask the user or the architect."
        }
        $forTicket = if ($build) { " for $($build.ticket) (the ticket in your build log)" } else { '' }
        Exit-Block "No approval stamp for this $what$forTicket. The user has not approved its current TDD or task. Stop and ask the user, naming it ('Approve <ticket> TDD v<n>?'); never record a sign-off yourself."
    }

    $c = $changed[0]; $tk = $c.Ticket; $tdd = $c.Doc
    $last = @($stamped | Where-Object { $_.ticket -eq $tk } | Sort-Object time) | Select-Object -Last 1

    # (a) a user instruction typed after the last approval, quoted in a changes.md row
    $chPath = Get-DocPath $root $tk 'changes'
    if (Test-Path $chPath) {
        $words = @($records | Where-Object { $_.type -eq 'words' -and $_.time -gt $last.time })
        foreach ($row in ([System.IO.File]::ReadAllText($chPath, [System.Text.Encoding]::UTF8) -split "`n" | Where-Object { $_ -match '^\s*\|\s*CH-\d+' })) {
            $ch = [regex]::Match($row, 'CH-\d+').Value
            foreach ($q in [regex]::Matches($row, '["“]([^"”]{8,})["”]')) {
                $qp = ConvertTo-Plain $q.Groups[1].Value
                $hit = @($words | Where-Object { $_.plain.Contains($qp) }) | Select-Object -Last 1
                if (-not $hit) { continue }
                $new = @($c.Objects | Where-Object { -not (Test-NameAllowed $_ @($last.objects)) })
                $unnamed = @($new | Where-Object { -not (Test-NameAllowed $_ (Get-Words $hit.text)) -and -not (Test-NameAllowed ($_ -replace '(\.[A-Za-z0-9_]+|_?[A-Za-z0-9]*_Extension)$', '') (Get-Words $hit.text)) })
                if ($unnamed.Count) {
                    Exit-Block "TDD v$($tdd.Version) of $tk adds $($unnamed -join ', '), which the user's instruction ($ch) does not name. Say so in plain words and ask: 'Approve $tk TDD v$($tdd.Version)?'"
                }
                Add-Record $root @{ type = 'stamp'; session = $n.Session; ticket = $tk; doc = 'tdd'; version = $tdd.Version; bodyHash = $tdd.BodyHash
                    objects = $c.Objects; source = 'typed'; via = "instruction $ch"; words = $hit.text }
                exit 0
            }
        }
    }

    # (b) who changed it?
    $rel = "d365fo-work/$tk/tdd.md"
    $writes = @($records | Where-Object { $_.type -eq 'write' -and $_.file -eq $rel -and $_.hash -eq $tdd.BodyHash })
    $ask = "Approve $tk TDD v$($tdd.Version)?"
    if ($writes.Count -and @($writes | Where-Object { $_.session -eq $n.Session }).Count) {
        Exit-Block "TDD v$($tdd.Version) of $tk was changed by this session's agents after the user approved it, and no user instruction in changes.md covers it. Say what changed in plain words and ask: '$ask' A plain yes stamps it."
    }
    if ($writes.Count) {
        Exit-Block "TDD v$($tdd.Version) of $tk changed after approval; another session ($($writes[-1].session)) wrote it. Say what changed in plain words and ask: '$ask' A plain yes stamps it. Then retry."
    }
    Exit-Block "TDD v$($tdd.Version) of $tk changed after approval, and no agent wrote it. Ask the user: 'The TDD changed outside the agents - was that you? $ask' A plain yes stamps it. Then retry."
} catch {
    if ($failClosed) { Exit-Block "gate error ($($_.Exception.Message)). Stop and ask the user." }
    [Console]::Error.WriteLine("d365fo gate error: $($_.Exception.Message)")
    exit 0
}
