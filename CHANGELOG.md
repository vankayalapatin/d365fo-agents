# Changelog

## 0.2.0 — first public release

- **Eight agents** for D365 F&O, written once in `src/` and generated for the Claude desktop
  app (Code tab) and the GitHub Copilot app: architect (orchestrator), finance and supply
  chain functional, security, reporting, developer, reviewer and QA.
- **Ways to start:** a vague ticket (full analysis), written requirements or an FDD, a quick
  small change, a field-only change, a task whose design is your own request, or "explore:".
- **Gates:** FDD and TDD sign-off; the TDD sign-off approves its build plan.
- **Approval hooks** (PowerShell) enforce the gates: an approval is bound to the question the
  agent asked, writes and builds without one are blocked, and so are writes to objects the
  design doesn't list and terminal writes to AOT files. Self-test: `src/hooks/test-hooks.ps1`.
- **Tests are opt-in:** automated SysTests and a red run first are two questions, both
  default no; every acceptance criterion always gets a manual UAT step.
- **Grounding:** every object, method and label is checked through d365fo-mcp-server; the
  architect checks module references for every standard class a design extends.
- **Tested** on UDE in the Claude desktop app with an eval set (`eval/README.md`).
  **Not yet verified:** LCS Tier-1 cloud-hosted VMs and the GitHub Copilot app.
