---
applyTo: "tests/**"
description: "Enforces delegation to the @testing agent for any interaction with test files. Use when: editing, creating, reading, or analyzing any file in the tests/ directory."
---

## Testing Framework Delegation Rule

**STOP.** You are interacting with a file owned by the `@testing` agent.

The KGSM testing framework (`tests/`) is managed exclusively by the `@testing` agent. If you need to:

- **Read or understand** a test file or framework module → delegate to `@testing`
- **Create or modify** a test file → delegate to `@testing`
- **Debug a test failure** → delegate to `@testing`
- **Add assertions or hooks** → delegate to `@testing`

**How to delegate:** Invoke `@testing` as a subagent with a detailed prompt describing what you need. Include the module name, expected behavior, relevant context, and what you want done.

**Do NOT:**
- Write test code directly — `@testing` knows the framework conventions
- Modify framework modules (`tests/framework/*.sh`) without `@testing`
- Guess at test structure — `@testing` has the template and naming rules
