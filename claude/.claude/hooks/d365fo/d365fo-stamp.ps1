# UserPromptSubmit (Claude) / userPromptSubmitted (Copilot).
# Records approvals, task requests and instructions from the user's own messages. The model
# cannot write this record: the gate denies every model write to the stamp folder.
#
# An approval is bound to the question that was asked. The hook reads the assistant's last
# turn from the transcript and finds what it asked the user to approve: "<ticket> TDD v<n>",
# "<ticket> FDD v<n>", "<ticket> CH-n" or "<ticket> task card" ("A1" is enough for the ticket).
#
#   typed plain approval ("yes", "approve", "go", a reply button) -> stamps exactly what the
#                                       last turn asked; if it asked nothing, nothing is stamped
#   typed "approve A1 TDD v1 / approve B1 TDD v1" -> stamps each document named (several per message)
#   typed "approve object X"           -> X may be written in task mode
#   "/d365fo-architect task: <req>"    -> task stamp (the request word for word)
#   any other typed message            -> logged as the user's words (for instructions after sign-off)
#   relayed (<cross-session-message>)  -> stamps only documents it names after "approve", and
#                                       only when the user typed those words in some session
#                                       of this project (the relaying model can't invent them)
#   subagent reports, notifications    -> ignored
# Leading <system-reminder> blocks are removed first: they are the app's, not the user's.
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $p = Read-HookInput
    if ($null -eq $p -or (Test-HooksOff)) { exit 0 }
    $n = Get-Normalized $p
    if (-not $n.Prompt) { exit 0 }
    $raw = Remove-LeadingReminders $n.Prompt

    # ---- classify: typed, relayed or neither
    $source = 'typed'; $from = ''; $text = $raw
    $cmd = [regex]::Match($raw, '(?s)<command-name>/?([\w:-]+)</command-name>')
    $relay = [regex]::Match($raw, '(?s)^(?:Another Claude session sent a message:\s*)?<cross-session-message([^>]*)>(.*?)(?:</cross-session-message>|\z)')
    if ($cmd.Success) {
        $args0 = [regex]::Match($raw, '(?s)<command-args>(.*?)</command-args>')
        $text = '/' + ($cmd.Groups[1].Value -replace '^.*:', '') + ' ' + $(if ($args0.Success) { $args0.Groups[1].Value } else { '' })
    } elseif ($relay.Success) {
        $source = 'relayed'; $text = $relay.Groups[2].Value
        $f = [regex]::Match($relay.Groups[1].Value, 'from-name="([^"]*)"')
        if (-not $f.Success) { $f = [regex]::Match($relay.Groups[1].Value, 'from="([^"]*)"') }
        if ($f.Success) { $from = $f.Groups[1].Value }
    } elseif ($raw -match '^Background \(from the session that started this one\)') {
        # A started session's first message is written by the starting session's model, not
        # typed by the user: never an approval and never logged as the user's words. Only two
        # things carry over: the architect run (so its writes are gated), and a task request
        # the user really typed in some session of this project.
        $root = Find-ProjectRoot $n.Cwd
        if (-not $root -or $raw -notmatch '/d365fo-architect\b') { exit 0 }
        Add-Record $root @{ type = 'run'; session = $n.Session }
        $tm = [regex]::Match($raw, '(?is)/d365fo-architect\s+task:\s*(.+?)(?:\r?\n\s*\r?\n|\z)')
        if ($tm.Success) {
            $req = $tm.Groups[1].Value.Trim(); $rp = ConvertTo-Plain $req
            if (@(Get-Records $root | Where-Object { $_.type -eq 'words' -and $_.plain -and $_.plain.Contains($rp) }).Count) {
                Add-Record $root @{ type = 'task'; session = $n.Session; request = $req; plain = $rp }
                Write-Note "task request stamped (the user typed it in another session). Copy it word for word into the Request section of task.md."
            }
        }
        exit 0
    } elseif ($raw -match '^[<\[]' -or $raw -match '^Another Claude session sent a message') {
        exit 0   # subagent hand-backs, harness notifications, task reports: never the user's words
    }
    $text = $text.Trim()

    $root = Find-ProjectRoot $n.Cwd
    $isArchitect = $text -match '^/d365fo-architect\b'
    if (-not $root) { if ($isArchitect) { $root = $n.Cwd } else { exit 0 } }
    $tickets = @(Get-Tickets $root)

    if ($source -eq 'typed') {
        $logged = $text; if ($logged.Length -gt 4000) { $logged = $logged.Substring(0, 4000) }
        Add-Record $root @{ type = 'words'; session = $n.Session; text = $logged; plain = (ConvertTo-Plain $logged) }
        if ($isArchitect) { Add-Record $root @{ type = 'run'; session = $n.Session } }
    }

    # ---- task request
    $t = [regex]::Match($text, '(?is)^(?:/d365fo-architect\s+)?task:\s*(.+)$')
    if ($source -eq 'typed' -and $t.Success) {
        $req = $t.Groups[1].Value.Trim()
        Add-Record $root @{ type = 'task'; session = $n.Session; request = $req; plain = (ConvertTo-Plain $req) }
        Write-Note "task request stamped. Copy it word for word into the Request section of task.md. Objects it does not name: show the task card's object list and ask 'go on <ticket> task card?'."
        exit 0
    }

    # ---- object approval (task mode)
    $objM = [regex]::Match($text, '(?i)^\s*approve\s+object\s+([A-Za-z_][\w.]*)\s*$')
    if ($objM.Success) {
        if ($source -ne 'typed') { Write-Note "object approval NOT stamped: it must be typed by the user."; exit 0 }
        Add-Record $root @{ type = 'object'; session = $n.Session; name = $objM.Groups[1].Value; words = $text }
        Write-Note "object $($objM.Groups[1].Value) approved by the user for this task."
        exit 0
    }

    $records = @(Get-Records $root)
    function Add-ItemStamp($it) {
        $label = "$($it.Ticket) $($it.Doc.ToUpper())$(if ($it.Version) { " v$($it.Version)" })"
        if ($it.Ch) {
            $chPath = Get-DocPath $root $it.Ticket 'changes'
            if (-not (Test-Path $chPath) -or ([System.IO.File]::ReadAllText($chPath) -notmatch ('\|\s*' + $it.Ch + '\s*\|'))) { return "$($it.Ticket) $($it.Ch) NOT stamped: no such row in changes.md" }
            $label = "$($it.Ticket) $($it.Ch)"
        }
        $doc = Read-WorkDoc (Get-DocPath $root $it.Ticket $it.Doc)
        if (-not $doc) { return "$label NOT stamped: $($it.Doc).md does not exist yet" }
        if ($doc.Status -eq 'superseded') { return "$label NOT stamped: that document is superseded" }
        if ($it.Version -and $doc.Version -ne $it.Version) { return "$label NOT stamped: the file is now v$($doc.Version). Ask again for v$($doc.Version)" }
        $dup = @($records | Where-Object { $_.type -eq 'stamp' -and $_.ticket -eq $it.Ticket -and $_.doc -eq $it.Doc -and $_.bodyHash -eq $doc.BodyHash })
        if ($dup.Count) { return "$($it.Ticket) $($it.Doc.ToUpper()) v$($doc.Version) was already approved and has not changed" }
        $objs = @(); if ($it.Doc -eq 'tdd') { $objs = Get-TddObjects $doc } elseif ($it.Doc -eq 'task') { $objs = Get-TaskObjects $doc }
        $via = if ($it.Ch) { "change $($it.Ch)" } else { 'approval' }
        Add-Record $root @{ type = 'stamp'; session = $n.Session; ticket = $it.Ticket; doc = $it.Doc; version = $doc.Version; bodyHash = $doc.BodyHash
            objects = $objs; source = $source; from = $from; via = $via; words = $text }
        return "stamped approval of $($it.Ticket) $($it.Doc.ToUpper()) v$($doc.Version)$(if ($it.Ch) { " ($($it.Ch))" }) ($source$(if ($from) { " from $from" })). Record the sign-off with these words"
    }
    function Write-Results($items) { Write-Note ((@($items | ForEach-Object { Add-ItemStamp $_ }) -join '; ') + '.') }

    $turn = Get-LastTurn $n.Transcript
    $asked = @(Get-NamedItems ($turn.Lines -join "`n") $tickets)
    $askedTicket = ''; $at = @($asked | ForEach-Object { $_.Ticket } | Select-Object -Unique); if ($at.Count -eq 1) { $askedTicket = $at[0] }
    $negation = '(?i)\b(not|don''?t|didn''?t|never|reject(ed)?|but|except|instead|wait|hold)\b'

    # ---- relayed: only documents named after "approve" count
    if ($source -eq 'relayed') {
        $segs = @([regex]::Matches($text, '(?i)\bapprove\s+([^\n/;]+)') | ForEach-Object { $_.Groups[1].Value })
        if (-not $segs.Count) { exit 0 }
        if ($text -match '(?i)\b(not|didn''?t|never)\s+approv|\breject') { Write-Note "relayed approval NOT stamped: the message says it was not approved."; exit 0 }
        # The relaying session's model could write any words. Count the relay only if the user
        # typed the same approval in some session of this project in the last 12 hours.
        $since = (Get-Date).ToUniversalTime().AddHours(-12)
        $typed = @($records | Where-Object { $_.type -eq 'words' -and $_.plain -and ([datetime]$_.time).ToUniversalTime() -gt $since } | ForEach-Object { $_.plain })
        $segs = @($segs | Where-Object { $want = ConvertTo-Plain ('approve ' + $_.Trim().TrimEnd('.', '!')); @($typed | Where-Object { $_.Contains($want) }).Count })
        if (-not $segs.Count) {
            Write-Note "relayed approval NOT stamped: the user did not type these words in any session of this project. Ask the user to approve here. Do not record a sign-off."
            exit 0
        }
        $items = @(); foreach ($s in $segs) { $items += @(Get-NamedItems $s $tickets $askedTicket) }
        if (-not $items.Count) {
            Write-Note "relayed approval NOT stamped: it names no document. A relay must say 'approve <ticket> TDD v<n>' (or FDD, CH-n, task card). Do not record a sign-off."
            exit 0
        }
        Write-Results $items
        exit 0
    }

    # ---- typed
    $lead = $text.Length -le 600 -and $text -match '(?i)^\s*(?:ok(?:ay)?|yes|great|thanks)?[,.!\s]*(?:i\s+)?(approved?|approving|sign(?:ed)?[ -]?off|signoff|go(?:\s+ahead)?|lgtm)\b'
    $named = @(); if ($lead) { $named = @(Get-NamedItems $text $tickets $askedTicket) }
    if ($named.Count) {
        if ($text -match $negation) { Write-Note "approval NOT stamped: the reply says more than approve (it has '$($Matches[1])'). Make the change, then ask again."; exit 0 }
        Write-Results $named
        exit 0
    }

    # A plain approval: approval words only, or one of the reply buttons the last turn offered.
    $approveWords = @('yes', 'y', 'yep', 'yeah', 'yup', 'ok', 'okay', 'sure', 'approve', 'approved', 'approving', 'go', 'lgtm', 'sign', 'signed', 'off', 'signoff', 'proceed', 'confirm', 'confirmed', 'agreed', 'agree')
    $filler = @('ahead', 'it', "it's", 'please', 'build', 'thanks', 'thank', 'you', 'now', 'the', 'plan', 'both', 'all', 'and', 'design', 'looks', 'good', 'fine', 'start', 'do', 'that', 'this', 'them', 'ship', "let's", 'lets', 'great', 'perfect', 'was', 'me', 'i', 'did', 'mine', 'correct', 'right')
    $plain = $false
    $s = $text.Trim().TrimEnd('.', '!')
    foreach ($l in $turn.Labels) {
        if ($s -ieq $l.Trim().TrimEnd('.', '!') -and $l -notmatch '(?i)^\s*(no|not|don''?t|change|stop|wait|cancel|later|hold|skip|reject|edit|revise)\b') { $plain = $true }
    }
    if (-not $plain -and $s.Length -le 80) {
        $w = @([regex]::Matches($s.ToLowerInvariant(), "[a-z']+") | ForEach-Object { $_.Value })
        $plain = $w.Count -and @($w | Where-Object { $_ -in $approveWords }).Count -and -not @($w | Where-Object { $_ -notin $approveWords -and $_ -notin $filler }).Count
    }
    if (-not $plain) {
        if ($lead -and $asked.Count) { Write-Note "approval NOT stamped: the reply was more than a plain approval. Make the change, then ask again." }
        exit 0
    }
    if ($asked.Count) { Write-Results $asked; exit 0 }
    $waiting = @(foreach ($tk in $tickets) { foreach ($dn in 'fdd', 'tdd', 'analysis', 'task') { $d = Read-WorkDoc (Get-DocPath $root $tk $dn); if ($d -and $d.Status -eq 'ready-for-sign-off') { "$tk $($dn.ToUpper()) v$($d.Version)" } } })
    if ($waiting.Count) {
        Write-Note "approval NOT stamped: your last message did not name what to approve. Ask again, naming it, e.g. 'Approve $($waiting[0])?'"
    }
    exit 0
} catch {
    [Console]::Error.WriteLine("d365fo stamp hook error: $($_.Exception.Message)")
    exit 0   # never block the user's message; the gate fails closed instead
}
