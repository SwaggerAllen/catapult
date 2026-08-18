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
- **The siege port preserves semantics first** (v5 §B.2's mapping):
  mechanical f-string→Liquid conversion, then iteration via the
  harness — never both in one change, or a quality regression is
  unattributable.
- **The meaning-engine discipline governs edits** (v5 §B.2.5,
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
