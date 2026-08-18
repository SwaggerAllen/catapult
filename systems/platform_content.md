---
paths:
  - bundles/**
---

# platform_content

The bundle *content* the DSL loads, across **both bundle axes** (v5
§7.18):

- **chain axis** — `bundles/platform-elixir/` (the elixir-target
  layer: convention grammars, template tiers, enforcement profiles)
  and `bundles/default/` (the software-design chain: tier
  declarations, edges, and the prompts ported from SiegeEngine).
- **workflow axis** — the platform workflow layer, carrying the
  default review sequence (a UX review and an engineering review) and
  the default `dev`/`staging` environments.

**Delivery declarations moved off the elixir layer** (v5 §6, corrected
at §7.18): shipping them from the language layer welded the workflow
vocabulary to one target stack, which is exactly what the two-axis
split exists to prevent. They ship from the workflow layer instead,
and the two layers are never `extends:`-related.

A separate system from core_dsl **for the mutex**: prompt iteration
and loader development are unrelated work streams, and one label
covering both would serialize them (v5 §7.5's watch-item logic,
applied preemptively). Prompt tickets carry `system:platform-content`;
loader tickets carry `system:core-dsl`.

## Standing decisions

- **Prompts are content, reviewed as diffs, never inline in code**
  (conventions §11). The harness iterates them; the git history is
  their changelog.
- **The siege port is a re-expression, not a byte conversion** —
  revised (ORC-7). The source is now vendored at `seed-docs/`: siege's
  own prompt chain under `siege-prompts/`, and the mapping this repo
  kept citing as "v5 §B.2", which is really **Appendix B of
  `seed-docs/catapult-spec-v4.md`** — §B never existed in
  `v5-design-decisions.md`, and every citation of it here was wrong.
  The earlier rule (mechanical f-string→Liquid conversion first,
  harness iteration second, never both in one change) was written when
  a byte-level port looked possible. It is retired because **v5 moved
  the structure the prompts are written against** — `resp` restored as
  a tier, `fanin` and the domain/presentational split replaced by
  §4.1's three-way product/backend/frontend split, the product tier
  inserted into the chain head — so there is no tier-for-tier
  correspondence left to convert along. Sequencing a mechanical step
  before an iterative one only buys attributable quality regressions
  when the mechanical step is a real transformation of matching parts;
  here it would be a rewrite wearing a conversion's name.
  **The license is not a second reason, and was briefly recorded as
  one in error.** `bundles/**` is Apache-2.0 and SiegeEngine is
  AGPL-3.0, but siege has a single copyright holder, no third-party
  contributors and no users, so carrying its text into the Apache zone
  is authorized outright (`seed-docs/README.md`). Rewriting is a
  quality judgment, not a permission boundary — worth stating plainly,
  because a rule believed to be a legal constraint stops getting
  re-examined on its merits.
  What the vendored corpus is *for*, then: the v4 documents pin scope,
  identity, handle and generator per tier, which is structural fact
  that survives the rewrite, and the prompts show what siege learned
  about how to ask. Both are there to be read, and quoted where
  quoting is the right call — the constraint is editorial judgment,
  not provenance. The unattributability the old rule guarded against
  is real and gets its successor in the ticket: content deltas from
  siege's semantics are argued in the PR, not discovered later.
- **The meaning-engine discipline governs edits** (v4 §B.2.5,
  SiegeEngine's hard-won rule): each tier's prompt names its
  downstream reader and pushes against category-speak; if a tier's
  output is vague, fix that tier's prompt, don't pass more context
  downstream.
- **The layer carries the default license policy, written literally
  into the generated project** (ORC-16). `mix catapult.audit`'s license
  check is held to a list of SPDX identifiers the project states in its
  own `mix.exs` (`systems/substrate.md`), and the check itself carries
  none: an allowlist compiled into a module that ships everywhere is
  Catapult's legal position imposed on codebases nobody here has read.
  Somebody still has to supply the sane starting value, and that is
  this layer's job rather than the check's — the elixir-target layer is
  what a generated project's `mix.exs` comes from, and it is already
  where the enforcement profiles live.

  **Literally, and this is the whole of the decision.** The five
  identifiers are emitted as data in the project's own file, readable
  and editable in place; never as a call into a shipped module that
  resolves them, which would put the constant back inside the check
  with an extra hop and leave a project unable to read what it is being
  held to. A project that edits the list is not evading a gate, it is
  stating a policy — the distinction `docs/non-goals.md` records
  against the per-dependency waiver, which stays refused.

  Nothing here exists yet: `bundles/` arrives in Phase 3 and the check
  lands before it, so this is recorded now for the ticket that builds
  the layer rather than built now. Until then the only project on the
  path is `components/substrate`, which states its own list by hand
  because it is not a generated project.
- **A generated project's `mix.exs` declares `boundary: [default:
  [type: :strict]]`, not an apps list** (ORC-50), and this is recorded
  now for the same reason the entry above is: the layer does not exist
  yet, and the obvious move when it does is to copy the plane's own
  block, which would be copying a workaround along with it. Catapult
  runs `check: [apps: [...]]` because `components/substrate` is a
  **path** dep and Boundary drops a path dep's boundaries from its
  cached view (`systems/foundation.md`, measured twice). A generated
  project fetches substrate from hex like any other package, so the
  defect has no purchase there and strict is simply available —
  and strict is the better artifact: it needs no list, so it cannot
  have an incomplete one, and `Catapult.Audit.BoundaryApps` is inert
  against it and says so on every green run rather than auditing a
  declaration the project was never asked to maintain. The plane's list
  is the exception that a defect bought, and exceptions are not what a
  generator emits.
- **Stubbing is the instructed pattern for externally-gated scopes**
  (v5 §2.16): the arch and impl prompt material tells the generator —
  design the contract fully, type it opaquely, stub the
  implementation, declare `implementation: stubbed` with its exit
  plan. An agent improvising a stub without the declaration is a
  prompt bug, not an agent judgment call: undeclared stubs are
  exactly the silent half-implementation the doctrine forbids.

## Initial vs target

Initial (Phase 3): default bundle's upstream tiers + ported prompts,
platform-elixir grammar skeletons. Target: full tier set including
product tier (Phase 5), delivery declarations (Phase 7), runtime-
dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.
