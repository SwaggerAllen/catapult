# The seam pass — first draft

For each flexibility the DSL offers, five questions: what it lets a
bundle author vary; what it costs (loader, engine, doc, bundle); what
constraint it places on authors; whether that constraint is the
engine's requirement or the default bundle's habit; and whether this
is the right level to impose it (grammar, XSD, prompt, default,
engine code, binding). Then a status (live / reserved / questioned)
and a recommendation. Evidence citations are to `evidence/report-*`.

This is a starting table for the seam step in `README.md` §5, not
its conclusion. Several entries end in a question only the prototype
or the author can settle.

## Summary

| # | Flexibility | Status | Whose constraint | Recommendation |
|---|---|---|---|---|
| 1 | Arbitrary tier set, one file per tier | live | engine (shape), default (file layout, constant keys) | one file, tiers as a map, defaults for constant keys |
| 2 | Scope kinds | live (+1 reserved) | engine, except `reference` scope | fold `reference` scope into the generator; `child_of(X)` single-sourced (ORC-247) |
| 3 | Generator types | 3 live, 5 reserved | engine | merge `reference` into `supplied`; mark the rest |
| 4 | Typed edges bound to body paths | live (+`synthesis` reserved) | engine | instance is the unit; drop inline/instances duality |
| 5 | Endpoint locators | live | engine (need), default (form) | convention over declaration for `@from`/`@to` |
| 6 | Edge invariants: cardinality, graph_constraint, consistency, navigation, constraint | none read at runtime | default / XSD | cardinality to the XSD; acyclicity a per-type rule; question the rest |
| 7 | Context walks | live | engine | keep intact; it is the DSL's core. Variable naming is grammar (ORC-247): try `context:` as a name → walk map |
| 8 | `handle:` narrowing | live | default (opinion) | default to all fields; declare only to narrow |
| 9 | Fragments / `produces:` / vocabulary | live | engine (mechanism), default (owner, vocab) | map form; owner implied; vocab derived |
| 10 | Review tiers | live | default (encoding) | derive from the tier |
| 11 | Predicate language, four slots | 1 slot live (unused), 1 reserved, 2 questioned | none demonstrated | keep for `completion`; the used form is an engine invariant |
| 12 | Flows | reserved, MVP | engine (need), default (shape) | declare the varying part; derive the planning tier |
| 13 | `delivery:` / `executor:` / `enforcement:` | delivery: live binding point; executor: live default; enforcement: reserved | engine / binding | keep delivery with a default; default executor; mark enforcement |
| 14 | Extension registry and dialects | reserved | platform | narrow the doctrine to executors |
| 15 | Workflow types, ordered statuses, skeletons, fixed kinds | live | mixed | name the runtime module behind each check; split authorable from plane kinds |
| 16 | Sub-arrays, namespaces, derived throwback and gate scope | live | engine (need), default (encoding) | prototype flat + explicit; see what is lost |
| 17 | Gates and environments | gates live; environments reserved with a live defect | mixed | gate = role + throwback; mark environments; fix or mark the sequence drop |
| 18 | Two axes, no cross-reference | live | platform | keep; document the vocabulary leak as the trade |
| 19 | XSD vs DSL for structural facts | live | — | paths stay in the DSL; cardinality moves to the XSD; evaluate `xs:appinfo` |
| 20 | Where human gates live; the fixed status-name set | live grammar, reserved enforcement | platform (name set), engine (Phase 7 consumer) | keep the direction (tiers name statuses); free the names by the depth rule; retire the three reserved kinds |

## Entries

### 1. Arbitrary tier set, one file per tier

- **Enables:** any decomposition depth and any number of families;
  "adding a tier is a bundle edit" (v5 §5.1).
- **Costs:** 51 files (D); per-file constants (`identity: id` ×34,
  `executor: {effort: max}` ×10, `handle.fragments: []` ×28,
  `delivery:` fully determined by generator and `reviews`); the tier
  name repeated in `prompt`, `draft.grammar` and `draft.root_tag`
  paths in most files (D part 2); 600 lines of header comment.
- **Constrains authors:** closed key set; `scope` and `generator`
  required; one file per tier.
- **Whose:** the key *set* is the engine's (E part 4). The file
  layout was never decided (F part 2) and the constant keys are the
  default's habits.
- **Right level:** file granularity is a layout choice; constants
  are defaults.
- **Status:** live.
- **Recommendation:** one chain file with tiers as a map; `executor`
  and `delivery` default; `prompt`/`grammar`/`root_tag` derived from
  the tier name unless overridden. `identity` is **not** defaulted:
  ORC-246 found the blanket `identity: id` hiding five tiers that
  minted with no identity at all (`in-flight-tickets.md`), so it is
  chosen per tier from the mint element's key, or declared on the
  element itself (entry 19). This is the single-file prototype
  (README §4.1).

### 2. Scope kinds

- **Enables:** how many instances a tier has and who parents them,
  which is what readiness enumerates (`singleton`, `per(X)`,
  `child_of(X)`), plus `reference` and `cascade_visit`.
- **Costs:** ReadyScopes candidate logic per kind (E); five load
  rules for `reference` alone (C #64–#68); `cascade_visit` yields no
  candidates today.
- **Constrains authors:** closed set; `per(X)`/`child_of(X)` name a
  tier; `scope: reference` must pair with `generator: reference` and
  may not `produces:`, be walked with `all.`, or carry a non-zero
  `min`.
- **Whose:** the first three are the engine's instance model.
  `reference` as a *scope* exists for one tier and states the same
  fact as `generator: reference`; the pairing rule exists because
  the fact is written twice (A part 4).
- **Right level:** yes for the three; `reference` should be one
  fact.
- **Status:** three live; `cascade_visit` reserved with flows;
  `reference` live but redundant.
- **Recommendation:** a tier whose generator is externally sourced
  (see 3) has no scope by rule; drop `scope: reference` and its five
  checks. Keep `cascade_visit` reserved, marked, with flows.
- **Added by ORC-247:** `child_of(X)` is single-sourced; a fanout
  target may be minted by only one source tier, checked at load
  (`core_dsl#45` on that branch). This is the engine's requirement
  under its readiness model: `drained?` is per tier, so a pool with
  several drivers deadlocks any driver that reads it with `all.`. The
  flat `policy` pool becomes a family of three same-shaped tiers. The
  contract states the rule with that reason; the prototype tests
  whether a family can be one declaration with several drivers, which
  is the engine-side alternative and the author's call.

### 3. Generator types

- **Enables:** node sources other than an LLM call: join targets,
  supplied documents, references, and (reserved) commits, external
  packages, templates, webhooks.
- **Costs:** closed set of eight, three executors (`llm`,
  `supplied`, `synthesis`; `reference` is settled unconditionally);
  per-generator option keys documented only in prose (A part 4).
- **Constrains authors:** closed; `llm` requires `prompt`; `supplied`
  requires `source: input.<role>`.
- **Whose:** the engine dispatches on it. `supplied` was added for
  `design_system` but the concept (a project-supplied input) is a
  platform one (v5 input roles). `reference` and `supplied` are both
  "externally sourced, never generated, never drained".
- **Right level:** yes.
- **Status:** `llm`, `synthesis`, `supplied` live; `reference` live
  and mergeable; `git_commit`, `external`, `template`, `webhook`
  reserved (`external` is the registry's, v5 §7; the others need an
  owner named).
- **Recommendation:** merge `reference` into `supplied` (one
  externally-sourced kind with a `source:`); mark the four reserved
  kinds with their intended consumer; move option keys into the
  grammar table.

### 4. Typed named edges bound to body paths

- **Enables:** any relationship between tiers, with `declared_in`
  binding it to the element in the committing tier's body that
  extraction reads to mint or link.
- **Costs:** `edge.ex` 303 + `edge_locator.ex` 221 +
  `declared_in_schema.ex` 425 lines; §4–§4.2 ~210 lines; 673 bundle
  lines.
- **Constrains authors:** `type` closed (five); `declared_in` must
  resolve against the tier's XSD (ORC-232); inline form xor
  `instances:`.
- **Whose:** the engine's. `fanout` mints, `reference`/`dependency`
  link, `policy_application` marks; `declared_in` is how extraction
  finds the rows. `synthesis` is reserved with flows.
- **Right level:** yes. But the doc treats the *edge* as the unit
  and the bundle treats the *instance* as the unit: 58 of 62
  declarations are instances (D part 2). The inline/instances
  duality and its exclusivity check exist to support the four
  single-instance files.
- **Status:** live (+`synthesis` reserved).
- **Recommendation:** the instance is the unit; an edge name groups
  instances of one type. Drop the inline form and the exclusivity
  check. ORC-247 confirms the shape: `policy_application` now mixes
  mint-time-marker instances and ordinary-locator instances under one
  name, and disambiguates two instances sharing a `declared_in` by
  `source:` alone (`core_dsl#39` amended on that branch).

### 5. Endpoint locators (`source_ref` / `target_ref`)

- **Enables:** an edge whose endpoint is neither the committing tier
  nor its parent: same-tier dependency rows, `fanout(<edge>)`, an
  explicit attribute.
- **Costs:** five-kind locator shared by loader and extraction;
  ORC-236 machinery; §4.2 ~100 lines; five load rules (C #58–#62).
- **Constrains authors:** closed forms; required whenever nothing
  structural applies.
- **Whose:** the *need* is the engine's (extraction must find the
  node). The *form* was derived by tracing the default's instances
  and closed to exactly what they need (F part 4, core_dsl #37).
  All six uses are `@from`/`@to` in one file (D).
- **Right level:** a convention would do the same work: a same-tier
  edge's `declared_in` row carries `from` and `to` attributes.
- **Status:** live.
- **Recommendation:** derive `self`/`self.parent` as today; make
  `@from`/`@to` the convention for same-tier rows; keep the explicit
  keys only if a case the convention cannot express appears. ORC-247
  adds `@ref` on `<applies ref>` citation rows: a second use of the
  attribute locator, and the same convention (a row's `ref` names the
  far end) covers it.

### 6. Edge invariants: cardinality, `graph_constraint`, `consistency`, `navigation`, `constraint`

- **Enables:** declaring structural invariants of the document graph.
- **Costs:** `GraphConstraints` evaluator with no production caller
  (E); 124 bundle lines of `cardinality:` across 62 declarations (D);
  a load rule for non-zero `min` on reference tiers.
- **Constrains authors:** min/max on every instance; `consistency`
  only on dependency edges; a navigation edge may not be walked.
- **Whose:** nothing enforces cardinality at runtime, and reading
  the 62 declarations, each is one of two things: a fact about the
  *body* ("every project has ≥1 component" is `minOccurs` on
  `<component>`) or a tautology of the edge type ("every comp has
  exactly one mint" is what fanout means). `graph_constraint:
  [acyclic, no_self_loop]` on `dependency` is engine-relevant
  (readiness) but is a property of the *type*, not a per-edge choice.
  `navigation: true` is read at load only (walk ban). `consistency`
  and `constraint` have no reader and no recorded intent.
- **Right level:** body cardinality belongs in the XSD, where it
  already is; type invariants belong on the type; the rest is
  questioned.
- **Status:** none live at runtime.
- **Recommendation:** drop `cardinality` from the grammar and rely
  on the XSD; make acyclicity a rule of the `dependency` type; keep
  `navigation` as a type or flag since it has a reader; question
  `consistency`, `constraint`, `cardinality.when`, `per_source`.

### 7. Context walks

- **Enables:** what each prompt sees, and therefore readiness (a
  node is ready when its walks land) and staleness.
- **Costs:** parser 234 lines, resolver, assembly; §7 ~115 lines;
  165 bundle entries of 36 distinct strings.
- **Constrains authors:** closed projections (`handle`,
  `handle.fragments[k]`); navigation edges banned; `all.` not on a
  reference tier; a review's walks equal the reviewed tier's.
- **Whose:** entirely the engine's. `~` reversal, multi-hop,
  `self.parent`, `all.<tier>` and both projections are all wired
  (E). This is the one place the bundle is a language rather than a
  table, and it earns it.
- **Right level:** yes.
- **Status:** live.
- **Recommendation:** keep intact. Two trims: if `handle` becomes
  the default projection (see 8), `-> comp` suffices and
  `-> comp.handle` is the exception; and the `input.<role>` set is a
  platform vocabulary admitted by census (A part 4) and should be
  declared once, not inferred from which tier reads it.
- **Amended by ORC-247.** How a walk is named in the prompt is part
  of the walk's grammar, not a derivation. §9's "one variable per
  target tier, same-tier walks merge" fused distinct reads in nine
  tiers and their reviews (eighteen sites) and nobody saw it until
  round 5 of an unrelated ticket. The branch adds an `as:` name per
  entry, a merge-by-name rule, and reserved-name and cross-tier
  collision errors (`core_dsl#47`), with the `as:` form still open.
  The prototype should try the stronger shape: `context:` as a map
  from variable name to a walk or list of walks. Naming becomes
  mandatory, the merge rule disappears (a name with two walks merges
  by construction), the collision errors reduce to key uniqueness and
  a short reserved list, and the `as:` form question dissolves. Also
  from that ticket: `all.<tier>` is refused when the reader is in the
  target's driver closure (`core_dsl#46`), a readiness deadlock class
  that is the engine's requirement; `cascade_visit` targets are a
  third never-drains case, which the flows reserved entry cites.

### 8. `handle:` narrowing

- **Enables:** a tier chooses what walkers see of it (information
  hiding, context budget).
- **Costs:** 34 blocks; `handle.fields` never checked against
  `fields` (E); in all ten join targets `handle.fields` is `[id]` plus
  every field (D part 4).
- **Constrains authors:** walkers see only the handle.
- **Whose:** the engine reads the handle for projection, but the
  *narrowing* is a design opinion, and the default never narrows a
  join target.
- **Right level:** a default with an override.
- **Status:** live.
- **Recommendation:** default handle = all fields plus what is
  produced onto the node; `handle:` only to narrow. Add the missing
  subset check if the key survives.

### 9. Fragments, `produces:`, and the bundle-level vocabulary

- **Enables:** a child tier writing named sections onto its parent
  (comparch's five fragments onto comp), readable by others as
  `fragments[kind]`.
- **Costs:** a closed vocabulary in `bundle.yaml`; 24 `produces` rows
  in six files, every one `owner: self.parent`; `handle.fragments`
  lists that restate what is produced onto the tier; an `owner: self`
  form that loads and is dropped at runtime (E).
- **Constrains authors:** kinds closed per bundle; owner in
  `{self, self.parent}`.
- **Whose:** the mechanism is the engine's. The closed vocabulary is
  a load-check convenience; the owner key is a choice with one
  working value.
- **Right level:** fine, over-declared.
- **Status:** live.
- **Recommendation:** `produces: {techspec: draft.technical-
  specification, ...}` map form; owner implied (parent); vocabulary
  derived from the union of `produces` keys; `handle.fragments`
  derived. Also the doc's fragments section (§5) is missing and its
  body is orphaned in §4.1 (A part 4); the rewrite gives it a home.

### 10. Review tiers

- **Enables:** a per-tier review prompt with the same context as the
  tier.
- **Costs:** 17 files, seven keys each, four constant, one a copy
  (D part 3); a load rule that the copy is exact.
- **Constrains authors:** must restate the walks verbatim.
- **Whose:** the encoding is the default's (core_dsl #9,
  platform_content #25); the engine needs only "this tier has a
  review, here is its prompt".
- **Right level:** a tier property.
- **Status:** live.
- **Recommendation:** `review: prompts/review/<tier>.md.liquid` on
  the tier, or a convention that the file's presence declares it.
  The equality rule holds by construction (README §4.2).

### 11. Predicate language, four slots

- **Enables:** conditional scope (`scope_filter`), conditional
  cardinality (`cardinality.when`), edge constraints (`constraint`),
  flow completion (`completion`).
- **Costs:** 317-line parser, evaluator; §8; six operator families.
- **Constrains authors:** closed, non-Turing; predicates named in one
  file.
- **Whose:** only `scope_filter` is evaluated and the default never
  uses it; `completion` is parsed and never evaluated; the other two
  are never evaluated (E). The only predicate form in the bundle,
  `all(<plan> -> resolved)`, is the same for all five flows and
  expresses what "a flow is complete" means to the engine, not a
  bundle opinion (D part 2, predicates).
- **Right level:** a predicate slot earns its place only where a
  bundle needs a *varying* condition. None does today.
- **Status:** `scope_filter` live-unused; `completion` reserved with
  flows; `cardinality.when` and `constraint` questioned.
- **Recommendation:** keep the language for `completion`, marked
  reserved; when the flow engine lands, check whether completion is
  a fixed rule or needs a predicate at all. The author decides the
  two questioned slots. If all four end up fixed rules, the parser
  goes with them.

### 12. Flows

- **Enables:** change after scaffolding: feature request, bug fix,
  refactor, upward and downward propagation. MVP.
- **Costs today:** five directories, five planning tiers of one
  template (`cascade_visit`, `argument`/`resolved` fields, the same
  context head), a 21-instance `synthesis` edge that is a 5-row
  table, five identical predicates, four core growth events
  (core_dsl #8); ~120 doc lines; no consumer yet (E).
- **Constrains authors:** adding a flow means a directory, a
  planning tier, N edge rows and a predicate.
- **Whose:** what the engine will need from a flow is a name, an
  entry point, a walk direction, a planning prompt, which tiers the
  plan may target, and a completion rule. The *shape* (a planning
  tier with `argument`/`resolved`, a synthesis edge, `cascade_visit`)
  is one encoding of that, and the default repeats it five times
  identically, which is the signature of a shape fixed by the engine
  rather than chosen by the author.
- **Right level:** the fixed shape belongs in the engine; the bundle
  declares the varying part.
- **Status:** reserved, MVP.
- **Recommendation:** keep, marked reserved, with the intent stated
  in the contract doc. Simplify the shape now to something like
  `flows: {bug_fix: {walk: downward_cascade, entry: impl_backend,
  prompt: ..., targets: [...], context: [...]}}` with the planning
  tier, `plan_target` and completion derived by the engine. The
  flow-engine ticket owns the final grammar and amends the doc. The
  author's call: is the planning-tier shape the engine's requirement
  or the default's habit? Settling it before that engine is written
  is cheaper than after.

### 13. `delivery:`, `executor:`, `enforcement:`

- **Enables:** `delivery.phase`/`agent_step` binds a chain tier to a
  workflow status kind; `executor.effort` hints the run; `enforcement`
  names codegen profiles.
- **Costs:** three keys; `delivery` constant in the default (22×
  generation/design, 17× critique/critique); `executor` always
  `max`; `enforcement` cannot be authored (empty registry).
- **Constrains authors:** `delivery` values from the fixed
  vocabulary; `enforcement` from a registry with nothing in it.
- **Whose:** `delivery.phase` is the intended cross-axis binding
  point (see 18): the chain says which kind each tier runs at, which
  is what lets a workflow gate on `design` versus `architecture`
  without naming a tier. ORC-179 records that the default has not
  yet chosen kinds per tier, which is why it is constant today. It is
  not derivable garbage; it is a reserved decision with a live key.
  `executor` is content by the store test (v5 §7.10), with one value
  in use. `enforcement` is reserved (v5 §2.9).
- **Right level:** yes for all three.
- **Status:** `delivery` live; `executor` live; `enforcement`
  reserved.
- **Recommendation:** keep `delivery` with a default derived from
  generator/reviews, so a tier states it only to pick a non-default
  kind; default `executor`; mark `enforcement` with its consumer.
  This corrects README §2.2's grouping of `delivery` with the
  derivable constants.

### 14. Extension registry and dialects

- **Enables:** platform-shipped vocabulary growth without forking
  the core (v5 §9).
- **Costs:** `dialect.ex`, `registry.ex`, `extension.ex`; zero
  registrations; two keys (`enforcement:`, `ticket.*`) that fail to
  load for want of one.
- **Constrains authors:** none today.
- **Whose:** platform doctrine, bypassed by every growth event
  (core_dsl #8, #9, #10, #30, #40).
- **Right level:** for executors, yes; for grammar, no. An extension
  can hold a generator type, a context source, an annotation
  namespace or an enforcement profile. It cannot hold a scope kind,
  a walk form or a locator, which is why those grew in the core.
- **Status:** reserved.
- **Recommendation:** keep; narrow the doctrine to what it can hold;
  state that core grammar grows by reviewed edit (README §4.5).

### 15. Workflow types, ordered statuses, skeletons, fixed kinds

- **Enables:** a custom review and deploy sequence per work-item
  type, and containers (milestones) that nest ticket types.
- **Costs:** 20 fixed kinds of which 8 are ever authored (D part 5);
  two skeletons with backbone rules; ~41 workflow load rules (C);
  `workflow.ex` 1158 lines; §15.1–§15.3 ~760 lines.
- **Constrains authors:** backbone order; `pending` before every
  generation-shaped entry; `merge` after `reconcile`; `critique`
  adjacent to its generation entry; `checks` position; `terminal`
  last.
- **Whose:** mixed, and the doc does not say which. Some rules are
  the engine's (merge consumes reconcile's output; the lifecycle
  sequences need `pending` as the dispatch-wait state). Some read as
  conventions the engine could relax (critique adjacency already
  admits `checks` in between; `pending` somewhere before `deploy`).
  The twelve never-authored kinds (`backlog`, `blocked`, `stubbed`,
  `validating`, ...) are plane states, not bundle grammar.
- **Right level:** the engine's rules, yes; the conventions belong
  in lint or in the default's own comments, not the contract.
- **Status:** live.
- **Recommendation:** for each of the ~41 rules, name the runtime
  module that misbehaves without it (report E's consumer list is the
  start); rules with no such module leave the contract. Split the
  fixed kinds into *authorable* (the eight, in the contract) and
  *plane* (in the engine doc).

### 16. Sub-arrays, namespaces, derived throwback and derived gate scope

- **Enables:** a gate grouped with the agent step it reviews, so a
  decline lands at the group's head and an approval leaves the
  group; gate scope (own vs joined) derived from position relative
  to `reconcile`.
- **Costs:** §15.10–§15.12 ~890 lines, the largest block in the
  spec; `type.ex` namespacing; the ORC-171 corruption class; nine
  load rules (C part 2).
- **Constrains authors:** one agent-balled anchor per group;
  `pending` heads the group; names unique per namespace; qualified
  references when ambiguous.
- **Whose:** the *need* (a decline lands somewhere earlier; an
  approval advances) is the engine's. Grouping-by-nesting is one
  encoding. Every one of the five shipped gates declares `throwback:`
  explicitly anyway (D part 5), and the doc itself concludes one of
  them restates the derived default.
- **Right level:** an explicit field is one line and greppable; a
  derivation is a section. README §4.4.
- **Status:** live.
- **Recommendation:** prototype a flat `statuses:` array where every
  gate declares `throwback:` and see what is lost. Known losses:
  "approve leaves group" and position-derived gate scope (§15.11).
  If those need a group, keep the sub-array and drop the
  derivations; if not, drop both.

### 17. Gates and environments

- **Enables:** named human sign-offs with a role and a decline
  target; named deployment environments with promotion order.
- **Costs:** gate keys `role`, `depth`, `throwback`, `escalation`;
  environment keys `promote_from`, `depth`, `lifetime`. Read: `role`
  (display only), `throwback`. Unread: gate `depth` ("0 is the rule",
  so why a key), `escalation` (always `author`), all environment
  keys. An `environment:` entry is dropped by both lifecycle
  sequences (E), which is a live defect rather than a future.
- **Constrains authors:** `throwback` earlier in the citing array;
  `promote_from` acyclic; `lifetime` closed.
- **Whose:** gate = role + throwback is the engine's; the rest is
  reserved (escalation policy, deploy) or the default's (`depth: 0`).
- **Right level:** yes.
- **Status:** gates live; `escalation` reserved; environments
  reserved with a defect.
- **Recommendation:** gate = `{role, throwback}`; drop gate `depth`
  if 0 is the rule; mark `escalation` and environments reserved with
  their consumers; either fix the sequence drop or mark it in the
  contract so an author is not surprised.

### 18. Two axes, no cross-reference

- **Enables:** any workflow bundle composes with any chain bundle
  (v5 §7.18).
- **Costs:** the fixed status vocabulary must be rich enough to
  carry every gate anyone wants, so `design`/`architecture`/
  `implementation` were added to the fixed table to make the
  default's gates expressible (v5 §7.18 concedes this); depth is a
  number, not a name; a gate cannot name a tier.
- **Constrains authors:** a workflow author can gate only on kinds
  and depths.
- **Whose:** platform, recorded with its reason, and the reason
  holds.
- **Right level:** yes. But the coupling comes back through the
  vocabulary: the chain's `delivery.phase` (13) is where a tier
  chooses its kind, and that is the real cross-axis seam. It should
  be named as such in the contract rather than left looking like an
  annotation.
- **Status:** live.
- **Recommendation:** keep; document the trade and the binding point
  explicitly.

### 19. XSD versus DSL for structural facts

- **Enables:** the XSD says what a body may contain; the DSL says
  which elements mint tiers (`declared_in`), which are fields
  (`draft.*`), which are fragments (`authored:`), and how many there
  are (`cardinality`).
- **Costs:** the DSL states paths into the XSD in four places and
  the loader walks the XSD to check them (425 lines, ORC-232/236);
  cardinality is stated in both (6).
- **Constrains authors:** every path must resolve; hyphen/underscore
  mismatches were a ticket.
- **Whose:** the engine needs the binding; where it is written is a
  choice never argued (F part 2: XSD "assumed from v4").
- **Right level:** two options. Keep paths in the DSL and drop the
  duplicated cardinality (least change). Or annotate the XSD
  (`xs:appinfo`: this element mints tier X; this element is field
  Y) so the schema is the single source and the DSL names only
  edges and walks. The second shrinks the DSL further and moves the
  seam toward the document grammar; it also changes what a
  bundle author edits most.
- **Status:** live.
- **Recommendation:** decide in the prototype; drop the cardinality
  duplication either way.

### 20. Where human gates live, and the granularity the fixed name set costs

Raised by the author during review of the matrix; corrected against
the code after a first framing got the mechanism wrong. Not answered
here.

- **What the tree does.** The coupling is unidirectional and it is
  the chain that references the workflow: a tier's `delivery.phase`
  names the status it generates in, and a workflow's `statuses:`
  array never names a tier (`dsl-syntax.md` §11, v5 §7.10). A gate
  sits after a status; its review set is whatever the chain produced
  at that status. That is the intended shape, and it is what the
  loader enforces. The only closure is the *name set*: `chain.ex:736`
  requires `delivery.phase` to be one of `SystemStatus.kinds()`, and
  `workflow.ex:679` requires a ticket-skeleton `status:` name to be
  one of the same fixed kinds. So a gate can sit only after
  `generation`, `design`, `architecture` or `implementation`, and
  every tier that names the same kind is one batch. That is the
  limitation the author observed: an objection at
  `feature_expansion` regenerates `journeys` and `screens`, because
  all three name `generation` and no finer position exists to gate
  on.
- **What the tree does not do yet.** Nothing at runtime reads
  `delivery.phase` (matrix 1.2). The sweeper dispatches every ready
  `llm` tier project-wide with no reference to any ticket's position
  (`sweeper.ex:144`), `ReadyScopes` has no notion of a ticket or a
  flow, and the feature lifecycle's resting position is projected
  state that nothing in generation consults. So today no gate holds
  any generation, at any granularity; a human gate is a resting
  position on the board. The record says so: "there is no shipped
  enforcement of a declared allow-list ... that command edge is
  unbuilt (Phase 7)" (`dsl-syntax.md` 3013–3016), and the gate's join
  to the chain "is `systems/delivery.md`'s Phase 7 work, declared
  workflow gates being that phase's to build" (3145). The consumer
  that Phase 7 builds is exactly the one `delivery.phase` is waiting
  for: while a ticket rests at a generation-shaped position, the
  tiers dispatchable for its flow are those whose `phase` names that
  position. The matrix's `delivery:` row now says this.
- **So the "bug" is two things, of different kinds.** The closed name
  set is a loader restriction, two lines, cheap to lift. Gate
  enforcement against dispatch is reserved Phase 7 work that the
  record already owns. Lifting the first without the second changes
  what the board shows and nothing about what runs.
- **The option the first framing missed, and the one to take
  seriously: keep the direction, unbound the names.** A ticket-
  skeleton `status:` entry keeps its *kind* (the shapes the engine
  branches on: generation-shaped, review-shaped, the plane states)
  and gains a free *name*; a tier's `delivery.phase` names the
  position, not the kind. No new grammar is needed: `name:` on a
  status entry already exists (core_dsl#26, live, zero uses), so
  `status: generation, name: features` followed by `review:
  product-review` is legal syntax today, and `delivery: {phase:
  features, ...}` is one relaxed check away. The fixed generation
  kinds `design`/`architecture`/`implementation` (matrix 2.2,
  reserved, never authored) become unnecessary: they were the fixed
  table's way of admitting three named positions, and free names
  admit any number. Sub-arrays and derived throwback (entry 16)
  shrink for the same reason: a gate after a named position throws
  back to that position.
- **Composability under free names.** §11's "no compatibility
  contract to check" and v5 §7.18 are the reason the set was closed.
  Depth already shows the way through (v5 §7.19): a workflow's depth
  against a chain that fans out less "applies at the levels that
  exist, silently. It must *not* be a load error". The same rule for
  names keeps composability: a tier whose `phase` names a position no
  paired workflow declares runs at that position's kind, and the
  finer gate simply does not apply. A workflow is then portable
  across chains exactly to the degree it uses kind names, and
  chain-specific exactly to the degree it uses fine names, which is
  the author's choice per bundle rather than the platform's. Whether
  the loader also warns on an unmatched fine name is a small call;
  `load_axes/5` loads both bundles together, so it can.
- **Options struck.** *Bidirectional coupling* (a workflow gate
  naming a tier, alongside tiers naming statuses): out, by the
  author's rule that the reference runs one way only. *A chain-
  declared checkpoint list the workflow references*: the same idea as
  free names with the direction reversed, so it is out for the same
  reason. *Gates declared on the chain* (a tier carrying its own
  human gate): also reverses the direction, and moves organization
  policy into the chain bundle against v5 §7.16; out unless
  `delivery.phase` is abandoned entirely, which nothing argues for.
- **What remains to weigh.** Keep the fixed table (the tree; every
  new gate position is a platform vocabulary change, and ORC-179's
  kind-per-tier assignment is still pending) or free the names (two
  loader lines now, the Phase 7 consumer unchanged in shape, the
  three reserved kinds retired, entry 16's machinery reduced). The
  second is the smaller grammar and the one the author says was the
  intent.
- **What the prototype can test.** Write `default-flow` with named
  generation positions where the author would actually want gates in
  the product tier (`feature_expansion`, `journeys`, `screens`) and
  the chain's tiers naming them, and compare against the tree's
  version: lines, whether any sub-array survives, and what a second
  stack's workflow would have to change.
- **Status:** live grammar, reserved enforcement; the axis split and
  its direction stand. What this entry questions is only the closed
  name set, and it records that the runtime half is Phase 7 either
  way.
- **Recommendation:** free the names, by the depth rule, in the
  redesign; retire the three reserved kinds; amend `dsl-syntax.md`
  §11's "no compatibility contract" to state the silent-fallback rule
  and v5 §7.18/§7.19 to match; carry ORC-179 as "which position each
  default tier names", which is the same decision with a better
  answer available. Author's call.
