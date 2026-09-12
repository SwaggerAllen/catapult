# DSL usage census: `bundles/default` and `bundles/default-flow`

Scope: the 83 YAML files (2692 lines). Non-YAML counted only: 36 `prompts/**/*.liquid` (17 base, 17 `review/`, 2 `partials/`), 5 `flows/*/*.liquid`, 21 `schemas/*.xsd`.

## Part 1 — Comment load

"Comment-only" = line starts with optional whitespace then `#`. "Trailing" = content line containing ` #`. Provenance = comment lines (either kind) citing `ORC-\d+` or `§`.

| Directory | Files | Total | Comment-only | Trailing | Blank | Pure content | Pure % | Cites ORC | Cites § | Either |
|---|---|---|---|---|---|---|---|---|---|---|
| default/tiers | 51 | 1619 | 676 | 0 | 0 | 943 | 58% | 36 | 127 | 156 |
| default/edges | 10 | 673 | 220 | 47 | 37 | 369 | 55% | 26 | 25 | 48 |
| default/flows | 5 | 71 | 26 | 0 | 0 | 45 | 63% | 0 | 0 | 0 |
| default/predicates.yaml | 1 | 28 | 23 | 0 | 0 | 5 | 18% | 0 | 3 | 3 |
| default/bundle.yaml | 1 | 15 | 8 | 0 | 0 | 7 | 47% | 1 | 1 | 2 |
| default-flow/types | 4 | 162 | 101 | 29 | 0 | 32 | 20% | 11 | 28 | 38 |
| default-flow/gates | 5 | 94 | 69 | 9 | 0 | 16 | 17% | 1 | 11 | 12 |
| default-flow/environments | 3 | 14 | 3 | 0 | 0 | 11 | 79% | 0 | 2 | 2 |
| default-flow/bundle.yaml | 1 | 16 | 9 | 1 | 0 | 6 | 38% | 0 | 4 | 4 |
| **default (chain)** | 68 | 2406 | 953 | 47 | 37 | 1369 | 57% | | | |
| **default-flow (workflow)** | 13 | 286 | 182 | 39 | 0 | 65 | 23% | | | |
| **All** | 83 | 2692 | 1135 | 86 | 37 | 1434 | 53% | 75 | 201 | 265 |

Notes:
- The workflow bundle is 77% comment; its 65 content lines carry 182 comment lines plus 39 more comments riding on content lines. `types/` is 5:1 comment to content.
- Tier header blocks (leading `#` lines before `tier:`) total 600 lines across 51 files; longest are `screen_collarch` (34), `policy` (29), `requirements` (28), `bug_fix_plan` (23), `frontend_sysarch` (22). Every one of the 17 review tiers carries a 7–10 line header saying the same thing ("a review is a tier, not a nested block ... context is the same set of walks ... checked at load time").
- 265 of 1221 comment lines (22%) cite a ticket or section. Distinct ticket ids: 16, dominated by ORC-111 (25 mentions), ORC-235 (10), ORC-109 (9), ORC-108 (6), ORC-155 (5), ORC-114 (5). Most-cited sections: §13 (20), §7.19 (17), §3.3 (17), §9 (16) — the last three are the review-tier header boilerplate.

## Part 2 — Chain construct frequency

### `tiers/*.yaml` (51 files)

Top-level key presence: `tier` 51, `generator` 51, `prompt` 39, `delivery` 39, `context` 39, `scope` 34, `identity` 34, `handle` 34, `fields` 33, `draft` 22, `reviews` 17, `grammar` (top-level) 17, `executor` 10, `produces` 6, `source` 1, `enforcement` 1.

| `scope:` form | Count | Members |
|---|---|---|
| `cascade_visit` | 5 | the five `*_plan` tiers |
| `child_of(X)` | 11 | comparch, feature_expansion, frontend_sysarch ×2, journeys, requirements, screen_collarch, screens, sysarch ×2, ui_collarch |
| `per(X)` | 13 | comp, feature_expansion ×3, requirements, screen_coll, screen_subcomp ×2, subcomp ×2, ui_coll, ui_subcomp ×2 |
| `singleton` | 4 | design_system, feature_expansion, frontend_sysarch, non_goals |
| `reference` | 1 | ref |
| (absent — inherited via `reviews:`) | 17 | review tiers |

| `generator:` | Count |
|---|---|
| `llm` | 39 (17 spine + 17 review + 5 plan) |
| `synthesis` | 10 |
| `supplied` | 1 (design_system) |
| `reference` | 1 (ref) |

Other scalar keys: `identity: id` in all 34 that carry it (no other value); `executor:` always `effort: max` (10 files); `enforcement: []` once (comparch); `grammar: schemas/review.xsd` on all 17 review tiers; `draft.grammar` is `schemas/<tier>.xsd` for 19 of 22, the exceptions being the three `impl_*` sharing `impl.xsd`; `draft.root_tag` is the tier name hyphenated for 17 of 22 (exceptions: three `impl_*` → `implementation`, `vocab` → `vocab-entry`, `downward_propagation_plan` → `propagation-plan`); `prompt:` is `prompts/<tier>.md.liquid` / `prompts/review/<tier>.md.liquid` for all but `impl_backend` (both use `impl`) and the 5 plan tiers (`flows/<flow>/plan.md.liquid`, one named `propose`). `delivery:` is fully determined: 22× `{phase: generation, agent_step: design}`, 17× `{phase: critique, agent_step: critique}`.

`fields:` sources (33 files, 91 entries): `draft.` 33 entries / 21 files; `mint.` 39 / 11 files; `mint.parent.` 17 / 4 files (comp, subcomp, screen_subcomp, ui_subcomp); `reference.` 2 / 1 file (ref). Note `vocab` is `generator: llm` with `draft:` yet sources every field from `mint.*`. `handle.fragments`: `[]` 28, five-kind list 3 (comp, screen_coll, ui_coll), three-kind list 3 (subcomp, screen_subcomp, ui_subcomp). `produces:` 6 files, 24 fragment rows (5+5+5+3+3+3), every row `owner: self.parent`.

**Context walks**: 165 entries in 39 files (100 in base tiers, 65 in review tiers). 36 distinct strings.

| Feature | Count |
|---|---|
| `self.*` | 109 (of which `self.parent.handle` 28, `self.reference -> ref.handle` 18, `self.plan_target -> ...` 20) |
| `all.<tier>.handle` | 41 (vocab 10, journey 8, comp 7, sysarch 6, feature_expansion 6, screen 4) |
| `input.*` | 15 (project_doc 7, mocks 4, non_goals 2, `input.*` 2) |
| entries with `->` | 81 |
| `~` reversal | 4 (`self.parent.policy_application~` ×2, `self.parent.fulfills.policy_application~` ×2 — comparch and its review) |
| multi-hop (≥2 edge segments before `->`) | 2 (the `fulfills.policy_application~` pair) |
| `.fragments[...]` | 30 (all `pubapi` or `failure_surface`) |

### `edges/*.yaml` (10 files)

`type:` — `dependency` 4 (calls, dependency, renders, uses_shapes), `reference` 3 (fulfills, navigation, reference), `fanout` 1, `policy_application` 1, `synthesis` 1 (plan_target).

`instances:` used by 6 of 10 files, 58 instances (plan_target 21, decomposition 13, reference 13, dependency 7, fulfills 2, policy_application 2); 4 single-declaration edges. 62 declarations total. `source_ref`/`target_ref`: 6 instances, all in dependency.yaml (the same-tier `dep[]` rows), always `"@from"`/`"@to"`. `graph_constraint: [acyclic, no_self_loop]` 1 (dependency). `consistency: eventual` 4 (exactly the four `type: dependency` files). `navigation: true` 1. **`constraint`: 0. `cardinality.when`: 0. `scope_filter`: 0** (predicates.yaml's own header says so).

Cardinality forms over 62 declarations: source `{min: 0}` 27, `{min: 1, max: 1}` 21, `{min: 1}` 11, `{min: 0, max: 1}` 3; target `{min: 0}` 47, `{min: 1, max: 1}` 15. plan_target's 21 instances are the 5 plan tiers × their target set (4/4/3/4/6) with identical cardinality and `declared_in: <plan>.cascade_target` on every row — 126 lines encoding a 5-row table.

### `flows/*/flow.yaml` (5) and `predicates.yaml`

Every flow carries exactly `flow`, `delta.tiers`, `delta.edges`, `walk`, `ticket.entry`, `ticket.labels`, `completion`. `walk`: `downward_cascade` 4, `up_then_down` 1. `ticket.labels: []` in all 5. `delta.edges` is `[edges/plan_target.yaml]` in all 5. Predicates: 5, all the single form `all(<plan_tier> -> resolved)`, one per flow. `bundle.yaml` declares `fragments: [techspec, pubapi, privapi, policies, failure_surface]`.

## Part 3 — Review-tier duplication

All 17 `X_review.yaml` `context:` blocks are byte-identical to `X.yaml`'s: **17/17 identical, 65 duplicated context lines** (comparch 8, screen_collarch 9, ui_collarch 7, frontend_sysarch/impl_*/screen_subcomparch/ui_subcomparch 4 each, requirements/screens/subcomparch 3, feature_expansion/non_goals/sysarch 2, journeys/vocab 1). Each header says the block "is the same set of walks ... checked at load time (§13) rather than trusted".

Keys review tiers carry beyond `tier`, `reviews`, `generator`, `prompt`, `grammar`, `context`, `delivery`: **none**. All 17 have exactly those seven keys, with `generator: llm`, `grammar: schemas/review.xsd`, `delivery: {critique, critique}` constant across all 17 and `prompt` derivable from `reviews` in 16 of 17.

## Part 4 — Tier shape clusters

| Cluster | n | Members | Key set | Identical across members (boilerplate) | Varies |
|---|---|---|---|---|---|
| Review | 17 | every `*_review` | tier reviews generator prompt grammar context delivery | generator=llm, grammar=review.xsd, delivery={critique,critique}; prompt derivable from `reviews` (16/17); context = copy of base | tier, reviews, context (copied) |
| LLM spine | 17 | feature_expansion, non_goals, journeys, screens, requirements, sysarch, frontend_sysarch, comparch, subcomparch, impl_backend, ui_collarch, ui_subcomparch, impl_ui, screen_collarch, screen_subcomparch, impl_screen, vocab | tier scope identity fields handle draft generator [executor] prompt context [produces] delivery [enforcement] | identity=id, handle.fragments=[], generator=llm, delivery={generation,design}; root_tag/grammar/prompt derivable from tier name in 12/17 | scope, fields (1–3 `draft.` entries), handle.fields, context (1–9 entries), executor present on 10, produces on 6 (the six `*arch` tiers with a join-target parent), enforcement on 1 |
| Join-target / projection | 10 | comp, subcomp, resp, policy, journey, screen, screen_coll, screen_subcomp, ui_coll, ui_subcomp | tier scope identity fields handle generator | identity=id, generator=synthesis, scope always `child_of(<minting tier>)`, fields always `mint.*`, handle.fields = `[id] + fields keys` in all 10 | field lists (2–9), fragments list (three shapes), 4 carry `mint.parent.*` copies |
| Planning | 5 | bug_fix_plan, downward_propagation_plan, feature_request_plan, refactor_plan, upward_propagation_plan | tier scope identity fields handle draft generator prompt context delivery | scope=cascade_visit, identity=id, `argument: draft.argument`, `resolved: draft.resolved`, handle.fragments=[], generator=llm, delivery={generation,design}, context begins `input.project_doc`, `all.comp.handle` in all 5, `all.sysarch.handle` in 4 | root_tag, grammar, prompt path, plan_target targets (3–6), one extra summary field |
| Externally sourced | 2 | ref, design_system | tier scope identity handle generator + (fields \| source) | identity=id, handle.fragments=[] | ref: scope=reference, generator=reference, fields `reference.*`; design_system: scope=singleton, generator=supplied, `source: input.design_system`, no fields |

Sub-shapes inside the spine: three `impl_*` are one template (same grammar, root_tag, 4-entry context differing only in parent tier name); the `*arch` pairs (comparch/ui_collarch/screen_collarch; subcomparch/ui_subcomparch/screen_subcomparch) differ only in tier names and one or two family-specific edges.

## Part 5 — Workflow construct frequency

`skeleton:`: `ticket` 2 (feature, seed), `container` 1 (milestone), absent 1 (project). `entry: project`.

| statuses entry kind | Count | Values |
|---|---|---|
| `status:` | 31 | pending 4, deploy 3, terminal 3, generation 2, checks 2, reconcile 2, merge 2, critique 1, setup/prep/main/retro/cleanup 1 each, initialization/scaffolding/build-out/iteration/maintenance/deprecating/sunsetting 1 each |
| `flow:` (sub-key on status) | 10 | feature 7, milestone 2, seed 1 |
| `review:` | 5 | ux-review, engineering-review, kickoff-review, milestone-signoff, proposals-read (each once) |
| `environment:` | 2 | staging (feature), prod (milestone) |
| `depth:` (sub-key) | 1 | `[2, 0]` on feature's critique |
| `blocks:` | 1 | `[retro]` on milestone's main |
| `critique:`/`reconcile:`/`merge:`/`checks:` as entry kinds | 0 | these appear only as `status:` values |

Sub-arrays (`- - `): 3 (feature 1, milestone 2). Every grouped sub-array opens with `status: pending` except milestone's retro group, whose pending is second.

Gates (5 files, 5 keys each, no others): `review` (name), `role` {author 3, design 1, engineering 1}, `depth` {0 ×5}, `throwback` {ux-review, setup, main, retro, pending}, `escalation` {author ×5}. Environments (3): `environment`, `depth: 0` ×3, `lifetime: persistent` ×3, `promote_from` ×2 (staging→dev, prod→staging).

Keys set to what their comment says is the default anyway: **1 explicit** — ux-review's `throwback: pending` ("Restates the derived default rather than overriding it"). Additionally ux-review's `depth: 0` comment says "this is the rule for a gate, not merely its default", so all **5** gate `depth: 0` lines restate a value that cannot differ; `escalation: author` ×5, `lifetime: persistent` ×3 and env `depth: 0` ×3 are uniform with no comment saying whether a default exists. Comments explicitly mark two throwbacks as *real* overrides (kickoff-review, engineering-review).

## Part 6 — What the YAML suggests is boilerplate vs load-bearing

The load-bearing content is small and enumerable: 36 distinct context-walk strings, 62 edge declarations (really ~40 once plan_target's 21-row product and the 9 identical `-> ref` rows are seen as tables), 33 `draft.`/39 `mint.` field sources, 5 predicates, and about 65 lines of workflow statuses. Everything else is either constant across a cluster or derivable from a name: every review tier is seven keys of which four are constants and one (context) is a verbatim copy checked for equality at load, so the 17 files carry roughly 20 lines of information between them; `identity: id`, `handle.fragments: []`, `delivery:` (a pure function of `generator`+`reviews`), `grammar: schemas/review.xsd`, `executor: {effort: max}`, prompt/grammar/root_tag paths matching the tier name, and `cardinality`/`consistency` lines that take one of two shapes are all restatement. The comments are the largest single component (45% of all lines, 77% of the workflow bundle) and roughly a fifth of them are provenance (ticket ids, section cites) rather than rationale; the review-tier header alone is repeated 17 times. The signal about what matters is in what *varies*: `scope`, the `~`/multi-hop walks (4 entries, all on comparch), the 6 `produces:` blocks, the 3-vs-5 fragment split, `graph_constraint`, `navigation: true`, `blocks:`, `depth: [2, 0]`, and the four throwbacks that are not the derived default — while `scope_filter`, `constraint`, and `cardinality.when` are unused anywhere.
