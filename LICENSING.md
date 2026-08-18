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

New files take their directory's license. **The table above is
descriptive, not the rule** — it records where things happen to live
today, which is a useful map and a poor policy: it cannot express a
component that is deliberately not open source, and the hosted tier
will have those.

## Classification: declared, not inferred from a path

**Every component declares two facts about itself; the project
declares the policy over them.** The audit checks the first against
the second, so a component in the wrong class is a build failure
rather than a licensing surprise.

The declared facts, on the component registry (v5 §2.2):

- **`distribution`** — how the component reaches the people who use
  it, which is what license obligations actually key on:
  - **`:distributed`** — conveyed to third parties: a shipped
    library, a published package, code generated into a customer's
    repository. Copyleft anywhere in its dependencies propagates to
    every recipient.
  - **`:service`** — runs on infrastructure its operator controls and
    is reached over a network. **AGPL §13 triggers here and plain GPL
    does not**, which is the whole reason this is its own class
    rather than a flavour of the one above.
  - **`:internal`** — neither conveyed nor network-reachable: build
    tooling, ops scripts, fixtures. Practically nothing triggers.
- **`license`** — the SPDX identifier this component's own code
  carries. SPDX because it is the vocabulary every other tool
  already speaks; inventing names here would make the declaration
  unreadable to anything but us.

**The classes are deliberately not our business model.** "Shipped /
hosted / plane" would have been shorter and would have made this
useless to anybody else. The three above are derived from how
licenses actually work, so a project that dual-licenses a library, or
one that bans copyleft for procurement reasons rather than product
ones, gets the same three classes and writes a different policy over
them.

The policy, which is ours and which another project would replace:

| `distribution` | our code | dependencies |
| --- | --- | --- |
| `:distributed` | Apache-2.0 | **permissive only** (Apache-2.0, MIT, BSD-2/3, ISC). A copyleft dependency here reaches every generated application; this is the rule the whole document exists for. |
| `:service`, ours | AGPL-3.0-only | anything — we offer source, so nothing a dependency asks for is a cost we are not already paying. |
| `:service`, proprietary (hosted tier) | proprietary (`LicenseRef-*`) | **the same list**, and for its own reason: AGPL §13 would oblige us to offer source to our own users, defeating the point of the component being closed. Not "no copyleft" — "everything except copyleft" cannot be enumerated, so a denylist would have the check deciding the copyleft-ness of identifiers it has never seen, which is a guess running in the permissive direction. `MPL-2.0` and `EPL-2.0` are therefore outside this row until a project's list says otherwise, which is a line in one `mix.exs` rather than a release of the check. |
| `:internal` | anything | anything |

**Why a declaration is enough, without a path to back it up.** The
objection to declaring is that a declaration can be wrong where a
directory cannot. What answers it is that these registries are
projected into the doc graph: a component's class is not a field
buried in a module that only the compiler reads, it is part of the
documented surface, reviewed like any other declaration and visible
to anyone reading the architecture. A wrong class is therefore
wrong *in public*, which is the property the path rule was providing
and the only one it was providing.

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
- **Test (exists, ORC-16):** a license-inventory check in
  `mix catapult.audit`. Every dependency a consumer of the project
  would fetch — the transitive closure over hex metadata already on
  disk, offline — against **the list of SPDX identifiers the project
  states in its own `mix.exs`**, failing the audit on any it cannot
  place. It is armed by declaration and never by a path: a project's
  `package: [licenses: [...]]` and its components' `licensing/0`,
  read together, decide *whether* a tree is checked and for which of
  the reasons in the table above; the list decides *against what*.
  `components/substrate` states the five identifiers this document
  already argues for, which is that argument in a form the audit can
  read:

      licensing: [allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]

  The list is the project's rather than the tool's because
  `Catapult.Audit.License` ships into every generated project, and
  five identifiers compiled into it would be our legal position
  imposed on codebases nobody here has read. A project that states no
  list has *declined* the check and every run says so on stdout;
  there is no per-dependency waiver, and none is coming
  (`docs/non-goals.md`). What the check honestly claims is that no
  dependency in a checked tree **declares** terms nobody accepted —
  hex metadata is the publisher's own assertion, and the counsel pass
  below is what verification would mean.

  **A dependency with no hex metadata is not an automatic failure**
  (ORC-74) — git-distributed dependencies, Catapult's own components
  included once §3.1 lands them that way, never carry
  `hex_metadata.config` at all. Resolution is an ordered rung ladder,
  first answer wins, no reconciliation between rungs
  (`systems/substrate.md`): hex metadata, then the dependency's own
  `licensing/0` if it is a Catapult component, then an explicit
  `SPDX-License-Identifier:` line in its LICENSE file if it is a
  third-party one, then `overrides:` in `mix.exs`, then unresolved —
  which still fails, exactly as before the ladder existed. The
  practical change for a human: `overrides:` now only supplies a fact
  where nothing above it could, and can no longer correct a
  present-but-unrecognized hex metadata spelling — that residue is
  what the project's own `allow:` list is for.

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
- **Dependency licenses inside a proprietary `:service` component.**
  The table above bans AGPL there on the reasoning that §13 obliges
  an offer of source to network users, which is the same argument we
  rely on for choosing AGPL ourselves and is safe to act on. Plain
  GPL arguably imposes nothing on a service that conveys nothing, and
  that is the open question — but it is a *permission* rather than a
  restriction, and the cost of being wrong about it is a component we
  cannot keep closed, so the row holds proprietary `:service` to the
  same list as the shipped layer until counsel says otherwise. A list
  is cheap to widen and expensive to narrow after something has
  shipped against it, and widening it is now one reviewed line in one
  project's `mix.exs` rather than a change to the check.
