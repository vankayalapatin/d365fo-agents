---
ticket: <ticket-id>
document: changes
version: 1
status: draft
author: d365fo-architect
updated: <yyyy-mm-dd>
---

# Changes during the work — <ticket title>

Only the architect writes this file. The developer reads it before each object and before each
write, and acknowledges every row in `build-log.md` (*Changes*). One row per change; rows are
never deleted — a cancelled change becomes `withdrawn`.

| CH | Status | Kind | What changes, in plain words | Affects (REQ / AC / OBJ) | Rework of built objects | Approved (who, when, new FDD/TDD version) | From (CL-n) |
|---|---|---|---|---|---|---|---|

- **Status:** `waiting-approval` (do not apply yet) · `ready` (apply from now on) · `withdrawn`.
- **Kind:** `detail` (inside the approved plan) · `requirement` (new or changed need) ·
  `approach` (different design) · `pause` (stop at the next step).
- **Rework:** objects already built under the old rule that must change, from `build-log.md`.
