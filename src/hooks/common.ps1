# Shared code for the d365fo hooks. Dot-sourced by every hook script.
# Windows PowerShell 5.1 and PowerShell 7. No modules, no network.
#
# The hooks enforce the agents' gates mechanically (see src/hooks/README.md):
#   stamp  - records approvals from the user's own typed messages
#   gate   - blocks d365fo writes and builds without a valid stamp, writes to objects outside
#            the TDD or task card, terminal writes to AOT files, and writes to the stamp store
#   record - records every agent write to a work document, so the gate can tell who edited it

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off   # PS 5.1 strict mode has no .Count on single objects

# ---------------------------------------------------------------- payload

function Read-HookInput {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { return $null }
    $p = $raw | ConvertFrom-Json
    Write-PayloadLog $raw
    return $p
}

function Get-Prop($obj, [string[]] $names) {
    if ($null -eq $obj) { return $null }
    foreach ($n in $names) {
        $prop = $obj.PSObject.Properties[$n]
        if ($prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') { return $prop.Value }
    }
    return $null
}

# One shape for Claude (snake_case) and Copilot (camelCase) payloads.
function Get-Normalized($p) {
    $toolInput = Get-Prop $p @('tool_input', 'toolInput', 'toolArgs')
    if ($toolInput -is [string]) { try { $toolInput = $toolInput | ConvertFrom-Json } catch { $toolInput = [pscustomobject]@{ raw = $toolInput } } }
    if ($null -eq $toolInput) { $toolInput = [pscustomobject]@{} }
    $cwd = Get-Prop $p @('cwd')
    if (-not $cwd) { $cwd = $env:CLAUDE_PROJECT_DIR }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    return [pscustomobject]@{
        Session   = [string](Get-Prop $p @('session_id', 'sessionId'))
        Cwd       = [string]$cwd
        Tool      = [string](Get-Prop $p @('tool_name', 'toolName'))
        Input     = $toolInput
        AgentType = [string](Get-Prop $p @('agent_type', 'agentType'))
        AgentId   = [string](Get-Prop $p @('agent_id', 'agentId'))
        Prompt    = [string](Get-Prop $p @('prompt'))
        Transcript = [string](Get-Prop $p @('transcript_path', 'transcriptPath'))
    }
}

# Tool arguments may sit at the top level or nested in `params` (d365fo_file, generate_object).
function Get-Arg($toolInput, [string[]] $names) {
    $v = Get-Prop $toolInput $names
    if ($null -ne $v) { return $v }
    $params = Get-Prop $toolInput @('params')
    if ($params -is [string]) { try { $params = $params | ConvertFrom-Json } catch { $params = $null } }
    return (Get-Prop $params $names)
}

# ---------------------------------------------------------------- stamp store

function Get-StampDir {
    if ($env:D365FO_STAMP_DIR) { $d = $env:D365FO_STAMP_DIR } else { $d = Join-Path $HOME '.claude/d365fo-stamps' }
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return $d
}

function Test-HooksOff { return (Test-Path (Join-Path (Get-StampDir) 'OFF')) }

# Opt-in raw payload log: create the file LOG in the stamp folder yourself to switch it on.
function Write-PayloadLog([string] $raw) {
    try {
        $dir = Get-StampDir
        if (Test-Path (Join-Path $dir 'LOG')) {
            if ($raw.Length -gt 6000) { $raw = $raw.Substring(0, 6000) + '...(cut)' }
            Add-Content -Path (Join-Path $dir 'payload-log.jsonl') -Value ($raw -replace "`r?`n", ' ') -Encoding UTF8
        }
    } catch { }
}

function Get-Hash([string] $text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 32)
}

function Get-StoreFile([string] $root) {
    return Join-Path (Get-StampDir) ((Get-Hash $root.ToLowerInvariant().TrimEnd('\', '/')).Substring(0, 16) + '.jsonl')
}

function Add-Record([string] $root, [hashtable] $rec) {
    $rec['time'] = (Get-Date).ToUniversalTime().ToString('o')
    $line = (New-Object PSObject -Property $rec) | ConvertTo-Json -Compress -Depth 6
    Add-Content -Path (Get-StoreFile $root) -Value $line -Encoding UTF8
}

function Get-Records([string] $root) {
    $f = Get-StoreFile $root
    if (-not (Test-Path $f)) { return @() }
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($f, [System.Text.Encoding]::UTF8)) {
        if ($line.Trim()) { try { $out += ($line | ConvertFrom-Json) } catch { } }
    }
    return $out
}

# ---------------------------------------------------------------- work files

# The project root is the nearest folder (from cwd up) that holds d365fo-work/.
function Find-ProjectRoot([string] $start) {
    $d = $start
    while ($d) {
        if (Test-Path (Join-Path $d 'd365fo-work')) { return $d }
        $parent = Split-Path -Parent $d
        if ($parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

function Read-WorkDoc([string] $path) {
    if (-not (Test-Path $path)) { return $null }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) -replace "`r`n", "`n"
    $meta = @{}; $body = $text
    if ($text.StartsWith("---`n")) {
        $end = $text.IndexOf("`n---", 4)
        if ($end -gt 0) {
            foreach ($l in $text.Substring(4, $end - 4).Split("`n")) {
                if ($l -match '^([A-Za-z][\w-]*):\s*(.*?)\s*(#.*)?$') { $meta[$Matches[1]] = $Matches[2].Trim('"', "'") }
            }
            $body = $text.Substring($end + 4)
            $nl = $body.IndexOf("`n"); if ($nl -ge 0) { $body = $body.Substring($nl + 1) } else { $body = '' }
        }
    }
    # The hash leaves out the Sign-off section (TDD 15, FDD 13): recording the sign-off there
    # must not void the stamp it records. Any other change to the body still does.
    $kept = New-Object System.Collections.Generic.List[string]; $skip = 0
    foreach ($l in $body.Split("`n")) {
        $h = [regex]::Match($l, '^(#{1,6})\s')
        if ($h.Success) {
            $lvl = $h.Groups[1].Value.Length
            if ($skip -and $lvl -le $skip) { $skip = 0 }
            if (-not $skip -and $l -match '(?i)^#{1,6}\s*(\d+\.?\s*)?sign-?\s?off\b') { $skip = $lvl }
        }
        if (-not $skip) { $kept.Add($l.TrimEnd()) }
    }
    $norm = ($kept -join "`n").Trim()
    $version = 0; if ($meta.ContainsKey('version')) { [void][int]::TryParse($meta['version'], [ref]$version) }
    $status = ''; if ($meta.ContainsKey('status')) { $status = $meta['status'] }
    return [pscustomobject]@{ Path = $path; Meta = $meta; Body = $body; Version = $version; Status = $status; BodyHash = (Get-Hash $norm) }
}

function Get-Tickets([string] $root) {
    $w = Join-Path $root 'd365fo-work'
    if (-not (Test-Path $w)) { return @() }
    return @(Get-ChildItem -Path $w -Directory | ForEach-Object { $_.Name })
}

function Get-DocPath([string] $root, [string] $ticket, [string] $doc) { return Join-Path $root "d365fo-work/$ticket/$doc.md" }

# Names in the first Markdown table under a heading that matches $headingRegex.
function Get-TableNames([string] $body, [string] $headingRegex, [string[]] $columns) {
    $names = New-Object System.Collections.Generic.List[string]
    $lines = $body.Split("`n"); $in = $false; $idx = @()
    foreach ($l in $lines) {
        if ($l -match '^#{1,6}\s') { if ($in -and $idx.Count) { break }; $in = ($l -match $headingRegex); $idx = @(); continue }
        if (-not $in) { continue }
        if ($l -notmatch '^\s*\|') { if ($idx.Count) { } ; continue }
        $cells = @($l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (-not $idx.Count) {
            for ($i = 0; $i -lt $cells.Count; $i++) { foreach ($c in $columns) { if ($cells[$i] -match "^(?i)$c") { $idx += $i } } }
            continue
        }
        if ($cells[0] -match '^:?-{2,}') { continue }
        foreach ($i in $idx) {
            if ($i -lt $cells.Count) { foreach ($tok in (Get-ObjectTokens $cells[$i])) { $names.Add($tok) } }
        }
    }
    return @($names | Select-Object -Unique)
}

# AOT object names in a table cell: PascalCase identifiers of 3+ characters, not part of a
# hyphenated word. Drops prose and tool words ("add-module-reference", "form", "en-US").
function Get-ObjectTokens([string] $cell) {
    return @([regex]::Matches($cell, '(?<![\w.-])[A-Z][A-Za-z0-9_]{2,}(\.[A-Za-z0-9_]+)?(?![\w-])') | ForEach-Object { $_.Value })
}

# Only the Name column: base objects and other cells are not objects the change writes.
function Get-TddObjects($doc) { return Get-TableNames $doc.Body '(?i)^#{1,6}\s*4\.?\s*Objects' @('Name\s*$') }
function Get-TaskObjects($doc) { return Get-TableNames $doc.Body '(?i)^#{1,6}\s*Objects' @('Name\s*$') }

# The user's request as written in task.md: the block under "## Request".
function Get-TaskRequest($doc) {
    $m = [regex]::Match($doc.Body, '(?ims)^#{1,6}\s*Request[^\n]*\n(.*?)(?=^#{1,6}\s|\z)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function ConvertTo-Plain([string] $s) {
    if (-not $s) { return '' }
    $s = $s -replace '(?m)^\s*>\s?', '' -replace '[`*_"“”‘’]', '' -replace "'", ''
    return (($s -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

# Is object name $n covered by any of $allowed? Exact, or $n = <allowed> + an extension suffix
# (VendTable.DPExtension, VendTableDP_Extension, VendTable_DP_Extension).
function Test-NameAllowed([string] $n, [string[]] $allowed) {
    if (-not $n) { return $true }
    foreach ($a in $allowed) {
        if (-not $a) { continue }
        if ($n -ieq $a) { return $true }
        # The tool adds the model prefix itself, so the call may name DPFoo as Foo.
        if ($a.Length -gt $n.Length -and $a.EndsWith($n, [System.StringComparison]::OrdinalIgnoreCase) -and
            $a.Substring(0, $a.Length - $n.Length) -cmatch '^[A-Z][A-Za-z0-9]{0,5}$') { return $true }
        if ($n.Length -gt $a.Length -and $n.StartsWith($a, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rest = $n.Substring($a.Length)
            if ($rest -match '^(\.[A-Za-z0-9_]+|_?[A-Za-z0-9]*_Extension)$') { return $true }
        }
        # The call may name an extension by its base object (CustTable for CustTable.DPExtension).
        if ($a.Length -gt $n.Length -and $a.StartsWith($n, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rest = $a.Substring($n.Length)
            if ($rest -match '^(\.[A-Za-z0-9_]*Extension|_?[A-Za-z0-9]*_Extension)$') { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------- tickets and questions

# A ticket named in chat: the full folder name, or its last part(s) ("A1", "eval-a1").
function Resolve-Ticket([string[]] $tickets, [string] $name) {
    if (-not $name -or $name -match '^(?i)(v\d+|tdd|fdd|ch-?\d*|analysis|task|card)$') { return $null }
    $exact = @($tickets | Where-Object { $_ -ieq $name })
    if ($exact.Count -eq 1) { return $exact[0] }
    $tail = @($tickets | Where-Object { $_.EndsWith('-' + $name, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($tail.Count -eq 1) { return $tail[0] }
    return $null
}

# Approval items named in a text: "<ticket> TDD v<n>", "<ticket> FDD", "<ticket> CH-2",
# "<ticket> task card". A document without a ticket in front takes the nearest ticket on its
# line, else the last one named ("approve B9 FDD v1 and TDD v1"), else $defaultTicket.
function Get-NamedItems([string] $text, [string[]] $tickets, [string] $defaultTicket = '') {
    $docWord = '(?i)^(?:''s)?\s+(?:fdd|tdd|analysis|ch-?\d+|change\s+ch-?\d+|task\s+card)\b'
    $items = @(); $carry = ''
    foreach ($line in $text.Split("`n")) {
        # A ticket is named by its full folder name (also inside a path), or by a short name
        # right before a document ("A1 TDD", "hookcheck's TDD"). A plain word that a folder
        # name happens to end with ("field" in "...-rating-field") is not a ticket.
        $mentions = @()
        foreach ($m in [regex]::Matches($line, '(?<![\w-])[A-Za-z0-9][\w-]*')) {
            $exact = @($tickets | Where-Object { $_ -ieq $m.Value })
            if ($exact.Count) { $mentions += [pscustomobject]@{ Pos = $m.Index; Ticket = $exact[0] }; continue }
            if ($line.Substring($m.Index + $m.Length) -match $docWord) {
                $tk = Resolve-Ticket $tickets $m.Value
                if ($tk) { $mentions += [pscustomobject]@{ Pos = $m.Index; Ticket = $tk } }
            }
        }
        $rx = '(?i)\b(?:(?<doc>fdd|tdd|analysis)\b(?:\s*(?:v|version\s*)(?<v>\d+))?|(?:change\s+)?CH-?(?<ch>\d+)\b|(?<task>task\s+card)\b)'
        foreach ($m in [regex]::Matches($line, $rx)) {
            # The nearest ticket before it on the line, else the one after it on the line
            # ("TDD v1 ... file: d365fo-work/<ticket>/tdd.md"), else the last ticket named.
            $before = @($mentions | Where-Object { $_.Pos -lt $m.Index }) | Select-Object -Last 1
            $after = @($mentions | Where-Object { $_.Pos -gt $m.Index }) | Select-Object -First 1
            $tk = if ($before) { $before.Ticket } elseif ($after) { $after.Ticket } elseif ($carry) { $carry } else { $defaultTicket }
            if (-not $tk) { continue }
            $carry = $tk
            if ($m.Groups['doc'].Success) { $it = [pscustomobject]@{ Ticket = $tk; Doc = $m.Groups['doc'].Value.ToLowerInvariant(); Version = $(if ($m.Groups['v'].Success) { [int]$m.Groups['v'].Value } else { 0 }); Ch = '' } }
            elseif ($m.Groups['ch'].Success) { $it = [pscustomobject]@{ Ticket = $tk; Doc = 'tdd'; Version = 0; Ch = 'CH-' + $m.Groups['ch'].Value } }
            else { $it = [pscustomobject]@{ Ticket = $tk; Doc = 'task'; Version = 0; Ch = '' } }
            $items += $it
        }
    }
    # One item per document; a named version wins over a bare "tdd.md".
    $out = @()
    foreach ($g in ($items | Group-Object { "$($_.Ticket)|$($_.Doc)|$($_.Ch)" })) {
        $out += @(@($g.Group | Sort-Object Version -Descending) | Select-Object -First 1)
    }
    return $out
}

# The assistant's last turn in a Claude transcript (JSONL): its question lines, and the labels of
# the reply buttons it offered. Reads only the end of the file.
function Get-LastTurn([string] $path) {
    $out = [pscustomobject]@{ Lines = @(); Labels = @() }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $out }
    $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $max = 4MB; $start = [Math]::Max(0, $fs.Length - $max)
        [void]$fs.Seek($start, 'Begin')
        $buf = New-Object byte[] ($fs.Length - $start)
        $read = 0; while ($read -lt $buf.Length) { $r = $fs.Read($buf, $read, $buf.Length - $read); if ($r -le 0) { break }; $read += $r }
    } finally { $fs.Close() }
    $lines = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read).Split("`n")
    if ($start -gt 0) { if ($lines.Count -gt 1) { $lines = $lines[1..($lines.Count - 1)] } else { $lines = @() } }
    $texts = New-Object System.Collections.Generic.List[string]; $seen = $false
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if (-not $l -or ($l -notmatch '"type"\s*:\s*"(assistant|user)"')) { continue }
        try { $e = $l | ConvertFrom-Json } catch { continue }
        if ($e.isSidechain -eq $true -or -not $e.message) { continue }
        $content = $e.message.content
        if ($e.type -eq 'user') {
            $isResult = $content -isnot [string] -and @($content | Where-Object { $_.type -eq 'tool_result' }).Count
            if ($seen -and -not $isResult) { break }   # the prompt before the last turn
            continue
        }
        if ($e.type -ne 'assistant') { continue }
        $seen = $true
        foreach ($b in @($content)) {
            if ($b -is [string]) { $texts.Insert(0, $b); continue }
            if ($b.type -eq 'text' -and $b.text) { $texts.Insert(0, [string]$b.text) }
            elseif ($b.type -eq 'tool_use' -and $b.input) {
                foreach ($k in 'ask', 'question') { $v = Get-Prop $b.input @($k); if ($v) { $texts.Insert(0, ([string]$v) + '?') } }
                foreach ($q in @(Get-Prop $b.input @('questions'))) { if ($q -and $q.question) { $texts.Insert(0, "$($q.question)?") } }
                foreach ($a in @(Get-Prop $b.input @('actions'))) { if ($a -and $a.label) { $out.Labels += [string]$a.label } }
            }
        }
    }
    # Only lines that ask: a question, or one that names an approval or sign-off.
    $out.Lines = @(($texts -join "`n").Split("`n") | Where-Object { $_ -match '(?i)\?|approv|sign[- ]?off|\bgo\b' })
    return $out
}

# Leading <system-reminder> blocks the app puts in front of the user's own words.
function Remove-LeadingReminders([string] $s) {
    $t = $s.TrimStart()
    while ($t -match '^(?s)<system-reminder>.*?</system-reminder>') { $t = $t.Substring($Matches[0].Length).TrimStart() }
    return $t
}

function Get-Words([string] $text) { return @([regex]::Matches($text, '[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)?') | ForEach-Object { $_.Value } | Select-Object -Unique) }

# ---------------------------------------------------------------- output

function Exit-Block([string] $reason) {
    [Console]::Error.WriteLine("d365fo gate: $reason")
    exit 2
}

function Write-Note([string] $text) { [Console]::Out.WriteLine("d365fo hooks: $text") }
