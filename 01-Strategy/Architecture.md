# Reference Architecture & Workflows

## Goal
Automate customer support inquiries with a chatbot pattern backed by Hybrid RAG, and escalate to a live representative when answer quality is below a defined threshold—without breaking the conversation chain.

## Architecture (logical components)

```mermaid
flowchart LR
  U[Customer] -->|Web/Chat/Email/SMS| CH[Channel Adapter]
  CH --> GW[Conversation Gateway API]

  GW --> SS[(Session Store)]
  GW --> ORCH[Conversation Orchestrator]

  ORCH --> POL[Policy & Safety Guardrails]
  ORCH --> RET[Hybrid Retrieval]
  RET --> DOC[(Document Store)]
  RET --> VEC[(Vector Index)]
  RET --> FTS[(Full-text Index)]
  RET --> RR[Reranker]

  ORCH --> LLM[LLM Provider]
  ORCH --> EVAL[Answer Quality Evaluator]

  ORCH -->|if low confidence| ESC[Escalation Service]
  ESC --> TKT[Ticketing System / Agent Desk]
  ESC --> AG[Human Agent]

  AG -->|reply/update| TKT --> ORCH --> GW --> CH --> U

  ORCH --> OBS[Observability & Metrics]
  ORCH --> KB[(Case/Resolution Knowledge Base)]
```

### Why these components
- **Channel Adapter + Gateway**: isolates channel-specific quirks (email threading, chat typing, auth) from core logic; reduces coupling and improves testability.
- **Orchestrator (state machine)**: conversation handling is inherently stateful (session, retries, escalation, resolution). A dedicated orchestrator makes “continue until resolved” reliable and auditable.
- **Hybrid Retrieval + Reranking**: support content often has both keyword-heavy and semantic queries; hybrid retrieval improves recall while reranking improves precision.
- **Answer Quality Evaluator**: the “do not guess” requirement needs an explicit gate that can block responses even if the LLM is willing to answer.
- **Ticketing integration**: ensures escalations land in the existing human workflow with full context.

## Core workflow: answer with evidence

```mermaid
sequenceDiagram
  autonumber
  participant User as Customer
  participant GW as Gateway
  participant Or as Orchestrator
  participant Ret as Hybrid Retrieval
  participant LLM as LLM
  participant Eval as Quality Gate
  participant SS as Session Store

  User->>GW: Ask question
  GW->>SS: Persist message (raw)
  GW->>Or: Route message + session_id

  Or->>Ret: Retrieve (hybrid) using query + session context
  Ret-->>Or: Top sources + scores + citations

  Or->>LLM: Generate answer constrained to sources
  LLM-->>Or: Draft answer + cited sources

  Or->>Eval: Validate grounding + confidence
  Eval-->>Or: Pass/Fail + reason

  alt Pass
    Or->>SS: Persist assistant response + source refs
    Or-->>GW: Return answer + citations
    GW-->>User: Respond
  else Fail
    Or-->>GW: Trigger escalation (see next flow)
  end
```

### Why “citations-first”
Requiring citations (URLs, document paths, KB article IDs, or structured record IDs) operationalizes “don’t hallucinate”. It also improves debuggability: when an answer is wrong, the fix is usually retrieval/indexing—not prompt tweaks.

## Escalation workflow: low confidence → human (without losing context)

```mermaid
sequenceDiagram
  autonumber
  participant User as Customer
  participant GW as Gateway
  participant Or as Orchestrator
  participant Eval as Quality Gate
  participant Esc as Escalation Service
  participant TKT as Ticketing System
  participant Agent as Human Agent
  participant SS as Session Store

  Or->>Eval: Validate answerability
  Eval-->>Or: Fail (insufficient evidence)

  Or->>SS: Persist escalation event + reason
  Or->>Esc: Create/Update ticket request
  Esc->>TKT: Create ticket with transcript + summary + suggested next steps

  TKT-->>Agent: Assign/notify
  Agent->>TKT: Respond/resolve
  TKT-->>Esc: Ticket update (webhook/poll)
  Esc-->>Or: Agent message + resolution state

  Or->>SS: Persist agent response + resolution
  Or-->>GW: Route agent message to customer
  GW-->>User: Human response (same conversation thread)
```

### What gets sent to the human agent (and why)
- **Transcript**: prevents the user from repeating information; reduces handle time.
- **Context summary**: lets an agent skim quickly; summary is also re-usable for post-resolution.
- **Retrieval evidence + “why failed”**: helps agents see what the bot searched and why it refused to answer (missing doc, conflicting sources, low similarity, no entitlement).
- **Suggested clarifying questions**: keeps momentum and improves data capture for later retrieval.

## Component choices (recommended defaults)
These are defaults you can implement quickly, while keeping provider flexibility.

- **Session store**: PostgreSQL (relational integrity, easy analytics, durable audit trail).
- **Hybrid search**:
  - Default: PostgreSQL full-text (`tsvector`) + `pgvector` for semantic search in the same data plane.
  - Reasoning: simplest operationally (one DB), good enough for many orgs, easy to evolve.
  - Scale-out option: dedicated search (OpenSearch/Elasticsearch/Azure AI Search) + vector DB when corpus/traffic demands it.
- **Orchestration**: a small service with an explicit conversation state machine (rather than embedding state into prompts), because it’s safer and easier to reason about escalation/resolution.

