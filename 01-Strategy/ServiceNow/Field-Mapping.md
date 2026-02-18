# ServiceNow: Field Mapping (Session ↔ Incident)

## Mapping goals
- Preserve traceability from chat `session_id` to ServiceNow incident `sys_id`.
- Keep customer-visible content separate from internal operational notes.
- Support “continue until resolved” with state transitions and agent updates.

## Recommended incident fields

### Correlation
- `correlation_id` (or custom field): set to your `session_id`.
- Optional custom field: `u_external_conversation_id` (uuid) if you want strict typing.

**Why**: correlation fields are queryable and make sync/polling straightforward.

### Escalation and quality (custom fields if needed)
- `u_ai_escalation_reason` (string/choice)
- `u_ai_confidence` (number/string)
- `u_ai_evidence` (json/text) or store evidence in work notes

### Categorization
- Map your 1–2 word tags to:
  - `category` / `subcategory`, or
  - a custom field if your taxonomy differs.

**Why**: ServiceNow reporting is often built around category/state/assignment group.

## Journal fields (comments vs work notes)
- **Customer-visible**: use the customer comment field (varies by instance conventions).
- **Internal-only**: use `work_notes` for evidence pack, summaries, and decision rationale.

**Why**: aligns with ServiceNow operational practice and reduces the risk of leaking internal data.

## Suggested ServiceNow automations
- On agent customer-visible comment: notify orchestrator (webhook) to mirror back to the user channel.
- On incident resolved/closed: notify orchestrator to finalize session and generate the case summary.

