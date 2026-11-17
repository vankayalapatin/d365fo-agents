# d365fo hooks

The agents' prompt rules for approvals asked the model to police itself. These hooks enforce
the same gates mechanically. They are written once here; `scripts/build.ps1` generates the
Claude form (plugin `hooks/hooks.json`, plus a settings fragment that `install-claude.ps1`
merges into `settings.json`) and the Copilot form (plugin `hooks.json`, **untested**).

| Script | Event | What it does |
|---|---|---|
| `d365fo-stamp.ps1` | prompt submitted | Records approvals from the user's own message. **An approval is bound to the question asked:** the hook reads the assistant's last turn from the transcript (`transcript_path`), and a plain answer (`yes`, `approve`, `go`, a reply button) stamps exactly what it asked: `<ticket> TDD v<n>`, `FDD v<n>`, `CH-n` or `task card`. If it asked nothing, nothing is stamped. Typed `approve A1 TDD v1` (short ticket names work, several per message) stamps what it names. Also `approve object X` and `/d365fo-architect task: …`. A relay (`<cross-session-message>`) counts only for documents it names after "approve", and only when the user typed those same words in some session of this project in the last 12 hours. A short ticket name counts only right before a document ("A1 TDD v1"); the full id counts anywhere, also in a path. Subagent hand-backs and notifications never count, and neither does a started session's first message ("Background (from the session that started this one): …"): it is the starting model's text, so it only marks the architect run and carries a task request the user typed elsewhere. Leading `<system-reminder>` blocks are removed first. Every typed message is logged, so a clear instruction after sign-off can approve the TDD change it led to. |
| `d365fo-gate.ps1` | before a tool runs | Blocks `d365fo_file` writes, label writes and builds without a valid stamp (from any session). Blocks writes to objects outside the Name column of TDD §4 or the task card, for the ticket being built (the last `build-log.md` the agent wrote). Blocks terminal writes, copies, moves and deletes of `.xml`/`.xpp` under `Metadata`, terminal writes to work documents, and any model write to the stamp store (reads pass). The write and object gates apply to `d365fo-*` subagents and to sessions started with `/d365fo-architect`. |
| `d365fo-record.ps1` | after a file write | Records each agent write to `tdd/fdd/task/analysis.md` (body hash, session), so the gate can tell an agent's edit from the user's own edit, and each `build-log.md` write (which ticket that agent builds). |

- **Stamp store:** `~/.claude/d365fo-stamps/<project hash>.jsonl`, append-only. A stamp is
  bound to the hash of the document body below its frontmatter, without the Sign-off section:
  recording the sign-off doesn't void it, but changing the design does. (Stamps made before
  this rule no longer match: approve the documents again.)
- **Copilot (untested):** with no transcript in the payload, only approvals that name the
  document (`approve A1 TDD v1`) stamp.
- **Off switch:** create `~/.claude/d365fo-stamps/OFF` yourself (the gate blocks an agent
  from writing in that folder; in PowerShell:
  `New-Item -ItemType File "$HOME\.claude\d365fo-stamps\OFF"`). **Payload log:** create
  `~/.claude/d365fo-stamps/LOG`; raw payloads go to `payload-log.jsonl` next to it.
- **Fail mode:** inside an agent run, a gate error blocks the write ("ask the user"). Other
  errors let the call through.
- **Limit:** the terminal gate matches strings. It stops slips, not a determined workaround;
  full protection would need OS sandboxing.
- **Test:** `./src/hooks/test-hooks.ps1` runs the break-it cases (see `eval/README.md`, *Hooks*)
  against the scripts with no Claude, MCP server or Visual Studio needed.
