# Tailored Strategy: ServiceNow

## When to use this variant
Use this strategy when escalations and human handling occur in ServiceNow (typically `incident`), and you want the bot to create/update records and mirror agent responses back to the customer.

## Why ServiceNow needs a tailored approach
- ServiceNow’s workflow is strongly driven by **states**, **assignments**, and **ACLs**; integration must respect governance and domain separation.
- Comments have distinct semantics (e.g., **customer-visible comments** vs **work notes**), which map cleanly to bot needs.
- Many enterprises require integration through controlled paths (OAuth, MID Server, scripted APIs).

## Documents
- [`Integration.md`](Integration.md) — recommended Table API patterns, eventing, and reliability.
- [`Field-Mapping.md`](Field-Mapping.md) — mapping from session/message/evidence to `incident` fields, comments, and work notes.

