---
name: d365fo-grounding
description: How every d365fo agent reads the workspace, environment and real metadata through the d365fo MCP server before making any claim, what to do when a tool is missing or fails, and how analysis work runs on Microsoft Learn alone when the server is not connected. Use at the start of every d365fo agent run.
---

# Grounding and environment

The MCP server already ships the core rules (call `get_workspace_info` first, no terminal
fallback, confirm before writing, `d365fo_file` is the only writer for AOT files, batch your
reads). This standard adds what the agent team needs on top.

## 1. Start of every run

1. Call `get_workspace_info()`.
   - Call fails or the tool is missing → the MCP server is not connected. Continue only in
     **docs-only grounding** (§6), and only if the ticket allows it: the architect's start
     mode permits it, or `ticket.md` says `grounding: docs-only` and your stage is `explore`
     or `fdd`. Otherwise STOP: say the MCP server is not connected and ask the user to start
     it.
   - Response contains `⛔` → STOP. Relay the message word for word.
2. Note for the rest of the run: **model**, **prefix**, **extension naming style**,
   **environment type** (`ude` or traditional/Tier-1) and any index-staleness warning.
3. Never take these from anywhere else — not from object names in search results, not from
   paths, not from earlier tickets.
4. **Target project.** When the workspace has more than one project, don't assume the first
   one, or the one an earlier ticket used. Ask which project the ticket builds into and
   record it in TDD §1. Then call `get_workspace_info(projectPath=<it>)`. If that warns that
   the project belongs to a different model, or the project file's `<Model>` is not the
   workspace model, STOP: tell the user to set the project's *Model* property in Visual
   Studio and save it. Never write into a project of another model.

## 2. Ground before you claim

- **Plan the reads first**, then fetch them together: `get_object_info(objects=[…])` for
  2+ known objects, `search(queries=[…])` for 2+ searches. Independent read-only calls go out
  in the same step.
- A statement about the system ("CustTable has field X", "this form is covered by role Y",
  "standard posting already does Z") must come from a tool result in this run, or from a
  Microsoft Learn page you opened. If it came from neither, label it **assumption**.
- Prefer `get_object_info` over raw files for anything under the packages folders.
- Reports: read the summary (default). Ask for `includeRdl: true` only for a named design
  you must inspect, never for the whole report.
- Ask for the smallest result set that answers the question.

## 3. Environment differences

The X++ design is the same on UDE and Tier-1. What differs is runtime and tooling:

| Topic | UDE | Tier-1 cloud-hosted VM |
|---|---|---|
| Runtime and database | Remote environment, no local AOS or AxDB | Local AOS (IIS) and local AxDB |
| `axdb_sql`, `trace_d365fo` | Normally not available | Available only if configured |
| `build_d365fo_project(restartAos)` | Needs the environment URL passed in | Found from the local `web.config` |
| Paths | Two roots from the XPP config (Microsoft, custom) | One packages folder |
| `run_systest_class` | Does not start: the test runner (SysTestConsole / SysTestRunner) is not in the local bin folder. The user runs the class in Visual Studio Test Explorer and pastes the result. | Runs locally |
| Database sync (`dbSync`) and label compile | Do not run from the tool: the sync engine is not local (the database is in the cloud) and the label compiler may fail to start. The user does it in Visual Studio: project properties → *Deploy changes to online environment* = Yes and *Synchronize database on build* = Yes, then **Rebuild** the project. Building with deploy off leaves the sync hanging. | Runs locally |

**Every Visual Studio step starts with:** *"Close open editors for these objects and restart
Visual Studio before the Rebuild — VS caches metadata and may not read the latest files."*
Symptoms of the cache: "class not found", old code in the editor, or a test run that never
finishes. Ask the user for a Visual Studio run once per code change, never a repeat of the same
run without one.

**"Failed to write runtime metadata to disk … Object reference not set" in Visual Studio**,
often with "Service/Security duty '<name>' does not exist" for objects that do exist on disk.
The cause is the model's build-output folder, not the design: a tool build
(`build_d365fo_project`) writes its own runtime metadata files into `<model>\bin`, and
Visual Studio's build then fails at its *Write runtime metadata* step. A leftover
`<model>.dll<random>.delete` file in `<model>\Resources` is a related sign. Give the user these
steps, in this order (agents don't move these files: the terminal gate blocks it):
1. Close Visual Studio completely.
2. Rename the model's `bin` folder under the metadata folder (for example to
   `bin.bak-<date>`) and delete any `*.delete` file in its `Resources` folder. Both are build
   output, regenerated by the next build; keep the renamed folder until the build is green.
3. Reopen Visual Studio and **Rebuild** the project with deploy and sync on.
Don't change the design or the objects for this error. If it is still there after a clean
`bin`, then look at the objects it names.

**BP label noise on UDE.** The BP check there can report `BPErrorUnknownLabel` even for
standard labels (`@SYS22005`), followed by `BPUnusedStrFmtArgument` on the same `strFmt`.
Treat that pair as known noise when the label exists (`labels(action="search")`) and the
Visual Studio Rebuild doesn't report it; say so in the build log.

Rules:
- Never hardcode a drive, a packages path, a model name or a prefix in any output.
- Optional tools may be missing. If one is, say so in one line and give the manual step
  (for example "check the result in the client") — never work around it with a script or
  the terminal.
- What the server **cannot see**: security changed at runtime in an environment (Security
  configuration), Print management setup, Feature management state, parameter values and
  data in other environments. Ask the user when the design depends on them.

## 4. Who may write what

- Only the **developer** writes AOT objects, and only through `d365fo_file`.
- Every other agent is read-only towards X++ and metadata. It may write **only its own work
  file** (see `d365fo-work-files`). If such an agent finds it needs a change in code, it
  records it as a finding — it never edits.
- No agent runs `build_d365fo_project` unless the user asked for a build or the signed-off
  TDD's build plan covers it (`d365fo-work-files` §4).

## 5. When something fails

- Tool error → report it verbatim, say what you were trying to do, stop that line of work.
  Do not retry the same call with guessed parameters more than once; look the contract up
  with `get_knowledge(kind="op-spec")` or the tool's error text instead.
- **Stale build results.** The tool build can report errors that Visual Studio no longer
  has, for example *"A reference to 'Dynamics.AX.<Package>' is required"* while the model
  descriptor already lists that package. Before changing anything outside the TDD because of
  a build error, check the error against the files: here, the descriptor's
  `ModuleReferences`. If they already contain the fix, the result is stale: don't edit the
  descriptor. **Current workaround** for this known server issue, whose cause is not yet
  known: tell the user to restart Visual Studio and rebuild. Drop this step once the server
  is fixed.
- Ambiguous ticket, missing decision, or conflicting evidence → stop and return
  `STATUS: needs-input` with the questions (see `d365fo-work-files`). Guessing is a defect.

## 6. Docs-only grounding (no MCP server)

For people without the d365fo MCP server — a functional consultant, or a developer before
setup — the analysis half still works, grounded in Microsoft Learn instead of metadata.

- **Allowed:** explore (`analysis.md`), assessments at stage `fdd`, and the FDD. **Not
  allowed:** the TDD, building, review and QA — they need metadata. Stop there and say why.
- **Every claim about the system** comes from a Microsoft Learn page opened in this run (cite
  it), or is labelled **assumption — not checked in your environment**.
- **Never say an object, field or menu item exists in their system.** Name standard ones only
  as Learn describes them ("the *Vendor hold* field on the vendor's Invoice tab, per Learn").
  Customizations, extensions and parameter values are unknown: ask, or list them as
  questions.
- Security: describe standard roles and duties from Learn; current coverage and runtime
  changes are unknown — make them questions, not findings.
- Every work file written this way says so at the top: *"Grounded in Microsoft Learn only —
  not checked against your environment's metadata."*
- When the server is connected later, the architect re-checks every object, field and
  behaviour the FDD names before the TDD (`grounding: metadata`).
