---
name: d365fo-scm-checklist
description: Supply chain impact checklist for D365 F&O changes — procurement, sales, pricing, product information, inventory, costing, warehouse, transportation, production, planning, quality. Use in the supply chain functional agent.
---

# Supply chain impact checklist

For each area: **affected / not affected / unknown**, one line of why. Look up the standard
behaviour on Microsoft Learn before claiming a gap.

| Area | What to check |
|---|---|
| **Procurement** | Purchase requisitions, purchase orders, purchase agreements, vendor collaboration, product receipt, change management / PO approval workflow, charges. |
| **Sales** | Sales quotations, sales orders, order holds, delivery dates (ATP/CTP), confirmation, packing slip, invoicing, returns (RMA), customer-specific rules. |
| **Pricing and discounts** | Trade agreements, price/discount groups, charges, rebates; whether the change alters the price a user sees or posts. |
| **Product information** | Released products, item model groups, storage and tracking dimension groups, variants, units and conversions. |
| **Inventory** | On-hand, reservations, inventory journals (movement, counting, transfer), quarantine/blocking, inventory dimensions used. |
| **Costing** | Costing method (FIFO, weighted average, standard cost, …), cost price updates, inventory close / recalculation, what the change does to inventory value. |
| **Warehouse management** | Whether the warehouse uses WMS processes; work creation, location directives, waves, loads, mobile app screens; picking, packing, shipping. |
| **Transportation** | Rates, routes, carriers, freight reconciliation. |
| **Production** | BOMs, routes, production orders, batch orders, consumption and reporting as finished. |
| **Master planning** | Coverage settings, planned orders, firming; whether new data changes planning results. |
| **Quality** | Quality orders, test groups, non-conformance. |
| **Business documents** | Picking lists, packing slips, PO, confirmations, delivery notes that would change — flag for reporting. |
| **Number sequences** | Order, journal and document numbering. |
| **Volume and timing** | Lines per order, orders per day, peak periods, warehouse throughput; interactive vs batch. |

Supply chain usually **requires**: no extra steps or delay for warehouse and order-entry users,
correct inventory quantities and dimensions, planning that still works, mobile app flows that
stay usable. State these explicitly as your position when they apply.
