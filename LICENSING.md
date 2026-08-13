# Licensing

**Status:** posture adopted 2026-08-12, ahead of the first public
release. The repo is private today; `LICENSE` files carrying the
full texts land when it opens, and a counsel pass happens before
that. This document is the policy and the map; it is not legal
advice.

## The split, and why it exists

Catapult is two kinds of code with opposite licensing needs:

- **The plane** — the control plane itself (engine, delivery,
  generation coordination, dashboard, DSL loader) — is
  **AGPL-3.0-only**. The plane is internal-use, network-facing
  software: plain GPL would impose nothing on anyone, and
  permissive licensing would donate the hosted product to whoever
  wants to run it. AGPL §13 is the provision that makes copyleft
  mean something for this shape of program.
- **Everything that ships into a generated project** is
  **Apache-2.0**. Generated applications link the substrate,
  compile in registry components, and receive bundle template
  content verbatim. If any of that were copyleft, every customer
  application would arguably inherit it — which would end the
  product. Permissiveness here is not generosity; it is a hard
  correctness requirement of the business, and the single most
  important rule in this document.

## The map

| Paths | License |
| --- | --- |
| `components/**` (substrate today; every future shipped component) | Apache-2.0 |
| `bundles/**` (platform layer, default chain, prompts, templates) | Apache-2.0 |
| Future client corpus packages (`platform-client-ts`) and all registry-published artifacts | Apache-2.0 |
| Everything else — `lib/`, `priv/`, `test/`, `docs/`, `systems/`, repo root | AGPL-3.0-only |

New files take their directory's license. A new shipped component
is a new `components/*` entry and is Apache-2.0 by construction.

## The policy, with its enforcement ladder

**Nothing that ships into a generated project may be copyleft** —
no AGPL/GPL/LGPL code copied in, no copyleft dependency added to a
shipped mix project. Enforcement, on the v5 §4.5 ladder:

- **Structural (exists):** the shipped layer is separate mix
  projects, path-depended *from* the plane — substrate code cannot
  reference plane modules at compile time, so plane (AGPL) code
  cannot leak into shipped artifacts through the dependency graph.
- **Prose (this document, CLAUDE.md):** the split is a recorded
  load-bearing invariant; agents and reviewers are told.
- **Test (planned, ticketed):** a license-inventory check in
  `mix catapult.audit` — the dependency licenses of every
  `components/*` project against a permissive allowlist, failing
  the audit on violation. Filed as a backlog ticket per §4.5's
  enforcement-gap-visibility rule.

## Contributions

**No outside contribution is accepted without a signed CLA** —
individual or entity as appropriate — granting rights sufficient to
distribute the contribution under licenses of the project's
choosing (the Project Harmony "any license" grant or equivalent).
DCO sign-off alone is not sufficient. This is not bureaucracy for
its own sake: the CLA is what keeps the licensing options above
(and any future commercial license) available at all, and it cannot
be retrofitted after the first un-covered contribution lands. The
agreements and signature capture (CLA Assistant or equivalent) must
be live before the repository opens.

**Registry contributions** (community bundles, prompts, policies,
templates — v5 §8): inbound under Apache-2.0 or a compatible
permissive grant, because community artifacts compile into customer
applications. The central registry accepts nothing before these
terms are posted.

## Choices recorded for counsel review

- **AGPL-3.0-only, not -or-later**: with a CLA in hand the project
  can relicense deliberately, so "-or-later" buys nothing and cedes
  control to hypothetical future license versions.
- The Apache-2.0/AGPL-3.0 boundary as drawn above (in particular:
  prompts and templates as Apache-2.0 content).
- Trademark: the name and marks are not licensed by any of the
  above; a trademark policy is wanted by first release (the AGPL
  fork keeping the name is the scenario to preclude).
