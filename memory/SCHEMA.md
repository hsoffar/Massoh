# Memory — schema + mechanism (portable; the FACTS are never portable)

Memory = accreted, project-specific learnings that aren't derivable from the code or git history.
The **mechanism** (this file) ships with Massoh; the **memories themselves** live only in the host
project (and/or Claude's per-project memory dir) and are **never** copied upstream.

## What a memory is
One file = one durable fact, with frontmatter:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary — used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-name]].>
```

## Types
- **user** — who the owner is (role, expertise, preferences).
- **feedback** — guidance on how the agent should work (corrections + confirmed approaches); include
  the why.
- **project** — ongoing work, goals, constraints not derivable from the code; convert relative dates
  to absolute.
- **reference** — pointers to external resources (URLs, dashboards, tickets).

## Rules
- **One fact per file.** Update the existing file rather than duplicating; delete a memory that
  turns out wrong.
- **Don't store what the repo already records** (code structure, past fixes, git history, CHARTER).
  If asked to "remember" such a thing, capture what was *non-obvious* about it instead.
- Keep an index (`memory/MEMORY.md`): one line per memory (`- [Title](file.md) — hook`), no content.
- Recalled memories reflect what was true when written — **verify a named file/flag still exists**
  before acting on it.

## Boundary
Memory is **host-only**. When a "memory" turns out to be reusable *workflow* (true for any project),
it isn't memory — promote it **upstream into Massoh** (a policy/guardrail), and leave the host memory
as a pointer.
