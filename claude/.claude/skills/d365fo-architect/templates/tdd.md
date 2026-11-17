---
ticket: <ticket-id>
document: tdd
version: 1
status: draft
author: d365fo-architect
updated: <yyyy-mm-dd>
fdd-version: <signed-off FDD version this TDD implements>
type: code | configuration | mixed | field
automated-tests: no | yes | yes, red first   # two questions at the TDD; both default no (S9)
signed-off-by:
---

<!-- configuration: §4 says "None — configuration only"; §6, §12 and §13 carry the design.
     mixed: §4 lists only what is built; §6 and §13 also list the setup.
     field: no FDD (fdd-version: none); only §1, §4, §5 (with each control's form path), §8,
     §9 (one line), §12 (UAT steps) and §15. -->

# Technical design — <ticket title>

## 1. Workspace
| Item | Value (from `get_workspace_info` in this run) |
|---|---|
| Environment type | |
| Model | |
| Prefix | |
| Extension naming style | |
| Project | |

## 2. Traceability
| AC | Objects | Tests |
|---|---|---|

Every AC from the FDD appears here. An AC with no test is a gap and blocks sign-off.

## 3. Decisions
| D | Decision | Rejected alternative | Reason | Standard |
|---|---|---|---|---|

Covers at least: extension mechanism, where configuration lives (S1), the reversibility
switch (S2), batch vs interactive (S6), and any S7 exception.

## 4. Objects
| OBJ | Action (create / extend / modify) | Type | Name | Base object | Purpose | AC | Grounding |
|---|---|---|---|---|---|---|---|

- New names were checked with `validate_object_naming` / `prepare(mode="create")`.
- Extended objects and methods were confirmed with `get_object_info` / `prepare(mode="change")`;
  "Grounding" says which call proved it.
- Reuse existing extension classes in the model where `prepare` lists them.
- Module references: every package the code and tests use is in the model descriptor, or a
  row here adds it (`add-module-reference`). "None needed" is a checked statement, not a default.

## 5. Data model
<Tables, fields (with EDTs), indexes, relations, table extensions. Each field: name, EDT,
label, mandatory, default.>

## 6. Configuration and switch
<Parameter fields, setup tables and forms, number sequences; the S2 switch, its default
(off), and where it is turned on.>

## 7. Logic
<Per OBJ: methods, CoC targets with the exact signature source, event subscriptions,
validation and error messages (as labels), transaction boundaries.>

### How it plugs in
<Required when the code hooks in (CoC, event handler, delegate) more than one call away from
the form, button or batch job the user starts from; otherwise "Not applicable — the hook is
on the entry point itself".>

| Step | Class.method (or form / menu item) | What happens here | Proved by (tool call) |
|---|---|---|---|

- **Delegates and events:** `Class.delegate` — who raises it and when, its signature, our
  subscriber, and what the subscriber may change.
- **Why this point:** the hook points rejected and why (too early, runs twice, misses batch).
- **Routes not covered:** other ways into the same logic (data entity import, batch,
  intercompany, API) and whether that is intended.
- **Breakpoints to confirm:** 2–3 `Class.method` lines a developer can break on in Visual
  Studio. This path is traced from source, not run.

## 8. Labels
| Label ID | Text (en-us) | Reused or new | Used by |
|---|---|---|---|

## 9. Security
<Security delta table from `assessment-security.md` (security-design §8), with final object
names and license properties for every new menu item.>

## 10. Reporting
<Only if a report is touched: technique, chosen design and why, objects, and the manual
Report Designer checklist from `assessment-reporting.md`. Otherwise "Not applicable".>

## 11. Performance and volume
<Expected volumes, set-based choices, caching, batch scheduling, locking.>

## 12. Test plan
| T | AC | Type (SysTest / manual UAT) | Class.method or steps | Expected result |
|---|---|---|---|---|

Every AC has a manual UAT step, naming each place by its client caption. SysTests appear only when the header says
`automated-tests: yes` (written with the logic, run green once) or `yes, red first` (written
before the logic and run red first). Metadata with no code behind it gets a UAT step, not a SysTest; a test the ticket asks
for anyway is marked *guard* (S9 *What S9 tests*).

## 13. Deployment and setup
<Build, database sync, report deployment, Feature management enablement, parameter setup,
Print management setup, security assignment — in order, per environment.>

### Build phases
<Only when §4 has more than about eight objects or spans more than one layer; otherwise
"One phase". In dependency order, in plain words, each phase one developer run ending with an
MCP build and BP check. Visual Studio deploy, sync and tests run once, after the last phase.>

| Phase | In plain words | Objects (OBJ) |
|---|---|---|

## 14. Risks and open items
<Anything that must be checked in an environment the server cannot see.>

## 15. Sign-off
Signing off this TDD approves its build plan: creating and changing the objects in §4, the
tests in §12, and the builds and syncs in §13. Anything else needs a new approval. Setup steps
in §6 and §13 are applied by the user's team; no agent changes environment data.

<Recorded by the architect when the user approves in chat: name, date, version.>
