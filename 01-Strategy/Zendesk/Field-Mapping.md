# Zendesk: Field Mapping (Session ↔ Ticket)

## Mapping goals
- Preserve a single chain from chat `session_id` to Zendesk `ticket_id`.
- Store transcript, context summary, evidence, and escalation reasons in Zendesk in a way agents will actually use.
- Keep customer-visible content clean and safe (no evidence scores unless desired).

## Recommended Zendesk fields

### Correlation
- `external_conversation_id` (custom field): your `session_id`.
- `external_id` (ticket field, optional): also set to `session_id` if it fits your ecosystem.

**Why**: custom fields are queryable and reliable; `external_id` is helpful for cross-system joins but may be used by other integrations.

### Escalation and quality
- `ai_escalation_reason` (custom field, enum/string): canonical reason code.
- `ai_confidence` (custom field, number/string): evaluator outcome.
- Ticket tag `ai_escalated`.

### Categorization
- Zendesk tags: include your required 1–2 word tags (e.g., `billing`, `login`).

**Why**: tags are lightweight, searchable, and align with Zendesk reporting.

## Comment conventions

### Public comments (customer-visible)
- Agent replies that should go back to the customer.
- Optional: short “we’re escalating you to a human” message from the bot.

### Internal notes (agent-facing)
- Evidence pack: `{doc_uri/doc_id, chunk_id, retrieved_at, score}`.
- Conversation summary (rolling).
- “Why the bot refused” explanation.

**Why**: separates customer experience from operational details and keeps agents effective.

## Suggested automation in Zendesk
- Trigger: on **public comment added by agent** → call webhook to your orchestrator with `ticket_id` and latest comment.
- Trigger: on **status solved/closed** → call webhook to finalize the session and generate the case summary.

