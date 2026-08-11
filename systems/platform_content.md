---
paths:
  - bundles/**
---

# platform_content

The bundle *content* the DSL loads: `bundles/platform-elixir/` (the
elixir-target layer — convention grammars, template tiers,
enforcement profiles, delivery declarations) and `bundles/default/`
(the software-design chain: tier declarations, edges, and the
prompts ported from SiegeEngine).

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

## Initial vs target

Initial (Phase 3): default bundle's upstream tiers + ported prompts,
platform-elixir grammar skeletons. Target: full tier set including
product tier (Phase 5), delivery declarations (Phase 7), runtime-
dialect example content (Phase 8).

## Depends on

core_dsl defines what these files may say; generation renders them.
