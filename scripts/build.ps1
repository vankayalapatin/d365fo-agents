<#
.SYNOPSIS
  Generates every client format of the d365fo agents from src/.

.DESCRIPTION
  Reads   src/agents/*.md, src/standards/*.md, src/standards/templates/*.md, src/plugin.json,
          src/hooks/events.json and its scripts
  Writes  plugins/d365fo-agents/                one plugin folder for Claude Code AND the
                                                GitHub Copilot app / CLI
            .claude-plugin/plugin.json          Claude manifest
            plugin.json                         Copilot manifest (Agent Plugins 1.0)
            .mcp.json / mcp.json                Microsoft Learn MCP server (Claude / Copilot)
            agents/<name>.md                    Claude subagents
            com.github.copilot/agents/<name>.agent.md   Copilot custom agents
            skills/<name>/SKILL.md              shared standards (both clients)
            hooks/*.ps1, hooks/hooks.json       hooks from src/hooks/ (Claude form)
            hooks.json                          the same hooks, Copilot form (untested)
          .claude-plugin/marketplace.json,      marketplace catalog (one entry), read by Claude
          .github/plugin/marketplace.json       and the GitHub Copilot app
          claude/.claude/agents, skills, hooks  Claude desktop app / Claude Code project install
                                                (the orchestrator ships as a /skill, not an agent)

  Targets: the Claude desktop app and the GitHub Copilot app. In both, the architect runs the
  whole team in one conversation.

  Never edit the generated files; change src/ and run this again. The output is
  deterministic: running it twice gives identical files.

.PARAMETER D365McpServer
  Name the user gives the d365fo MCP server in their MCP config. Upstream docs use
  "d365fo-mcp-tools".

.PARAMETER ForbiddenWords
  Extra words that must not appear in any output (e.g. your own model name). Drive-letter
  paths are always rejected.

.EXAMPLE
  ./scripts/build.ps1
  ./scripts/build.ps1 -ForbiddenWords MyModel,MyPrefix
#>
[CmdletBinding()]
param(
    [string]   $D365McpServer = 'd365fo-mcp-tools',
    [string[]] $ForbiddenWords = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$Root      = Split-Path -Parent $PSScriptRoot
$SrcHooks  = Join-Path $Root 'src/hooks'
$SrcAgents = Join-Path $Root 'src/agents'
$SrcStd    = Join-Path $Root 'src/standards'
$SrcTpl    = Join-Path $SrcStd 'templates'
$PluginDir = Join-Path $Root 'plugins/d365fo-agents'
$ClaudeDir = Join-Path $Root 'claude/.claude'

$LearnServer = 'microsoft-learn'
$LearnUrl    = 'https://learn.microsoft.com/api/mcp'
$LearnTools  = [ordered]@{ 'search' = 'microsoft_docs_search'; 'fetch' = 'microsoft_docs_fetch'; 'code' = 'microsoft_code_sample_search' }

# The d365fo-mcp-server's 22 tools (docs/MCP_TOOLS.md). A name outside this list fails the build.
$D365Tools = @(
    'search', 'get_object_info', 'find_references', 'labels', 'get_knowledge', 'analyze_code',
    'generate_object', 'object_patterns', 'd365fo_file', 'security_info', 'extension_info',
    'validate_object_naming', 'get_workspace_info', 'verify_d365fo_project', 'prepare',
    'validate_code', 'build_d365fo_project', 'run_bp_check', 'run_systest_class',
    'update_symbol_index', 'axdb_sql', 'trace_d365fo'
)

$Errors = New-Object System.Collections.Generic.List[string]
function Add-BuildError([string] $msg) { $script:Errors.Add($msg) }

# ---------------------------------------------------------------- helpers

function Read-Text([string] $path) {
    $t = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return ($t -replace "`r`n", "`n").TrimStart([char]0xFEFF)
}

function Write-Text([string] $path, [string] $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = ($content -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

# Minimal frontmatter reader for our own files: `key: value` and `key: [a, b, c]`.
function Read-Doc([string] $path) {
    $text = Read-Text $path
    if (-not $text.StartsWith("---`n")) { throw "No frontmatter: $path" }
    $end = $text.IndexOf("`n---", 4)
    if ($end -lt 0) { throw "Unclosed frontmatter: $path" }
    $meta = [ordered]@{}
    foreach ($line in $text.Substring(4, $end - 4).Split("`n")) {
        if ($line -match '^\s*$') { continue }
        if ($line -notmatch '^([A-Za-z][\w-]*):\s*(.*)$') { throw "Bad frontmatter line in ${path}: $line" }
        $key = $Matches[1]; $val = $Matches[2].Trim()
        if ($val.StartsWith('[') -and $val.EndsWith(']')) {
            $inner = $val.Substring(1, $val.Length - 2).Trim()
            $items = @()
            if ($inner) { $items = @($inner.Split(',') | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }) }
            $meta[$key] = $items
        } else {
            $meta[$key] = $val.Trim('"', "'")
        }
    }
    $body = $text.Substring($end + 4).TrimStart("`n")
    return [pscustomobject]@{ Path = $path; Meta = $meta; Body = $body }
}

function ConvertTo-YamlString([string] $s) { return '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }

# Tiny JSON writer (stable output on Windows PowerShell 5.1 and PowerShell 7).
function ConvertTo-StableJson($value, [int] $indent = 0) {
    $pad = '  ' * $indent; $pad2 = '  ' * ($indent + 1)
    if ($null -eq $value) { return 'null' }
    if ($value -is [string]) {
        $e = $value -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`t", '\t'
        return '"' + $e + '"'
    }
    if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
    if ($value -is [int] -or $value -is [long] -or $value -is [double]) { return [string]$value }
    if ($value -is [System.Collections.IDictionary]) {
        if ($value.Count -eq 0) { return '{}' }
        $parts = foreach ($k in $value.Keys) { $pad2 + (ConvertTo-StableJson ([string]$k)) + ': ' + (ConvertTo-StableJson $value[$k] ($indent + 1)) }
        return "{`n" + ($parts -join ",`n") + "`n$pad}"
    }
    if ($value -is [System.Collections.IEnumerable]) {
        $arr = @($value)
        if ($arr.Count -eq 0) { return '[]' }
        $parts = foreach ($v in $arr) { $pad2 + (ConvertTo-StableJson $v ($indent + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n$pad]"
    }
    throw "Unsupported JSON value: $value"
}

function ConvertTo-Ordered($obj) {
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Ordered $p.Value }
        return $h
    }
    if ($obj -is [System.Array]) { return , @($obj | ForEach-Object { ConvertTo-Ordered $_ }) }
    return $obj
}

# Push every Markdown heading down by $levels, ignoring fenced code.
function Step-Headings([string] $md, [int] $levels) {
    $prefix = '#' * $levels
    $inFence = $false
    $out = foreach ($line in $md.Split("`n")) {
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; $line; continue }
        if (-not $inFence -and $line -match '^#{1,6} ') { $prefix + $line } else { $line }
    }
    return ($out -join "`n")
}

function Get-Generated([string] $source) { return "<!-- GENERATED by scripts/build.ps1 from $source - do not edit; change the source and rebuild. -->" }

# ---------------------------------------------------------------- load sources

$meta = ConvertTo-Ordered (Read-Text (Join-Path $Root 'src/plugin.json') | ConvertFrom-Json)

$Standards = [ordered]@{}
foreach ($f in Get-ChildItem -Path $SrcStd -Filter '*.md' -File | Sort-Object Name) {
    $d = Read-Doc $f.FullName
    foreach ($k in 'name', 'description') { if (-not $d.Meta.Contains($k)) { Add-BuildError "$($f.Name): missing '$k'" } }
    $n = $d.Meta['name']
    if ($n -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $n.Length -gt 64) { Add-BuildError "$($f.Name): skill name '$n' must be lowercase-hyphen, max 64 chars" }
    if ($Standards.Contains($n)) { Add-BuildError "Duplicate skill name '$n'" }
    $d | Add-Member -NotePropertyName Source -NotePropertyValue ("src/standards/" + $f.Name)
    $Standards[$n] = $d
}

# Templates become one extra skill so every client can reach them.
$tplFiles = @(Get-ChildItem -Path $SrcTpl -Filter '*.md' -File | Sort-Object Name)
$tplBody = "# Work file templates`n`nCopy the matching template when you create a work file in ``d365fo-work/<ticket-id>/``. " +
           "Replace every ``<...>`` placeholder; keep the headings and the frontmatter keys.`n"
$fence = '````'   # four backticks: templates may contain their own fences
foreach ($t in $tplFiles) {
    $tplBody += "`n## templates/$($t.Name)`n`n" + $fence + 'markdown' + "`n" + (Read-Text $t.FullName).TrimEnd("`n") + "`n" + $fence + "`n"
}
$Standards['d365fo-templates'] = [pscustomobject]@{
    Path = $SrcTpl; Source = 'src/standards/templates/'
    Meta = [ordered]@{ name = 'd365fo-templates'; description = 'File templates the d365fo agents fill in: analysis, assessment, FDD, TDD, task card, changes, build log, review and QA. Use whenever a d365fo agent creates or updates a work file.' }
    Body = $tplBody
}

$Agents = @()
foreach ($f in Get-ChildItem -Path $SrcAgents -Filter '*.md' -File | Sort-Object Name) {
    $d = Read-Doc $f.FullName
    $m = $d.Meta
    foreach ($k in 'name', 'description', 'role', 'tools', 'skills') { if (-not $m.Contains($k)) { Add-BuildError "$($f.Name): missing '$k'" } }
    foreach ($k in $m.Keys) { if ($k -notin 'name', 'description', 'role', 'tools', 'skills', 'model', 'inline') { Add-BuildError "$($f.Name): unknown frontmatter key '$k'" } }
    if ($m.Contains('model') -and $m['model'] -notin 'sonnet', 'opus', 'haiku', 'fable', 'inherit') { Add-BuildError "$($f.Name): unknown model '$($m['model'])'" }
    if ($m.Contains('inline') -and $m['role'] -ne 'orchestrator') { Add-BuildError "$($f.Name): 'inline' is only for the orchestrator" }
    foreach ($s in @($m['inline'])) { if ($s -and $s -notin @($m['skills'])) { Add-BuildError "$($f.Name): inline skill '$s' is not in skills" } }
    if ($m['name'] + '.md' -ne $f.Name) { Add-BuildError "$($f.Name): name '$($m['name'])' must match the file name" }
    if ($m['role'] -notin 'orchestrator', 'specialist', 'worker') { Add-BuildError "$($f.Name): unknown role '$($m['role'])'" }
    foreach ($t in @($m['tools'])) {
        $ok = ($t -in 'read', 'edit', 'agent') -or
              ($t -match '^d365fo/(.+)$' -and $Matches[1] -in $D365Tools) -or
              ($t -match '^mslearn/(.+)$' -and $LearnTools.Contains($Matches[1]))
        if (-not $ok) { Add-BuildError "$($f.Name): unknown tool '$t'" }
    }
    # Templates are not preloaded: each agent gets only the templates its prompt names (appended
    # by the build; the orchestrator reads them as files on demand).
    $skills = @($m['skills'])
    foreach ($s in $skills) { if (-not $Standards.Contains($s)) { Add-BuildError "$($f.Name): unknown skill '$s'" } }
    $d | Add-Member -NotePropertyName Skills -NotePropertyValue $skills
    $d | Add-Member -NotePropertyName Source -NotePropertyValue ("src/agents/" + $f.Name)
    $Agents += $d
}
if (@($Agents | Where-Object { $_.Meta['role'] -eq 'orchestrator' }).Count -ne 1) { Add-BuildError "Exactly one agent must have role 'orchestrator'" }
foreach ($a in $Agents) {
    foreach ($ref in [regex]::Matches($a.Body, 'templates/[a-z-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique) {
        if (-not (Test-Path (Join-Path $SrcStd $ref))) { Add-BuildError "$($a.Meta['name']): references missing $ref" }
    }
}
$usedSkills = @($Agents | ForEach-Object { $_.Skills } | Sort-Object -Unique)
foreach ($s in $Standards.Keys) { if ($s -notin $usedSkills -and $s -ne 'd365fo-templates') { Write-Warning "Standard '$s' is not used by any agent" } }
foreach ($a in $Agents) {
    if ($a.Meta['role'] -ne 'orchestrator' -and 'edit' -in @($a.Meta['tools']) -and -not [regex]::IsMatch($a.Body, 'templates/[a-z-]+\.md')) {
        Add-BuildError "$($a.Meta['name']): has the edit tool but names no templates/<name>.md to write"
    }
    foreach ($mk in [regex]::Matches($a.Body, '<!-- on-demand: ([^|]+?)\s*\|\s*(.+?) -->\n## ')) {
        if ($a.Meta['role'] -ne 'orchestrator') { Add-BuildError "$($a.Meta['name']): on-demand sections are only for the orchestrator" }
    }
    if ($a.Meta['role'] -eq 'orchestrator' -and ([regex]::Matches($a.Body, '<!-- on-demand:').Count -ne [regex]::Matches($a.Body, '<!-- on-demand: [^|]+?\s*\|\s*.+? -->\n## ').Count)) {
        Add-BuildError "$($a.Meta['name']): every '<!-- on-demand: <file> | <when> -->' marker must sit right above a '## ' heading"
    }
}

# Hooks: src/hooks/events.json lists each hook once; the scripts are shared by both clients.
$HookTools = [ordered]@{
    'd365fo-write' = '^mcp__.+__(d365fo_file|labels|build_d365fo_project)$'
    'terminal'     = '^(Bash|PowerShell)$|^mcp__.+__run_in_terminal$'
    'file-write'   = '^(Write|Edit|MultiEdit|NotebookEdit)$'
}
$HookEvents = [ordered]@{ 'prompt' = @('UserPromptSubmit', 'userPromptSubmitted'); 'pre-tool' = @('PreToolUse', 'preToolUse'); 'post-tool' = @('PostToolUse', 'postToolUse') }
$HookScripts = @('common.ps1')
$HookList = @((Read-Text (Join-Path $SrcHooks 'events.json') | ConvertFrom-Json).hooks)
foreach ($h in $HookList) {
    if (-not $HookEvents.Contains([string]$h.event)) { Add-BuildError "src/hooks/events.json: unknown event '$($h.event)'" }
    if (-not (Test-Path (Join-Path $SrcHooks $h.script))) { Add-BuildError "src/hooks/events.json: missing script '$($h.script)'" }
    if ($h.PSObject.Properties['tools']) {
        foreach ($k in @($h.tools)) { if (-not $HookTools.Contains([string]$k)) { Add-BuildError "src/hooks/events.json: unknown tool kind '$k'" } }
    }
    $HookScripts += $h.script
}

if ($Errors.Count) { $Errors | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }; throw "Build failed: $($Errors.Count) error(s) in src/." }


# ---------------------------------------------------------------- tool mapping

# $LearnStyle: 'plugin' (server bundled in the plugin) or 'project' (server in the repo's .mcp.json).
function Get-ClaudeTools($tools, [string] $LearnStyle) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in $tools) {
        switch -Regex ($t) {
            '^read$'        { 'Read', 'Grep', 'Glob' | ForEach-Object { $out.Add($_) } }
            '^edit$'        { 'Write', 'Edit' | ForEach-Object { $out.Add($_) } }
            '^agent$'       { $out.Add('Agent') }
            '^d365fo/(.+)$' { $out.Add("mcp__$($D365McpServer)__$($Matches[1])") }
            '^mslearn/(.+)$'{
                if ($LearnStyle -eq 'plugin') { $out.Add("mcp__plugin_$($meta['name'])_$($LearnServer)__$($LearnTools[$Matches[1]])") }
                else { $out.Add("mcp__$($LearnServer)__$($LearnTools[$Matches[1]])") }
            }
        }
    }
    return @($out | Select-Object -Unique)
}

function Get-CopilotTools($tools) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in $tools) {
        switch -Regex ($t) {
            '^read$'        { 'read', 'search' | ForEach-Object { $out.Add($_) } }
            '^edit$'        { $out.Add('edit') }
            '^agent$'       { $out.Add('agent') }
            '^d365fo/(.+)$' { $out.Add("$D365McpServer/$($Matches[1])") }
            '^mslearn/(.+)$'{ $out.Add("$LearnServer/$($LearnTools[$Matches[1]])") }
        }
    }
    return @($out | Select-Object -Unique)
}

# Standards may hold blocks only the orchestrator needs:
#   <!-- orchestrator-only --> ... <!-- /orchestrator-only -->
# Helpers' skills drop them; the orchestrator keeps them (markers removed).
$OrchBlock = '(?s)\n?<!-- orchestrator-only -->\n(.*?)\n<!-- /orchestrator-only -->\n?'
function Select-Audience([string] $text, [bool] $orchestrator) {
    if ($orchestrator) { return [regex]::Replace($text, $OrchBlock, { param($m) "`n" + $m.Groups[1].Value + "`n" }) }
    return [regex]::Replace($text, $OrchBlock, "`n")
}
function Get-OrchestratorOnly([string] $text) {
    return (@([regex]::Matches($text, $OrchBlock) | ForEach-Object { $_.Groups[1].Value.Trim() }) -join "`n`n")
}

function Get-TemplateNames([string] $text) {
    return @([regex]::Matches($text, 'templates/([a-z-]+)\.md') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
function Get-TemplateText([string] $n) { return (Read-Text (Join-Path $SrcTpl "$n.md")).TrimEnd("`n") }

# A helper's own work-file templates, appended to its prompt (instead of preloading all of them).
function Get-TemplateSection($agent) {
    $names = @(Get-TemplateNames $agent.Body)
    if (-not $names.Count) { return '' }
    $out = "## Work file templates`n`nCopy the template when you create the file; replace every ``<...>`` placeholder and keep the headings and frontmatter keys.`n"
    foreach ($n in $names) { $out += "`n### templates/$n.md`n`n" + $fence + "markdown`n" + (Get-TemplateText $n) + "`n" + $fence + "`n" }
    return "`n`n" + $out
}

# The orchestrator skill: a small core in SKILL.md, the rest as files next to it that it reads
# when needed (${CLAUDE_SKILL_DIR} is substituted by Claude Code).
#   - sections marked <!-- on-demand: <file> | <when> --> right above their '## ' heading
#   - standards not listed in 'inline'
#   - the templates it names
# Returns @{ Core = <SKILL.md body>; Files = ordered map of relative path -> content }.
function Get-OrchestratorParts($agent) {
    $files = [ordered]@{}
    $gen = Get-Generated $agent.Source
    $core = New-Object System.Collections.Generic.List[string]
    $lines = $agent.Body.Split("`n"); $i = 0; $inFence = $false
    while ($i -lt $lines.Count) {
        $l = $lines[$i]
        if ($l -match '^\s*(```|~~~)') { $inFence = -not $inFence }
        if (-not $inFence -and $l -match '^<!-- on-demand: ([^|]+?)\s*\|\s*(.+?) -->$') {
            $file = $Matches[1]; $when = $Matches[2]; $heading = $lines[$i + 1]
            $sec = New-Object System.Collections.Generic.List[string]; $sec.Add($heading); $i += 2; $f2 = $false
            while ($i -lt $lines.Count) {
                if ($lines[$i] -match '^\s*(```|~~~)') { $f2 = -not $f2 }
                if (-not $f2 -and ($lines[$i] -match '^## ' -or $lines[$i] -match '^<!-- on-demand:')) { break }
                $sec.Add($lines[$i]); $i++
            }
            if ($files.Contains($file)) { Add-BuildError "$($agent.Meta['name']): on-demand file '$file' used twice" }
            $files[$file] = $gen + "`n`n" + (($sec -join "`n").TrimEnd()) + "`n"
            $core.Add($heading); $core.Add('')
            $core.Add("Read ``$('${CLAUDE_SKILL_DIR}')/$file`` $when, and follow it as if it were written here."); $core.Add('')
            continue
        }
        $core.Add($l); $i++
    }
    $body = ($core -join "`n").TrimEnd()

    $inline = @($agent.Meta['inline'])
    $std = "## Standards`n`nThe rules below are referred to by name (for example ``d365fo-grounding`` section 1)."
    $onDemand = @()
    foreach ($s in $agent.Skills) {
        if ($s -in $inline) {
            $std += "`n`n### Standard: $s`n`n" + (Step-Headings (Select-Audience $Standards[$s].Body $true) 3)
        } else {
            $files["standards/$s.md"] = $gen + "`n`n" + (Select-Audience $Standards[$s].Body $true)
            $onDemand += "- ``$s`` — read ``$('${CLAUDE_SKILL_DIR}')/standards/$s.md`` before you apply it. $($Standards[$s].Meta['description'])"
        }
    }
    $allText = $agent.Body
    foreach ($n in Get-TemplateNames $allText) { $files["templates/$n.md"] = Get-TemplateText $n }
    $tplNote = "**Templates.** ``templates/<name>.md`` means ``$('${CLAUDE_SKILL_DIR}')/templates/<name>.md``: read it when you create that file."
    $std = "## Read on demand`n`n$tplNote`n`nStandards not printed below:`n" + ($onDemand -join "`n") + "`n`n" + $std
    return @{ Core = $body + "`n`n" + $std; Files = $files }
}

# ---------------------------------------------------------------- clean generated output

$generated = @(
    (Join-Path $PluginDir 'agents'), (Join-Path $PluginDir 'skills'), (Join-Path $PluginDir 'com.github.copilot'),
    (Join-Path $PluginDir '.claude-plugin/plugin.json'), (Join-Path $PluginDir 'plugin.json'),
    (Join-Path $PluginDir '.mcp.json'), (Join-Path $PluginDir 'mcp.json'),
    (Join-Path $ClaudeDir 'agents'), (Join-Path $ClaudeDir 'skills'),
    (Join-Path $PluginDir 'hooks'), (Join-Path $PluginDir 'hooks.json'), (Join-Path $ClaudeDir 'hooks')
)
foreach ($p in $generated) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }

# ---------------------------------------------------------------- manifests and MCP config

$claudeManifest = [ordered]@{}
foreach ($k in $meta.Keys) { $claudeManifest[$k] = $meta[$k] }
Write-Text (Join-Path $PluginDir '.claude-plugin/plugin.json') (ConvertTo-StableJson $claudeManifest)

$copilotManifest = [ordered]@{ '$schema' = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json' }
foreach ($k in $meta.Keys) { $copilotManifest[$k] = $meta[$k] }
Write-Text (Join-Path $PluginDir 'plugin.json') (ConvertTo-StableJson $copilotManifest)

# Marketplace catalog: one entry, same file in both places the apps look. Copilot checks
# .github/plugin/ before .claude-plugin/; Claude reads .claude-plugin/. Source is repo-relative.
$entry = [ordered]@{ name = $meta['name']; source = './plugins/d365fo-agents' }
foreach ($k in 'description', 'version', 'author', 'homepage', 'repository', 'license', 'keywords') {
    if ($meta.Contains($k)) { $entry[$k] = $meta[$k] }
}
$catalog = ConvertTo-StableJson ([ordered]@{ name = $meta['name']; owner = $meta['author']; plugins = @($entry) })
Write-Text (Join-Path $Root '.claude-plugin/marketplace.json') $catalog
Write-Text (Join-Path $Root '.github/plugin/marketplace.json') $catalog

$learnDef = [ordered]@{ type = 'http'; url = $LearnUrl }
Write-Text (Join-Path $PluginDir '.mcp.json') (ConvertTo-StableJson ([ordered]@{ mcpServers = [ordered]@{ $LearnServer = $learnDef } }))
Write-Text (Join-Path $PluginDir 'mcp.json') (ConvertTo-StableJson ([ordered]@{
    '$schema' = 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json'; mcpServers = [ordered]@{ $LearnServer = $learnDef } }))

# ---------------------------------------------------------------- skills (standards)

foreach ($name in $Standards.Keys) {
    $s = $Standards[$name]
    $fm = "---`nname: $name`ndescription: $(ConvertTo-YamlString $s.Meta['description'])`n---"
    $text = $fm + "`n`n" + (Get-Generated $s.Source) + "`n`n" + (Select-Audience $s.Body $false)
    Write-Text (Join-Path $PluginDir "skills/$name/SKILL.md") $text     # Claude plugin + Copilot plugin
    Write-Text (Join-Path $ClaudeDir "skills/$name/SKILL.md") $text     # Claude project install
}

# ---------------------------------------------------------------- agents

foreach ($a in $Agents) {
    $m = $a.Meta; $name = $m['name']; $gen = Get-Generated $a.Source
    $skillList = $a.Skills
    $desc = ConvertTo-YamlString $m['description']

    if ($m['role'] -eq 'orchestrator') {
        # Claude: the orchestrator must run in the user's own conversation (it asks for sign-offs
        # and starts the other agents), so it ships as a user-invoked skill: /<name> <ticket>.
        $parts = Get-OrchestratorParts $a
        $skill = "---`nname: $name`ndescription: $desc`ndisable-model-invocation: true`n---`n`n$gen`n`n" + $parts.Core
        foreach ($dir in $PluginDir, $ClaudeDir) {
            Write-Text (Join-Path $dir "skills/$name/SKILL.md") $skill
            foreach ($rel in $parts.Files.Keys) { Write-Text (Join-Path $dir "skills/$name/$rel") $parts.Files[$rel] }
        }
    } else {
        # Claude subagent, once per install style (they differ only in Microsoft Learn tool names)
        foreach ($style in 'plugin', 'project') {
            $fm = "---`nname: $name`ndescription: $desc`n" +
                  "tools: " + ((Get-ClaudeTools $m['tools'] $style) -join ', ') + "`n"
            if ($m.Contains('model')) { $fm += "model: $($m['model'])`n" }
            $fm += "skills:`n" + (($skillList | ForEach-Object { "  - $_" }) -join "`n") + "`n---"
            $dir = if ($style -eq 'plugin') { $PluginDir } else { $ClaudeDir }
            Write-Text (Join-Path $dir "agents/$name.md") ($fm + "`n`n" + $gen + "`n`n" + $a.Body + (Get-TemplateSection $a))
        }
    }

    # Copilot custom agent (no skill preloading: name the skills in the prompt). Model choice is
    # Claude-only for now: Copilot's model values are not documented.
    $ctools = (Get-CopilotTools $m['tools'] | ForEach-Object { "'$_'" }) -join ', '
    $copilot = "---`nname: $name`ndescription: $desc`ntools: [$ctools]`n---"
    $skillLine = "Before you start, load these skills: " + (($skillList | ForEach-Object { '`' + $_ + '`' }) -join ', ') + ". They define the rules this prompt refers to."
    $cbody = $a.Body -replace '(?m)^<!-- on-demand:[^\n]*-->\n', ''
    if ($m['role'] -eq 'orchestrator') {
        # The orchestrator-only blocks of the shared standards become one extra skill (the agent
        # file itself must stay under Copilot's 30,000-character limit).
        $extra = @($skillList | ForEach-Object { Get-OrchestratorOnly $Standards[$_].Body } | Where-Object { $_ })
        if ($extra.Count) {
            $oname = "$name-rules"
            $odesc = ConvertTo-YamlString "Rules from the shared d365fo standards that only $name needs: recording sign-offs, background runs, choice forms and using the user's answers."
            Write-Text (Join-Path $PluginDir "skills/$oname/SKILL.md") ("---`nname: $oname`ndescription: $odesc`n---`n`n$gen`n`n# Orchestrator rules`n`n" + ($extra -join "`n`n"))
            $skillLine = $skillLine.Replace('. They define', ", ``$oname``. They define")
        }
        $tn = @(Get-TemplateNames $a.Body)
        if ($tn.Count) { $skillLine = $skillLine.Replace('. They define', ", and ``d365fo-templates`` for " + (($tn | ForEach-Object { "templates/$_.md" }) -join ', ') + '. They define') }
        $ctemplates = ''
    } else { $ctemplates = Get-TemplateSection $a }
    Write-Text (Join-Path $PluginDir "com.github.copilot/agents/$name.agent.md") ($copilot + "`n`n" + $gen + "`n`n" + $skillLine + "`n`n" + $cbody + $ctemplates)
}

# ---------------------------------------------------------------- hooks

# Claude: exec form (no shell), Windows PowerShell 5.1, which every D365 dev box has.
function Get-ClaudeHooks([string] $dir) {
    $out = [ordered]@{}
    foreach ($h in $HookList) {
        $ev = $HookEvents[[string]$h.event][0]
        $group = [ordered]@{}
        if ($h.PSObject.Properties['tools']) { $group['matcher'] = (@($h.tools) | ForEach-Object { $HookTools[[string]$_] }) -join '|' }
        $group['hooks'] = @([ordered]@{
            type = 'command'; command = 'powershell.exe'
            args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$dir/$($h.script)")
            timeout = [int]$h.timeout
        })
        if (-not $out.Contains($ev)) { $out[$ev] = @() }
        $out[$ev] = @($out[$ev]) + $group
    }
    return $out
}

foreach ($s in $HookScripts) {
    $text = Read-Text (Join-Path $SrcHooks $s)
    Write-Text (Join-Path $PluginDir "hooks/$s") $text           # Claude plugin + Copilot plugin
    Write-Text (Join-Path $ClaudeDir "hooks/d365fo/$s") $text    # Claude install (copied by install-claude.ps1)
}
$hookDesc = 'd365fo agents: approval stamps from the user''s own messages, and gates on d365fo writes, builds and AOT files. Generated from src/hooks/.'
Write-Text (Join-Path $PluginDir 'hooks/hooks.json') (ConvertTo-StableJson ([ordered]@{ description = $hookDesc; hooks = (Get-ClaudeHooks '${CLAUDE_PLUGIN_ROOT}/hooks') }))
# Fragment that install-claude.ps1 merges into settings.json; it replaces {HOOKS_DIR} with the real folder.
Write-Text (Join-Path $ClaudeDir 'hooks/d365fo/settings-fragment.json') (ConvertTo-StableJson ([ordered]@{ hooks = (Get-ClaudeHooks '{HOOKS_DIR}') }))

# Copilot CLI / app (UNTESTED): plugin hooks.json, version 1, camelCase events, no matcher (the
# scripts filter by tool themselves). Script paths are relative to the plugin folder.
$cp = [ordered]@{}
foreach ($h in $HookList) {
    $ev = $HookEvents[[string]$h.event][1]
    if (-not $cp.Contains($ev)) { $cp[$ev] = @() }
    $cp[$ev] = @($cp[$ev]) + [ordered]@{ type = 'command'; powershell = "& ./hooks/$($h.script)"; timeoutSec = [int]$h.timeout }
}
Write-Text (Join-Path $PluginDir 'hooks.json') (ConvertTo-StableJson ([ordered]@{ version = 1; hooks = $cp }))

# ---------------------------------------------------------------- output checks

$outFiles = @(Get-ChildItem -Recurse -File -Force -Path $PluginDir, $ClaudeDir)
$patterns = @('\b[A-Za-z]:\\[A-Za-z]') + @($ForbiddenWords | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) })
foreach ($f in $outFiles) {
    $text = Read-Text $f.FullName
    foreach ($p in $patterns) { if ($text -match $p) { Add-BuildError "Environment-specific text '$($Matches[0])' in $($f.FullName.Substring($Root.Length + 1))" } }
    if ($f.Name -like '*.agent.md' -and $text.Length -gt 30000) { Add-BuildError "$($f.Name) is over Copilot's 30,000-character agent limit" }
    if ($f.Name -eq 'SKILL.md') {
        foreach ($ln in [regex]::Matches($text, '\$\{CLAUDE_SKILL_DIR\}/([^\s`]+)')) {
            $rel = $ln.Groups[1].Value
            if ($rel -notmatch '<' -and -not (Test-Path (Join-Path $f.DirectoryName $rel))) { Add-BuildError "$($f.FullName.Substring($Root.Length + 1)) links a missing file: $rel" }
        }
    }
}
if ($Errors.Count) { $Errors | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }; throw "Build failed: $($Errors.Count) error(s) in the output." }

Write-Host ("Built {0} agents and {1} skills into {2} files:" -f $Agents.Count, $Standards.Count, $outFiles.Count) -ForegroundColor Green
Write-Host "  plugins/d365fo-agents/   GitHub Copilot app plugin (also a Claude Code plugin)"
Write-Host "  claude/.claude/          Claude desktop app, copied into a repo by install-claude.ps1"
