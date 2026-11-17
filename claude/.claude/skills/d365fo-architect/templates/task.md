---
ticket: <ticket-id>
document: task
version: 1
status: draft | signed-off
author: d365fo-architect
updated: <yyyy-mm-dd>
automated-tests: no | yes | yes, red first   # default no (S9)
---

# Task — <short title>

## Request
<The user's request, word for word, as one quote block. Never edited: the hooks check that
the stamped request appears here unchanged.>

## Objects
| Name | Action (create / extend / modify) | Type | Base object | Why (from the request) |
|---|---|---|---|---|

Only objects the request names or needs. The user's go on "<ticket> task card" approves this
list; an object added later needs "approve object X". Extension names may be the base object
(the tool adds the suffix).

## Standards check
<"None broken", or one line per standard the request breaks, with the user's answer:
"S1: the 500 limit is hardcoded — user: keep as asked".>

## How it plugs in
<Only when the request hooks in away from the entry point: the short call path, delegate and
breakpoints, as in the TDD template's §7 *How it plugs in*. Otherwise "Not applicable".>

## Test steps
<Manual steps a user follows to see it work; SysTests only with automated-tests: yes (or yes, red first).>
