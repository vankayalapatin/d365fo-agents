---
ticket: <ticket-id>
document: review
version: <n — one per review round>
status: draft
author: d365fo-reviewer
updated: <yyyy-mm-dd>
tdd-version: <TDD version reviewed>
round: <1 | 2>
---

# Technical review — <ticket title>

## Verdict
**Pass** | **Fix needed** | **Escalate to user** (round 2 still failing, or a design problem)

## Evidence run in this review
| Check | Tool call | Result |
|---|---|---|
| Changed files | `get_workspace_info(changes=true)` | |
| Build + BP | from the developer's last build, or `run_bp_check(objects=[…])` | |
| Project registration | `verify_d365fo_project(objects=[…])` | |
| Security coverage | `security_info(mode="coverage")` per new entry point | |

## TDD conformance
| OBJ | In TDD | Implemented | As designed? | Note |
|---|---|---|---|---|

Also list anything changed that is **not** in the TDD.

## Findings
| # | Severity (blocker / major / minor) | Rule (S1–S10 or TDD) | OBJ / object | Evidence | Fix |
|---|---|---|---|---|---|

Blocker = breaks a standard or the TDD; must be fixed. Major = should be fixed this round.
Minor = may be deferred with the user's agreement.

## For the developer
<Ordered list of fixes, by finding number. Nothing else.>
