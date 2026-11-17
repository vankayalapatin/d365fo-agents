---
ticket: <ticket-id>
document: assessment-<finance | scm | security | reporting>
version: 1
status: draft
author: <agent name>
updated: <yyyy-mm-dd>
---

# <Finance | Supply chain | Security | Reporting> assessment — <ticket title>

## 1. Need, in plain words
<One or two sentences: who, what problem, why, how often.>

## 2. Reading discrepancies
| Ticket says | Architect framing says | Which I used, and why |
|---|---|---|

<"None" if none.>

## 3. Standard behaviour today
<What D365 does now for this process, with Learn links opened in this run and any objects
confirmed through the MCP server.>

## 4. Fit-gap
| Need | Rung (standard / configurable / out of scope / customization) | Evidence | Why higher rungs fail |
|---|---|---|---|

## 5. Impacts
| Area | Affected? | Why |
|---|---|---|

## 6. Proposed acceptance criteria
- `<PFX>-AC1` Given … When … Then …
- `<PFX>-AC2` (negative) Given … When … Then … must not …
- `<PFX>-AC3` (switched off) Given the feature is off … Then old behaviour …

## 7. Questions
| ID | Question | Suggested default | If the answer differs |
|---|---|---|---|

## 8. Assumptions
- `<PFX>-A1` …

## 9. Position
- **Requires:** …
- **Prefers:** …

<!-- Security assessments add the security delta table (security-design §8). Reporting
assessments add: report summary, designs found, recommended design, technique, manual
Report Designer checklist. -->
