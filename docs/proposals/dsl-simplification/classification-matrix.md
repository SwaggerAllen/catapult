# Classification matrix — every DSL construct, three columns, one class

README §5 step 2. One row per construct the loader accepts. Three
columns and a class:

- **Bundle** — does `bundles/default` or `bundles/default-flow` use it
  (report D)? A count where the report gives one.
- **Engine** — does a module outside `lib/catapult/dsl/` read the
  loaded value (report E)? "load-only" means the loader checks it and
  nothing reads it afterward.
- **Intent** — does the record say a consumer is coming? Cited to the
  section, "Initial vs target" entry, or ticket that says so. "none
  found" means the record was searched (v5, build-plan, every
  `systems/*.md` Initial-vs-target section, the ORC threads) and
  nothing names a consumer. That is a fact about the record, not a
  verdict; the author supplies the missing column in §3.

Classes: **live** (engine reads it), **reserved** (engine does not
read it yet; the record or the author intends it), **questioned**
(engine does not read it; no intent found). A live row can still
carry a seam note; a reserved row carries the intended consumer and
the plan phase; a questioned row waits on one sentence from the
author.

"Seam" cross-references are to `seam-pass.md` entries. ORC-246 and
ORC-247 changes are included where they alter a row (`in-flight-
tickets.md`).

## 1. Chain axis

### 1.1 Bundle manifest and `catapult.yaml`

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `catapult.yaml` `chain:` / `workflow:` | yes | loader input | core_dsl#7 | live | |
| `bundle.yaml` `name` | yes | chain dir lookup | — | live | |
| `bundle.yaml` `version` | yes | stored, never compared | v5 §6 cutover, engine#69's active-bundle-version projection | reserved | consumer: cutover (no phase named) |
| `bundle.yaml` `kind` | yes | axis dispatch | core_dsl#7 | live | |
| `tiers:` / `edges:` / `flows:` globs | yes | load | — | live (flows glob rides flows' class) | seam 1: one file makes the globs moot |
| `fragments:` closed vocabulary | yes (5) | load-only (vocab check) | — | live as a load check | seam 9: derive from `produces` |
| `extends:` (rejected) | no | rejected | core_dsl#29 | live (as a refusal) | keep the refusal, one line |

### 1.2 Tier declaration

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `tier` name | 51 | everywhere | — | live | |
| `scope: singleton` | 4 | ReadyScopes candidates, `drained?` | — | live | |
| `scope: per(X)` | 13 | ReadyScopes | — | live | |
| `scope: child_of(X)` | 11 | ReadyScopes, EdgeLocator | ORC-247: X single-sourced (`core_dsl#45` on that branch) | live | seam 2 |
| `scope: reference` | 1 (`ref`) | settled unconditionally, never drained | v5 §4.5 refs as the escape hatch | live, redundant with `generator: reference` | seam 2: fold into the generator |
| `scope: cascade_visit` | 5 (plan tiers) | candidates always `[]` | flows, v5 §7 up/down walks; core_dsl#8 | reserved | consumer: flow engine (engine#69 target "flow instances") |
| `scope_filter:` | 0 | evaluated by ReadyScopes → PredicateEvaluator | none found | questioned | the only evaluated predicate slot, and nothing uses it |
| `identity: id \| alias \| name \| slug` | `id` 34 (→ `alias` 4, `slug` 1 under ORC-246) | Extraction `identity_field/2` | ORC-246 | live | seam 1: never default it |
| `fields: draft.<path>` | 21 files | Extraction at commit | — | live | |
| `fields: mint.<name>` | 11 files | Extraction `mints/7` | ORC-236 | live | |
| `fields: mint.parent.<name>` | 4 files | Extraction `mints/7` | ORC-236, core_dsl#40 | live | |
| `fields: reference.<name>` | 1 (`ref`) | **no write path creates reference nodes** | v5 §4.5 | reserved | consumer: whatever mints `ref` nodes; no ticket names it |
| `argument` reserved field name | 5 (plan tiers) | not enforced | flows, one UI screen (A part 4) | reserved with flows | |
| `handle.fields` | 34 | ContextAssembly `render_node/3` | — | live | never checked ⊆ `fields`; seam 8: default to all |
| `handle.fragments` | 34 (28 empty) | ContextAssembly | — | live | seam 9: derive |
| `draft.root_tag` | 22 | CommitPath `validate_draft`, `generation_tier?` | — | live | derivable from tier name in 17/22 |
| `draft.grammar` | 22 | CommitPath, DeclaredInSchema | — | live | derivable in 19/22 |
| `generator: llm` | 39 | Sweeper dispatch | — | live | |
| `generator: synthesis` | 10 | join-target gating (`draft` nil) | — | live | |
| `generator: supplied` + `source: input.<role>` | 1 | Sweeper `mint_supplied` | core_dsl#30, #41 | live | seam 3: merge `reference` into it |
| `generator: reference` | 1 | ReadyScopes settles it; no executor | v5 §4.5 | live-ish | seam 3 |
| `generator: external` + `package:` / `options:` | 0 | no executor | v5 §3.2 (registry-resolved), registry#7 target Phase 7, v5 §9 | reserved | consumer: registry service, Phase 7 |
| `generator: template` + `template:` | 0 | no executor | v5 §9 names it as a new generator type; nothing else | reserved, weak | consumer unnamed; **author** |
| `generator: git_commit` + `code_repo_url:` / `path_from_handle:` | 0 | no executor | none found in v5 or systems | questioned | v4 carry-over? **author** |
| `generator: webhook` | 0 | no executor | none found | questioned | **author** |
| `prompt:` | 39 | ContextAssembly (Solid) | — | live | existence checked at dispatch, not load |
| `executor: {effort:}` | 10 (all `max`) | **no consumer** | v5 §7 "executor profile (model, effort, harness requirements)"; generation#50 target "executor-profile routing" | reserved | consumer: generation, target; default `max` meanwhile |
| `context:` walks | 39 files, 165 entries | ReadyScopes, Staleness, ContextAssembly | — | live | see 1.5 |
| `produces: {owner: self.parent, kind, authored}` | 6 files, 24 rows | Extraction `produces/3`, Reducer | — | live | seam 9: map form, owner implied |
| `produces: {owner: self}` | 0 | validated, **dropped at runtime** (`:self_not_yet_known`) | none found | questioned | a load-legal form the engine discards; **author**: intended or a defect |
| `delivery: {phase, agent_step}` | 39 (fully determined) | **no consumer** | v5 §7 delivery annotations; delivery#123 target Phase 7 "delivery-DSL extension registered with core_dsl"; ORC-179 (kind per tier deferred) | reserved | the cross-axis binding point (seam 13, 18); default from generator meanwhile |
| `enforcement: [...]` | 1 (`[]`) | **cannot load** (empty registry) | v5 §6 enforcement profiles (`codegen: restricted`, `purity: replay_floor`); v5 §2.9 | reserved | consumer: delivery Phase 7 (child reconcile gate) and the purity audit |
| `reviews: <tier>` | 17 | ReadyScopes `ready_review`, ContextAssembly, CommitPath | core_dsl#9 | live | seam 10: derive |
| `grammar:` (review tier root) | 17 (all `review.xsd`) | CommitPath | — | live | constant; a platform default |
| body attrs `implementation: stubbed\|real`, `swap:` | XSD content | not DSL keys | v5 §2.16 | out of scope | grammar content, not tier grammar |

### 1.3 Edge declaration

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `edge` name | 10 | grouping only | — | live | seam 4: instance is the unit |
| `type: fanout` | 1 (13 instances) | Extraction mints, ReadyScopes drivers | — | live | |
| `type: reference` | 3 | Extraction via EdgeLocator | — | live | |
| `type: dependency` | 4 | Extraction; store column | — | live | |
| `type: policy_application` | 1 (2 → 5 under ORC-247) | Extraction markers; ORC-247 adds locator instances | v5 §4.5, ORC-247 | live | |
| `type: synthesis` | 1 (`plan_target`, 21 rows) | **no consumer** | flows | reserved with flows | seam 12: derivable from a flow's `targets:` |
| inline `source`/`target` | 4 files | Extraction | — | live | seam 4: drop the inline form |
| `declared_in` | 62 | Extraction; XSD-walked at load | core_dsl#33–#36 | live | |
| `instances[]` | 6 files, 58 rows | Extraction, ReadyScopes | core_dsl#8 | live | |
| `source_ref` / `target_ref` (`self`, `self.parent`, `fanout(e)`, `@attr`) | 6 (`@from`/`@to`) + `@ref` under ORC-247 | Extraction via EdgeLocator | ORC-236, core_dsl#37 | live | seam 5: convention could replace the keys |
| `cardinality.{source,target}.{min,max}` | 62 rows | GraphConstraints evaluates, **no production caller**; non-blocking by design | v5 §7 "standard cardinality-many gate" (validation readiness), §13 `min` once `drained?` | reserved, weak | seam 6: every shipped value is an XSD fact or a type tautology; **author** |
| `cardinality.when` | 0 | not evaluated | none found | questioned | **author** |
| `cardinality.per_source` | 0 | stored | none found | questioned | **author** |
| `graph_constraint: [acyclic, no_self_loop, tree]` | 1 | GraphConstraints, no caller; load checks type-level acyclicity | readiness needs dependency acyclic | reserved | seam 6: make it a rule of the type |
| `consistency: eventual \| transactional` | 4 (all `eventual`) | stored, never read | v5 §2.6 (transactional edges handle the transaction version) | reserved | consumer: comparch grammar / codegen, Phase unnamed |
| `navigation: true` | 1 | load-only (walk ban) | v5 §4.3 nav edges | live (load-only) | |
| `constraint:` predicate | 0 | not evaluated | none found | questioned | **author** |

### 1.4 Flows (`flows/<flow>/flow.yaml`)

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `flow` name | 5 | **no consumer** (`Dsl.Flow` referenced by nothing outside `dsl/`) | v5 §7 flows; engine#69 target "flow instances"; MVP per author | reserved | seam 12 |
| `delta.tiers` / `delta.edges` | 5 | stored, never resolved | same | reserved | never checked against `tiers`/`edges` at load either |
| `walk: downward_cascade \| up_then_down` | 4 / 1 | none | v5 §7 (`up_then_down` named) | reserved | |
| `ticket.entry` | 5 | none | v5 §9 "flow ticket faces" | reserved | |
| `ticket.labels` | 5 (all `[]`) | none | same | reserved | |
| `completion: <predicate>` | 5 (one form) | parsed, never evaluated | flows | reserved | the one form used is an engine invariant (seam 11) |
| planning tiers + `plan_target` + `predicates.yaml` (bundle shape) | 5 + 21 + 5 | none | flows | reserved | shape, not grammar: derivable (seam 12) |

### 1.5 Context walks and prompt variables

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `self`, `self.parent` | 109 | ContextResolver | — | live | |
| `.<edge>` hop, multi-hop | 81 with `->`, 2 multi-hop | ContextResolver | core_dsl#8 | live | |
| `~` reversal | 4 | ContextResolver `landings/2` | core_dsl#8 | live | |
| `-> <tier>.handle` | most | ContextAssembly `render_node/3` | — | live | seam 7: `handle` as default projection |
| `-> <tier>.handle.fragments[k]` | 30 | ContextAssembly | — | live | |
| `.synthesis` projection | 0 | load error | core_dsl#42 retired | retired | keep the refusal one line, or drop |
| `all.<tier>.<proj>` | 41 | ReadyScopes `drained?` gate, ContextResolver | core_dsl#8, ORC-235; ORC-247 `#46` closure refusal | live | |
| `input.<role>` (4 roles) | 13 | readiness `{:ok, []}`; ContextAssembly reads Delivery | v5 input roles | live | roles are a platform list admitted by census (seam 7) |
| `input.*` (`raft`) | 2 | same | v5 §5 raft | live | |
| `ticket.findings` | 0 | `{:error, :unsupported}`; cannot load (no registered source) | v5 §7 flows ("planning tiers may read `ticket.findings`"), §9 | reserved | consumer: flow engine + delivery findings |
| per-entry variable name (`as:` / map form) | 0 (ORC-247 adds 18 sites) | ContextAssembly `build_variables/5` (ORC-247) | ORC-247 `core_dsl#47` | live under ORC-247 | seam 7: `context:` as name → walk map |
| §9 merge-by-target-tier rule | implicit | ContextAssembly | ORC-247 rewrites to merge-by-name | live, being replaced | dissolves under the map form |
| prompt variables `self`, `feedback`, `prior_review`, `draft`, `raft`, `<role>` | all prompts | ContextAssembly, engine projections (ORC-34) | — | live | content contract, not DSL keys |
| `{% render "partials/..." %}` | 13 sites | Solid | v5 §6 | live | content |

### 1.6 Predicates

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `predicates.yaml` named predicates | 5 | `Chain.resolve_predicate/2` from ReadyScopes | core_dsl#12 | live as plumbing | |
| slot `scope_filter` | 0 | evaluated | none found | questioned | |
| slot `cardinality.when` | 0 | not evaluated | none found | questioned | |
| slot edge `constraint` | 0 | not evaluated | none found | questioned | |
| slot flow `completion` | 5 | not evaluated | flows | reserved | |
| families: comparison, boolean, `has_edge`/`count`, `exists`, `all`/`any`, `reaches` | `all(... -> resolved)` only | PredicateEvaluator implements all; only reachable via `scope_filter` | v5 §3.4 closed predicate language, core_dsl#3 | reserved with the slots | the language survives only as long as one slot does |

### 1.7 Grammars and extensions

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| XSD draft grammars | 21 | `Grammar` at commit | core_dsl#6 | live | seam 19 |
| review grammar (`review.xsd`: intro, score, finding) | 1 | CommitPath | v5 §7.19 | live | platform-wide; a default |
| v5 grammar productions (`<permissions>`, `<enforcement>`, `<implementation>`, process inventory, `<tests>`) | per XSD | grammar content | v5 §6 | out of scope | content |
| extension registry (`Registry`, `Extension` behaviour) | 0 registrations | seam with no implementer | core_dsl#2, #43 target "full extension registry"; v5 §9 | reserved | seam 14: narrow the doctrine |
| dialects `design` / `runtime` | `design` only | `Dialect` gates workflow loading | core_dsl#43 target; llm#6 (runtime dialect Phase 8) | reserved (`runtime`) / live (`design`) | |
| extension kinds: annotation namespaces, declaration kinds, generator types, context sources, enforcement profiles | 0 | registry | v5 §9 | reserved | |
| loader input `role_holders:` | not bundle | opt-in check, never passed | v5 §7 bindings | reserved | consumer: delivery bindings |
| loader input `mirror_mapping:` | not bundle | opt-in check, never passed | v5 §7.12 Linear mirror; delivery target "outbound mirror" | reserved | |

## 2. Workflow axis

### 2.1 Manifest and types

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `gates:` / `environments:` / `types:` globs | yes | load | delivery#123 | live | |
| `entry:` | yes (`project`) | validated as root; **nothing mints the first container from it** | core_dsl#16; delivery Phase 4 container machinery | reserved | consumer: provisioning of the project root |
| `type` name | 4 | BoardLive, ContainerLifecycle | — | live | |
| `skeleton: ticket \| container \| absent` | 2 / 1 / 1 | ContainerLifecycle `nests?`, BoardLive | core_dsl#15, #20 | live | |
| `statuses:` ordered array | 4 | both lifecycle Sequences, ContainerQueues, Composition | core_dsl#14 | live | |
| entry `status:` | 31 | Sequences | — | live | |
| entry `review:` | 5 | Sequences, DocumentReviewLive | — | live | |
| entry `environment:` | 2 | **dropped by both Sequences** (`to_position`/`to_step` → nil) | v5 §7.19 environments; delivery Phase 7 | reserved, with a live defect | an author writes it and it vanishes; mark in the contract |
| sub-array grouping | 3 | `Type.namespaced_positions`, `group_at`, `anchor_index`; `approve_leaves_group?` | core_dsl#17 | live | seam 16: prototype flat |
| `name:` on a status entry | 0 | `Type` namespacing reads it | core_dsl#26 | live, unused | |
| `<anchor>.<name>` references | 0 | Sequences resolve | core_dsl#26, ORC-171 | live, unused | dissolves with sub-arrays if seam 16 goes flat |
| `flow:` on a population anchor | 10 | ContainerLifecycle `mint_child`, `nests?` | core_dsl#14 | live | |
| `blocks:` | 1 | ContainerQueues `held_or_resolved` | core_dsl#27 | live | |
| `depth:` on `critique` | 1 (`[2, 0]`) | **no consumer** | v5 §7.19 depth fan-out; generation#50 target "review passes" | reserved | consumer: review dispatch at depth |

### 2.2 Fixed status kinds

| Kind | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `pending`, `generation`, `critique`, `checks`, `reconcile`, `merge`, `deploy`, `terminal` | authored | `SystemStatus` shape predicates; Sequences | v5 §7.19 | live | the authorable eight |
| `setup`, `prep`, `main`, `retro`, `cleanup` | authored (milestone) | ContainerLifecycle | core_dsl#20 | live | container five |
| `design`, `architecture`, `implementation` | 0 | `generation_shaped?` accepts them | core_dsl#23, #27; ORC-179 (which kind each chain tier picks is deferred) | reserved | the kinds `delivery.phase` will bind to |
| `backlog`, `blocked`, `stubbed`, `validating` | 0 (never authorable) | plane transitions | v5 §7 | live, plane-owned | belong in the engine doc, not the bundle contract |
| free-form kinds on a skeleton-less type (`initialization`, `scaffolding`, ...) | 7 (`project`) | Sequences as plain positions | core_dsl#15 | live | |

### 2.3 Gates and environments

| Construct | Bundle | Engine | Intent | Class | Note |
|---|---|---|---|---|---|
| `review` (gate name) | 5 | Sequences, DocumentReviewLive | — | live | |
| `role` | 5 | `Positions.role/2` display only; `ApproveGate` does not check it | v5 §7 role bindings, `role_holders:` | live (display) / reserved (enforcement) | |
| gate `depth` | 5 (all `0`) | **no consumer** | doc: "0 is the rule for a gate" | questioned | if 0 is the rule, the key has no value space; **author** |
| `throwback` | 5 | `Workflow.throwback_default/3`, DocumentReviewLive | core_dsl#19 | live | |
| `escalation` | 5 (all `author`) | **no consumer** | v5 §7 escalation rules (bounce-twice → author) | reserved | consumer: delivery Phase 7; one value today |
| `environment` name | 3 | existence check only | v5 §7.19 | reserved | |
| `promote_from` | 2 | **no consumer** | v5 §7.19 promotion order | reserved | |
| `lifetime: persistent \| per_ticket` | 3 / 0 | **no consumer** | v5 §7.19 | reserved | `per_ticket` never used; **author**: is it intended? |
| environment `depth` | 3 (all `0`) | **no consumer** | v5 §7.19 | reserved | same question as gate depth |

## 3. Tally and the author's column

Rows by class (constructs, not keys; a closed set's members counted
with their construct):

| Class | Chain | Workflow | Total |
|---|---|---|---|
| live | 53 | 18 | 71 |
| reserved | 28 | 9 | 37 |
| questioned | 10 | 1 | 11 |
| retired / out of scope | 3 | 0 | 3 |
| rows | 94 | 28 | 122 |

The reserved rows group into five intended consumers, which is what
the contract doc's markers should name:

1. **Flow engine** (engine#69 target; MVP): `cascade_visit`,
   `argument`, `synthesis` edge type, every flow key, `completion`,
   `ticket.findings`, the planning-tier and `plan_target` shape.
2. **Delivery Phase 7** (delivery#123 target): `delivery:`,
   `enforcement:`, `entry:` (provisioning), `environment:` entries
   and every environment key, gate `escalation`, `role` enforcement,
   `role_holders:`, `mirror_mapping:`, the `design`/`architecture`/
   `implementation` kinds (with ORC-179).
3. **Generation target** (generation#50): `executor:`, `depth:` on
   `critique` (review passes at depth).
4. **Registry and runtime dialect** (registry#7, llm#6, core_dsl#43):
   `generator: external` and its options, the extension registry and
   kinds, the `runtime` dialect.
5. **Unassigned but recorded**: `version` (cutover), `reference.*`
   fields and `generator: reference` (v5 §4.5, no ticket),
   `consistency` (v5 §2.6, no phase), `cardinality` and
   `graph_constraint` (readiness gating, weak), `generator: template`
   (named once in v5 §9, no consumer).

The questioned rows, each needing one sentence (intended and for
what, or not):

| Construct | What the tree says |
|---|---|
| `scope_filter` | the only evaluated predicate slot; no bundle uses it; no record intent |
| `cardinality.when` | never evaluated; no intent |
| `cardinality.per_source` | stored; no intent |
| edge `constraint` | never evaluated; no intent |
| `generator: git_commit` (+ `code_repo_url`, `path_from_handle`) | no executor; not in v5; likely v4 carry-over |
| `generator: webhook` | no executor; not in v5 |
| `produces: {owner: self}` | loads, then discarded at runtime; either intended or a defect |
| gate `depth` | doc says 0 is the rule; five files restate it |
| `lifetime: per_ticket` | value never used; the key is reserved with environments |
| `.synthesis` projection | already retired (core_dsl#42); keep the refusal or drop it |
| `name:` on a status entry / `<anchor>.<name>` | live in code, zero uses; stands or falls with sub-arrays (seam 16) |

Three rows the tally counts as reserved but the seam pass argues
should move rather than wait: `cardinality` (to the XSD, seam 6),
`graph_constraint` (to a rule of the `dependency` type), and the
planning-tier shape (derived from a flow declaration, seam 12).
Moving them keeps the intent and removes the grammar; the author's
call is in `seam-pass.md`, not here.
