---
name: d365fo-security-design
description: Rules for designing D365 F&O security changes — reading current coverage, mapping personas to roles, choosing the smallest change (privilege, duty or role extension), license impact, segregation of duties, data security and the limits of what the AOT shows. Use in the security agent and when writing or reviewing the TDD security section.
---

# Security design

Security is designed **before code**, because it decides who can use the change and which
license they need. A single new "write" entry point in a role can move every user of that
role to a more expensive license.

## When security work is needed

Only when **access changes**. A change that only adds to what the same people already reach —
new fields, controls, enum values or logic on existing forms and tables — inherits the
privileges that cover those forms today, and license follows entry points and access levels,
not fields. So it changes neither who can do what nor anyone's license.

Run the security analysis (the rest of this standard, and the `d365fo-security` agent) only
when the change:
- adds an entry point: menu item, output menu item, service operation, data entity;
- adds or changes a privilege, duty, role or access level;
- asks for access different from today's form — narrower ("only AP managers may set it") or
  for people who don't reach it today;
- changes approval, posting or payment steps in a way that raises a segregation-of-duties
  question.

Otherwise the design gets one line — *"Security: none — inherits who can view and edit
<form> today; no license change"* — with no role list and no security agent run.

## 1. Model (Microsoft)

Role → duty → privilege → permission on an entry point (menu item, service operation, data
entity) with an access level. Roles should get **duties**, not privileges directly. Data
security policies (XDS) *restrict* rows; roles *grant* access.
([Role-based security](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/sysadmin/role-based-security) ·
[Security architecture](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/sysadmin/security-architecture))

## 2. Read the current state first

For every entry point the change adds or touches:

1. `security_info(mode="coverage", objectName=…)` — which privileges, duties and roles reach
   it today, and with which access.
2. `security_info(mode="artifact", artifactType=…, name=…)` — the full chain of the roles the
   personas use.
3. `search(scope="extensions")` for security objects already in the custom model that could
   be reused.
4. `get_object_info(objectType="menu-item", …)` for the license-relevant properties of
   existing menu items you would mirror.

## 3. Map personas to roles

From the FDD's personas (who does it, who approves, who only views), name the standard role
each persona has today. If the persona's role is not known, ask — do not assume System
administrator or a broad role.

## 4. Choose the smallest change

Go down the list; stop at the first that works. Each `SEC-n` change states why the higher
options do not fit.

1. **No change** — existing coverage already grants exactly the needed access.
2. **New privilege(s)** for the new entry point, normally a *Maintain* and a *View* pair, added
   to an **existing standard duty through a duty extension**.
3. **Role extension** adding an existing or new duty to a standard role.
4. **New duty** — only for a genuinely new part of a business process.
5. **New role** — only for a genuinely new persona. Rare; usually a security admin builds it
   at runtime by duplicating a standard role, not in code.

Facts that constrain the choice:
- Security **roles and duties** can be extended to add duties and privileges
  ([extensions](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/extensibility/customization-overlayering-extensions)).
  Standard privileges are not changed — add a new privilege.
- Microsoft recommends copying standard roles rather than modifying them, and not starting
  from fully custom roles
  ([implementation guide](https://learn.microsoft.com/dynamics365/guidance/implementation-guide/security-strategy-product-oa)).
- Grant the lowest access level that meets the need (Read before Update/Create/Delete).

## 5. License impact

- Menu items carry license properties (`ViewUserLicense`, `MaintainUserLicense`). Set them on
  every new menu item to match the persona's intended license; mirror a comparable standard
  menu item and say which.
- For each `SEC-n`, state the persona's license today and after: **unchanged / raised to
  <license> / attach license needed**. A raise needs explicit user acceptance in the FDD.
- After deployment, licensing is verified in the environment with *License usage summary*
  (Security governance); the server cannot compute it.
  ([Prepare for user license validation](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/sysadmin/prepare-for-user-validation))

## 6. Other checks

- **Segregation of duties** — would a role now hold two duties that should be segregated
  (e.g. create vendor and approve vendor payment)? Flag it.
- **Data security** — does a persona need fewer rows (one company, own records)? Then an XDS
  policy, not a narrower role.
  ([XDS policies](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/sysadmin/extensible-data-security-policies))
- **Entities and services** — every new data entity and service operation needs its own
  privilege; check table permissions where the server reports them.
- **Every new entry point** has a privilege (S8). No orphan menu items.

## 7. Limits — say these out loud

The server reads security **defined in code (AOT)**. It cannot see runtime changes made in
an environment through *Security configuration*, user-role assignments, or actual license
consumption. Ask the user whether production roles for the affected personas were changed
at runtime, and record the answer as an assumption if unknown.

## 8. Output — security delta table

| SEC | Persona | Object | Current coverage | Change | Access | License before → after | SoD | Reason |
|---|---|---|---|---|---|---|---|---|

The FDD gets the persona and license columns; the TDD gets the full table with object names
validated by `validate_object_naming`.
