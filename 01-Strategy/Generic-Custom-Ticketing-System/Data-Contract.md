# Generic Custom Ticketing System: Recommended Data Contract

## Ticket object (minimum fields)
Design the ticket schema so the AI escalation is complete, auditable, and retrievable.

### `Ticket`
- `ticket_id` (string): primary identifier.
- `external_conversation_id` (uuid): maps to chatbot `session_id`.
- `requester_id` / `customer_id` (string): requester identity.
- `subject` (string): short title derived from the initial question.
- `description` (string): initial transcript + context summary.
- `status` (enum): `new|open|pending|on_hold|solved|closed` (or your equivalents).
- `priority` / `severity` (optional): if your org uses it.
- `tags` (string[]): include the 1–2 word categorization tags.
- `ai_escalation_reason` (string): canonical reason code.
- `ai_confidence` (number): evaluator outcome or composite score.
- `evidence` (json): list of `{doc_uri, doc_id, chunk_id, score, retrieved_at}`.
- `resolution_summary` (string): populated on resolution.
- `resolution_references` (json): URLs/paths/doc_ids used to resolve.

## Comment object (message mirroring)

### `TicketComment`
- `comment_id` (string)
- `ticket_id` (string)
- `author_type` (enum): `customer|agent|assistant|system`
- `visibility` (enum): `public|internal`
- `body` (string)
- `source_message_id` (uuid, optional): points to your `MESSAGE.message_id`
- `created_at` (datetime)

**Why**: keeping `source_message_id` enables exact replay and prevents duplication when mirroring across systems.

## Webhook event contract (if supported)

### `ticket.updated`
- `event_id` (string) — unique (idempotency).
- `ticket_id` (string)
- `external_conversation_id` (uuid)
- `changed_fields` (string[])
- `latest_public_comment` (object, optional)
- `latest_internal_note` (object, optional)
- `status` (string)
- `updated_at` (datetime)

**Why**: the orchestrator can route only customer-visible content back to the user, while still ingesting internal notes for summarization and metrics.

