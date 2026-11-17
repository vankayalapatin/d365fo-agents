---
ticket: <ticket-id>
document: fdd
version: 1
status: draft
author: d365fo-architect
updated: <yyyy-mm-dd>
source: written | imported   # imported = requirements or spec written by someone else (ticket.md)
grounding: metadata | docs-only
signed-off-by:
---

# Functional design — <ticket title>

<docs-only: "Grounded in Microsoft Learn only — not checked against your environment's metadata.">
<imported: "Based on requirements written by <who>; every change made to them is listed in §12.">

Source ticket: `ticket.md` · Assessments: `assessment-finance.md`, `assessment-scm.md`, `assessment-security.md`

## 1. Business need
<Plain-language restatement. Who, what problem, why, how often, how much.>

## 2. Scope
- **In scope:** …
- **Out of scope:** … (and who owns it, e.g. "monthly trend view → Power BI")

## 3. Personas and access
| Persona | Does what | Standard role today | Approves? | View only? |
|---|---|---|---|---|

## 4. Standard behaviour today
<As-is process and what standard D365 already offers, with Learn links.>

## 5. Requirements and fit-gap
| REQ | Requirement | Verdict (standard / configurable / out of scope / customization) | Evidence | Module |
|---|---|---|---|---|

## 6. Acceptance criteria
| AC | REQ | Given | When | Then |
|---|---|---|---|---|

Include negative cases and the switched-off case.

## 7. Functional impacts
| Area | Finance | Supply chain | Notes |
|---|---|---|---|

## 8. Reconciliation
| C | Topic | Finance position | Supply chain position | Resolution | Decided by |
|---|---|---|---|---|---|

"Decided by" is `agreed`, `follow-up round`, or `user` (with the option chosen).

## 9. Security and licensing
| Persona | Access change | License before → after | SoD concern |
|---|---|---|---|

A license raise must be accepted by the user here before sign-off.

## 10. Reversibility
<How the business turns it off, who can, and what happens to data created while it was on.>

## 11. Assumptions, open questions, risks
- **Assumptions:** `A-n` …
- **Open questions:** `Q-n` … (must be empty or explicitly deferred before sign-off)
- **Risks:** …

## 12. Changes to the source (imported only)
| Source item | What I changed | Why (gap found) |
|---|---|---|

<"Not imported" when `source: written`.>

## 13. Sign-off
<Recorded by the architect when the user approves in chat: name, date, version.>
