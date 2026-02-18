# Tailored Strategy: Zendesk

## When to use this variant
Use this strategy when escalations and human handling occur in Zendesk Support (tickets), and you want the bot to create/update tickets and mirror agent responses back to the customer conversation.

## Why Zendesk needs a tailored approach
- Zendesk has strong native concepts for **public replies vs internal notes**, **tags**, **custom fields**, and **triggers/webhooks**—ideal for the “transcript + summary + reason” payload.
- There are **rate limits** and multiple integration paths (webhooks/triggers vs incremental exports), so reliability patterns matter.

## Documents
- [`Integration.md`](Integration.md) — recommended API/webhook design and end-to-end escalation workflow.
- [`Field-Mapping.md`](Field-Mapping.md) — how to map session/message/evidence fields into Zendesk ticket fields, tags, and comments.

