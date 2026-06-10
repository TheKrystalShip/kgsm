---
applyTo: "docs/specs/testing-framework/**"
description: "Enforces delegation to the @testing agent for any interaction with testing framework documentation. Use when: reading, editing, or referencing testing specification files."
---

## Testing Documentation Delegation Rule

**STOP.** These documentation files are owned by the `@testing` agent.

Testing framework specifications and documentation (`docs/specs/testing-framework/`) are managed by the `@testing` agent. If you need to:

- **Read or interpret** testing specifications → delegate to `@testing`
- **Update documentation** to reflect framework changes → delegate to `@testing`
- **Reference testing conventions** for writing tests → delegate to `@testing`

**How to delegate:** Invoke `@testing` as a subagent with your question or task.
