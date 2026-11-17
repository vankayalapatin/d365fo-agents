---
ticket: <ticket-id>
document: qa
version: <n>
status: draft
author: d365fo-qa
updated: <yyyy-mm-dd>
fdd-version: <signed-off FDD version tested against>
---

# Business acceptance — <ticket title>

## Verdict
**Accepted** | **Accepted with a minor finding** (cosmetic only: label, help text, caption) | **Not accepted** (list failing or uncovered ACs) | **Escalate to user**

## Acceptance criteria
| AC | Given / When / Then (from the FDD) | Evidence | Result |
|---|---|---|---|

Result: `pass (automated)` — a SysTest that maps to this AC passed in this run ·
`pass (manual pending)` — covered by a UAT step below, not yet run by a person ·
`fail` · `not covered`.

## Business checks
| Check | Result | Note |
|---|---|---|
| Switched-off case behaves like before | | |
| Personas can reach the function with the planned roles only | | |
| No user-facing text without a label | | |
| Reversibility path in the FDD is real (setup exists, default off) | | |

## UAT script
For a business user in a test environment. One block per AC.

### UAT-<n> — covers AC-<n>
- **Role:** <persona and role>
- **Setup:** <parameters, feature switch, test data>
- **Steps:** 1. Go to <navigation path> … 2. …
- **Expected:** …
- **Result:** ☐ pass ☐ fail — tester, date

## For the developer
<Failing or uncovered ACs, in business terms. Nothing else.>
