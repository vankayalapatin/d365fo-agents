# D365 F&O AI Agents

AI agents for **Microsoft Dynamics 365 Finance and Operations** (D365 F&O, D365FO): Finance and
Supply Chain Management. Paste a business ticket, however vague, and a team of agents takes it
all the way: functional fit-gap → **security and licensing design** → signed-off **FDD** and
**TDD** → **X++ written, built and unit-tested** the way a senior developer would (extensions,
Chain of Command, event handlers, SysOperation, labels, security) → **code review and BP
check** → **QA against every acceptance criterion** → **UAT script**, in **GitHub Copilot** or
**Claude**.

Under the hood it's a **multi-agent system**: an orchestrator agent runs seven specialist
subagents, with **human-in-the-loop** sign-off gates, and every agent is grounded through an
**MCP (Model Context Protocol) server** that acts as a **RAG layer** over your D365 metadata.

### Built on d365fo-mcp-server

Thanks and kudos to [Filip Maňas](https://github.com/dynamics365ninja) for
[d365fo-mcp-server](https://github.com/dynamics365ninja/d365fo-mcp-server), the open-source MCP
server these agents are built on.

The server is the agents' **retrieval and tool layer**. It runs on your D365 dev machine,
indexes your real metadata (standard and custom: tables, classes, forms, EDTs, labels, security
objects) and exposes it to the agents as **MCP tools**: **retrieval-augmented generation (RAG)**
over your own codebase. Before an agent writes a design or a line of X++, it retrieves the
actual objects, fields and method signatures, generates through a **grounding chain**
(prepare → generate → validate → write), and checks the result with the real compiler and BP
checker. That is how the agents avoid **hallucinating** tables, fields or methods that don't
exist.

> Work in progress. Tested on UDE in the Claude desktop app. LCS Tier-1 cloud-hosted VMs and the
> GitHub Copilot app are supported by design but not yet verified.

## How it works

```
ticket ──► architect
             ├──► assessments: finance · supply chain · security (· reporting)
             ├──► FDD ──► you sign off
             ├──► TDD ──► you sign off            (also approves the build plan)
             ├──► developer   finds the right extension points in your metadata, then
             │   (in the      writes the X++: table/form extensions, Chain of Command,
             │   background)  event handlers, SysOperation batch, labels, security objects
             │                ──► builds ──► unit tests, if you asked for them
             │        ▲
             │        └── remember something mid-build? tell the architect: it shows you
             │            the impact in plain words, and the running developer picks it up
             ├──► reviewer    standards, BP check, security against the TDD
             ├──► QA          every acceptance criterion ──► UAT script
             │                (up to two fix rounds, then back to you)
             ▼
        summary: what was built, tests, BP, what to deploy
```

The agents run in a desktop AI app — the **GitHub Copilot app** or the **Claude desktop app** —
next to Visual Studio. You start the architect once; it runs every other agent itself and only
stops to ask you something. You keep editing and building in Visual Studio as usual; the
agents read and write the same model through the MCP server.

| Agent | Job |
|---|---|
| `d365fo-architect` | Start here. Runs the assessments, reconciles finance and supply chain, writes the FDD and TDD. |
| `d365fo-finance-functional` | Finance fit-gap and impact: GL, AP/AR, tax, dimensions, period close. |
| `d365fo-scm-functional` | Supply chain fit-gap and impact: procurement, sales, inventory, warehouse, production, costing. |
| `d365fo-security` | Current role coverage, role/duty/privilege changes, license impact, segregation of duties. |
| `d365fo-reporting` | SSRS and Print management documents. |
| `d365fo-developer` | Implements the signed-off TDD with extensions only, plus SysTests when you choose them. |
| `d365fo-reviewer` | Technical review against the TDD and the standards; runs the BP check. |
| `d365fo-qa` | Checks every acceptance criterion; writes the UAT script. |

Every step writes a file under `d365fo-work/<ticket-id>/` in your repo, so you can read, edit
and keep the ticket, assessments, FDD, TDD, review and QA results.

## Ways to start

You always start the same architect. It looks at what you paste, says where it will start,
and you can change that:

| You paste | The architect | Ends with |
|---|---|---|
| A vague ticket | Runs the full analysis: assessments → FDD → TDD → build | Built, reviewed, QA'd change |
| Requirements or an FDD written by your team | Checks them for gaps (missing acceptance criteria, contradictions, security, cross-module impact), asks only about those → TDD → build | Built, reviewed, QA'd change |
| A clear, small change ("add field X to table Y, show it on form Z") | Writes a one-screen plan checked against your metadata; one "go" and the developer starts, while security and other-module checks run alongside | Built, reviewed, QA'd change |
| Anything, with "explore:" | Explains the process, standard options, impact and risks, and writes clarifying questions to send back | `analysis.md` — nothing built |

Whatever the start, nothing is built without a signed-off TDD and acceptance criteria to test
against, and security is always checked.

**No MCP server?** Exploring and writing or checking an FDD still work, grounded in
Microsoft Learn instead of your metadata — useful for functional consultants. Every file then
says it was not checked against your environment; the TDD and the build need the server.

## How it's engineered

- **Orchestrator–subagent architecture:** one architect agent plans and delegates; specialist
  subagents each get only the context and tools their job needs.
- **MCP tool use with least privilege:** each agent's tool list is explicit. Analysts can't
  write code; only the developer writes X++.
- **RAG grounding:** every claim and every generated object is checked against retrieved
  metadata, not model memory.
- **Human-in-the-loop gates, enforced:** nothing is built until a person signs off the FDD and
  the TDD, and hooks block the writes mechanically until they do (see *Approval hooks*).
- **Tests as you choose:** every acceptance criterion gets a manual UAT step. Automated
  SysTests, and a red run before the logic exists, are two questions the architect asks you;
  both default to no, because each red run costs a Visual Studio deploy.
- **State in files, not chat:** requirements, acceptance criteria and decisions carry IDs
  (REQ, AC, D, OBJ), traceable from ticket to test. Runs can resume, and every step is
  auditable.
- **Bounded loops and escalation:** one consensus round between analysts and two fix rounds
  after review, then the agents hand back to you instead of looping.
- **Background work you can steer:** the developer builds in the background while the
  architect stays available to you. A change you add mid-build is recorded in a change log
  the developer checks before each object and each write, plus a direct nudge to the running
  agent — no restart, and you see which objects were already built under the old rule.
- **Cost-aware orchestration:** one long-running developer, steered with small messages,
  instead of a fresh agent per step — every new agent start re-reads its full instructions.
  Large builds split by dependency group only when the client can't run in the background.
- **Prompts as code:** each agent is written once and compiled by a deterministic build into
  GitHub Copilot and Claude formats; the build validates tool names, skills and portability.
- **Grounded in Microsoft guidance:** a second MCP server (Microsoft Learn) lets agents cite
  official documentation.

## Before you install

You need all three on your D365 development machine:

1. **A D365 F&O development environment with Visual Studio**: UDE (tested) or an LCS Tier-1
   cloud-hosted VM (designed for, not yet verified).
2. **d365fo-mcp-server** installed and running, following its
   [Quick Start](https://github.com/dynamics365ninja/d365fo-mcp-server). In your D365 repo's
   MCP config (`.mcp.json` for Claude), register it under the name **`d365fo-mcp-tools`**:
   the agents look for exactly that name.
3. **The server's rules file in your D365 repo**: its `.github/copilot-instructions.md`, copied
   into the repo as `CLAUDE.md` for Claude, or as `.github/copilot-instructions.md` for Copilot.

The second MCP server the agents use, **Microsoft Learn**, needs no setup: the plugin brings it.

## Install in the Claude desktop app (tested)

**Option A: the plugin**

1. Open the Claude desktop app → **Customize → Plugins → + Add**, and enter
   `vankayalapatin/d365fo-agents`. (Claude Code in a terminal:
   `/plugin marketplace add vankayalapatin/d365fo-agents`.)
2. Install **d365fo-agents**. (Terminal: `/plugin install d365fo-agents@d365fo-agents`.)
3. Open a **Code** session on your D365 repo folder itself, not a git worktree: the MCP server
   writes to your model's metadata folder, and a worktree wouldn't see those changes.
4. Type `/d365fo-agents:d365fo-architect` followed by your ticket text.

**Option B: the install script** (what the tests used)

1. Clone this repo anywhere.
2. In PowerShell, from the repo folder:
   ```powershell
   ./scripts/install-claude.ps1 -User
   ```
   This copies the agents and skills into `~/.claude/`, and merges the approval hooks into
   `~/.claude/settings.json`. It writes a backup first and keeps your own settings and hooks.
   To also add the Microsoft Learn server and the rules file to one repo, add
   `-RepoPath <your D365 repo> -McpInstructionsPath <d365fo-mcp-server>/.github/copilot-instructions.md`.
3. Open a **Code** session on your D365 repo folder (not a worktree).
4. Type `/d365fo-architect` followed by your ticket text.

**Check it works:** paste a small ticket such as *"Add a Legacy customer number (text, 20
characters) on customers, shown on All customers"*. The architect should read your workspace
(model, prefix, environment type), then ask **"Go on <ticket> TDD v1?"**. Your *go* should be
confirmed as stamped.

The architect runs in your conversation, asks you for the sign-offs, and starts every other
agent itself.

## Install in the GitHub Copilot app (not yet tested)

The same plugin is built for the Copilot app, but nobody has run it there yet. Please report
what you find.

1. In the Copilot app: **Customize → + Add**, marketplace `vankayalapatin/d365fo-agents`.
   (Copilot CLI: `copilot plugin marketplace add vankayalapatin/d365fo-agents`.)
2. Install **d365fo-agents**. (CLI: `copilot plugin install d365fo-agents@d365fo-agents`.)
3. Open your D365 repo, select the **d365fo-architect** agent and paste your ticket.

## Update, switch off, uninstall

- **Update:** update the plugin in the app; with the script, pull this repo and run
  `./scripts/install-claude.ps1 -User` again.
- **Switch the hooks off** (keep the agents): create an empty file named `OFF` in your
  approvals folder (see *Approval hooks*). Delete it to switch them on again.
- **Uninstall:** remove the plugin in the app. Script install:
  `./scripts/install-claude.ps1 -User -Uninstall` removes the d365fo agents, skills and hooks
  (your approval stamps and `.mcp.json` are kept).

## Approval hooks

A prompt rule like "don't write code before sign-off" asks the model to police itself. The
plugin also installs three small **PowerShell hooks** (Windows PowerShell 5.1 or 7; no
network, no modules) that enforce the gates outside the model:

- **When you send a message**, a hook reads the agent's last question. If it asked
  *"Approve B9 TDD v2?"* and you answer *yes*, *approve*, *go* or click a reply button, it
  records an approval for exactly that document version. If the question named nothing,
  nothing is approved. You can also type `approve B9 TDD v2`.
- **Before a tool runs**, a hook blocks X++ writes, label writes and builds without a valid
  approval; writes to objects the approved design doesn't list; terminal writes to AOT files
  under `Metadata`; and any agent write to the approval store.
- **After a file write**, a hook records which session changed a design document, so an edit
  after sign-off needs a new approval.

Approvals live in `~/.claude/d365fo-stamps/` on your machine, one file per repo. Only the
hooks write there. To switch the hooks off, create an empty file named `OFF` in that folder
(PowerShell: `New-Item -ItemType File "$HOME\.claude\d365fo-stamps\OFF"`). With the script
install, `install-claude.ps1 -RemoveHooks` takes them out again. The hooks run with
`-ExecutionPolicy Bypass` so they work on locked-down dev VMs. Read
[`src/hooks/`](src/hooks/) before you install: they are short, and
`src/hooks/test-hooks.ps1` runs their self-test with nothing else installed.

Limits: the terminal check matches command text, so it stops slips, not a determined
workaround. In the GitHub Copilot app the hooks are untested.

## FAQ

**Can AI agents write X++ for D365 F&O?**
Yes, and these agents write it the way a senior developer would: extensions only, labels, EDTs,
SysOperation for batch, set-based data access, security for every entry point — and they check
every table, class and method name against your real metadata before writing code.

**Does it work with GitHub Copilot?**
Yes. It is a plugin for the GitHub Copilot app (and Copilot CLI), and the same plugin works in
Claude.

**Do I need d365fo-mcp-server?**
For design and code, yes: the agents read your workspace, search metadata, generate, validate,
build and BP-check through it. Without it, they can still explore a ticket and write or check
an FDD using Microsoft Learn, and say clearly that nothing was checked against your
environment.

**Our team already writes the requirements. Do the agents redo them?**
No. Paste the requirements or FDD and the architect checks them for gaps instead of starting
over, then goes on to the technical design. Paste a technical spec and it checks that against
your metadata before anything is built.

**What if I remember something halfway through the build?**
Tell the architect in the same chat. It records it, tells you in plain words what it changes
and which objects are already built, and asks you to approve only that change. The running
developer picks it up before its next object or write — it doesn't start over.

**Can functional consultants use it?**
Yes, for the analysis half: explore a ticket, draft an FDD from user requirements, or check
their own FDD for what's missing — with Microsoft Learn citations and no MCP server to set up.

**Does it change anything without asking?**
No code is written before you sign off the FDD and the TDD. Setup and configuration steps are
listed for your team to apply; deployments are never done by the agents.

**What about security roles and licensing?**
The security agent reviews current role coverage, designs the role/duty/privilege changes,
flags user-license impact and segregation-of-duties conflicts. The reviewer checks the code
against that design.

**Visual Studio says "Failed to write runtime metadata to disk … Object reference not set"
after the agents built. What now?**
The agents' tool build leaves its own runtime files in the model's build-output folder, and
Visual Studio's build can trip over them. Close Visual Studio, rename the model's `bin` folder
under your metadata folder (e.g. to `bin.bak`), delete any `*.delete` file in its `Resources`
folder, then reopen Visual Studio and **Rebuild**. Both are build output and are regenerated.
Errors such as "Service '…' does not exist" in the same build usually go away with it.

**Does it work on LCS cloud-hosted VMs?**
It is designed for both UDE and LCS Tier-1 VMs — the agents read the environment type at
runtime — but only UDE has been tested so far.

## Contributing

Agents and standards are written once in [`src/`](src/) and generated for every client:

```powershell
./scripts/build.ps1
```

Never edit `plugins/`, `claude/` or the `marketplace.json` files by hand.

## License

MIT — see [LICENSE](LICENSE). d365fo-mcp-server is a separate project under its own MIT
licence.
