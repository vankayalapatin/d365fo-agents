# Eval set

A fixed set of sample tickets that the agents are re-run against after a change to an agent,
a standard or the hooks. Each one tests a different path through D365 F&O development, so a
change that fixes one ticket can't quietly break another.

## How a case runs

1. Open a session in your D365 repo folder (not a git worktree) and run
   `/d365fo-architect` with the ticket text exactly as written below.
2. Play the business user: answer questions from the ticket's intent; say "don't know" to
   facts the ticket doesn't give. Answer **no** to automated tests unless the case says to
   check it in Test Explorer, and **no** to a red run first.
3. Sign off the FDD and TDD when they're right, let the developer build, then do the Visual
   Studio step it hands you (Rebuild with deploy and sync, tests, UAT).
4. Score it (below), then return the workspace to its starting state.

Several cases can be designed in parallel, one session each, and built together by one
developer session: then all of them need only one Visual Studio round.

## Scoring

| Check | Pass when |
|---|---|
| **Mode** | The architect picks a sensible start (field, quick, full, configuration) and says why |
| **Decision** | The mechanism fits the ticket, and the rejected alternatives are named |
| **Slice** | Every object needed exists, and nothing unneeded was created |
| **Traps** | The case's catch (below) was handled, or the agent stopped and asked |
| **Build** | Compile 0 errors, BP 0 new warnings |
| **Runtime** | The UAT step, Test Explorer run or API call passes in the environment |
| **Weight** | Questions only where the answer changes the design |
| **Hand-off** | Manual steps are exact (menu paths, properties), and none is left unsaid |

## Cases

**Smoke set** (re-run after every change): A1, B1, B9, D4.

### Data model and forms
| Case | Ticket |
|---|---|
| A1 | "Sales wants a *Legacy customer number* (text, 20 characters) on customers, visible and searchable on All customers and on the customer details page." |
| A2 | "Each vendor should have a *Default inspector* — one of our workers — chosen from a lookup on the vendor's General tab." |
| A3 | "AP needs to maintain a list of *vendor risk categories* (code + description) and pick one on each vendor. Only AP managers may maintain the list; everyone who sees vendors may see it." |
| A4 | "We want a switch in AP parameters: *Require risk rating on new vendors*. Off by default. When on, a vendor can't be saved without a rating." |
| A5 | "Add a *Risk rating* filter to the All vendors list so AP can show only High-risk vendors." (needs a *Risk rating* field on vendors) |

### Code extensions
| Case | Ticket |
|---|---|
| B1 | "A purchase order for a vendor on hold for *All* must not be saved — show a clear error." (check in Test Explorer) |
| B2 | "When a new sales line is created, default the *Delivery reason* from the customer." |
| B3 | "Hide the *Delete* button on the vendor form unless the user is an AP manager." |
| B4 | "On the sales order lines grid, make *Unit price* read-only when the line comes from a trade agreement." |
| B5 | "When the *Delivery terms* on a purchase order header change, ask the user whether to update the lines." |
| B6 | "Add a button *Send to vendor portal* on the purchase order action pane that marks the order as sent." (standard vendor collaboration may already cover it) |
| B7 | "Before a sales order is confirmed, check the customer's credit insurance limit and stop confirmation if it's exceeded." |
| B8 | "Whenever a customer is created — by a user, an import or an integration — log who created it in our audit table." |
| B9 | "Show each vendor's number of open purchase orders on the vendor form." |

### Queries and list pages
| Case | Ticket |
|---|---|
| C1 | "On the *Open vendor transactions* inquiry, add the purchase order's *Buyer group*." (several screens fit: the agent should ask which) |
| C2 | "On All sales orders, users in the Online sales team should only see orders from their own sales channel." |

### Integration
| Case | Ticket |
|---|---|
| D1 | "Our risk platform needs to read and create vendor risk categories (from A3) through the API, and AP wants to load the initial list from Excel." |
| D2 | "Same as D1, but only the risk platform reads it — no Excel loads." Variant: "only Excel loads, no API." |
| D3 | "Add the vendor *Risk rating* field to the standard vendor data entity so it imports and exports." |
| D4 | "Our e-commerce site must create sales order holds through an API call: order number, reason code, note. Return a clear error if the order doesn't exist." (check by an API call) |

### Frameworks and process
| Case | Ticket |
|---|---|
| E1 | "Every night, set vendors' risk rating to *High* when they have more than 3 late deliveries in 90 days. AP wants to run it on demand too." |
| E2 | "AP wants to block a vendor from payments while we investigate a complaint." (standard configuration is the right answer) |
| E3 | Run A3, and **while the developer builds** tell the architect: "Actually the description should be 60 characters and the list also needs an *Active* checkbox." |

## Hooks

`../src/hooks/test-hooks.ps1` runs the approval hooks' self-test (break-it cases: approvals
from the wrong source, writes before sign-off, writes outside the design, terminal writes to
AOT files) with nothing else installed. All checks must pass in Windows PowerShell 5.1 and
PowerShell 7.

## Results

Tested on UDE in the Claude desktop app: the smoke set passes (design, sign-off, build, tests
and UAT). LCS Tier-1 VMs and the GitHub Copilot app are not yet verified.
