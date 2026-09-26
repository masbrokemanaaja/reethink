---
name: modular-code-guard
description: >-
  Keeps code modular and prevents spaghetti: single responsibility, small
  focused units, separation of concerns, explicit module boundaries, and a
  dependency direction that points inward. Use during any development,
  refactoring, or code-review task, before declaring a multi-file change done,
  and whenever the user says "modular-code-guard", "keep it modular", "avoid
  spaghetti code", "clean up the structure", "this is getting tangled",
  "jangan spaghetti", "rapikan strukturnya", or worries the code is getting
  tangled. This one governs the shape of what gets written, not the
  process of writing it.
license: MIT
metadata:
  author: ree_es97
  homepage: https://reetech.web.id
  source: https://github.com/masbrokemanaaja/reethink
  version: "1.2.0"
---

# Modular Code Guard

The goal is code where each piece has one clear job, boundaries are obvious,
and a change in one place does not ripple everywhere.

Follow the repository's existing structure and naming. A "more modular" layout
that fights the conventions already in the repo is not an improvement.

## Core rules

1. **Single responsibility.** Each function, class, module or component does one
   thing. If describing it needs an "and", split it.
2. **Small units.** If a function scrolls off the screen or nests more than
   about three levels, extract.
3. **Separation of concerns.** Keep the layers apart: transport and controllers,
   business logic, data access, presentation. No SQL in a controller, no
   business rules in a template.
4. **Explicit boundaries.** Modules talk through small, named interfaces, not by
   reaching into each other's internals. Export only what callers need.
5. **Dependency direction points inward.** Business logic must not depend on
   frameworks, drivers or UI. Depend on abstractions and inject them.
6. **No god files.** Break up any file or class that has quietly accumulated
   unrelated responsibilities.
7. **DRY within reason.** Extract real duplication. Do not invent an abstraction
   for two lines that merely look alike; that trades one tangle for another.
8. **Low coupling, high cohesion.** What changes together lives together; what
   does not stays apart.

## Before declaring the change done

Answer these against the actual diff, not from memory:

- Can each new or touched unit's responsibility be named in one short phrase?
- Are I/O, logic, data and UI in separate places?
- Would someone new find where a given behaviour lives without being told?
- Is the change contained, or does it ripple into unrelated modules?
- Did any file quietly become a dumping ground in this change?

Anything answered badly is a finding. Fix it or say plainly why it stays.

## Verifying a refactor did not change behaviour

A modularity change must be provably behaviour-preserving, or it is a rewrite
wearing a refactor's name.

1. Establish the baseline first: run the existing tests, or the command that
   exercises the code, and record the output before touching anything.
2. Extract one responsibility at a time. Do not batch unrelated moves into one
   step.
3. Re-run the same command after each step and compare against the baseline.
4. If there is no test covering the seam being moved, either add one first or
   state in the report that the step is unverified. Do not imply it was checked.

## When it is already spaghetti

Refactor incrementally. Find the seams, move one responsibility, verify, repeat.
Do not rewrite everything at once: a large rewrite removes the ability to tell
which step broke what, which is the one thing that makes tangled code fixable.
