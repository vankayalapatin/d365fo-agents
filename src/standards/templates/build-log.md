---
ticket: <ticket-id>
document: build-log
version: <n — one per developer run>
status: in-progress | needs-input | done | blocked
author: d365fo-developer
updated: <yyyy-mm-dd>
tdd-version: <signed-off TDD version being implemented>
round: <0 = first build, 1–2 = fix rounds>
---

# Build log — <ticket title>

## Progress
| OBJ / T | Action | Done? | Tool result (one line) | Notes |
|---|---|---|---|---|

The next run resumes at the first row not done.

## Builds
| # | When | Call | Result | Errors / BP findings |
|---|---|---|---|---|

## Tests
| T | Test class.method | Red run (before logic) | Green run (after logic) | Source of result (tool / user in VS) |
|---|---|---|---|---|

The red-run column is "n/a" unless the TDD says `automated-tests: yes, red first`; then a
logic test with no red run is not evidence. A *guard* test (S9) writes "guard" there. With
`automated-tests: no` this table is empty.

## Changes
| CH | Seen (object, step, time) | Applied from | Already built under the old rule | Rework added |
|---|---|---|---|---|

One row per `changes.md` row, so none is applied twice.

## Waiting on the user
<Manual steps still open, with exact instructions. Empty when none.>

## Deviations
<Anything that differs from the TDD, and the TDD issue raised for it. Empty when none.>
