# Tailored Strategy: Generic Custom Ticketing System

## When to use this variant
Use this strategy when the ticketing system is in-house or bespoke, and you control (or can extend) its data model, APIs, and eventing.

## Core objective (same as baseline)
Automate customer inquiries using a chatbot + Hybrid RAG, and escalate to a human when evidence is insufficient—while preserving a single end-to-end conversation chain until resolution.

## Why this integration is different
- You can design the ticket schema to make AI+human collaboration first-class (transcript, evidence pack, summaries, and decision reasons).
- Eventing may be immature or absent, so you need a reliable update mechanism (webhook preferred; polling as fallback).
- You can embed the “AI guardrails” as platform rules, not just bot logic (e.g., required citation fields, mandatory escalation reasons).

## Documents
- [`Integration.md`](Integration.md) — integration patterns (webhook vs polling), reliability, and workflows.
- [`Data-Contract.md`](Data-Contract.md) — recommended ticket and comment schema fields to support AI escalation and post-resolution learning.

