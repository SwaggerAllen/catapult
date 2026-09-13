# The seam pass — decisions

README §5 step 3, executed. Inputs: `seam-pass.md` (the questions and
first-draft recommendations), `classification-matrix.md` (every
construct, three columns, a class), `questioned-rows.md` (the
author's answers and the v4 cross-reference), `in-flight-tickets.md`
(ORC-246/247), and two rule-by-rule passes over report C's load-time
checks against the runtime (§2 below).

Two outputs, as the plan asked for: where each construct lands
(§1), and which load-time rules are the engine's and which are the
default bundle's habits (§2). §3 is the target key set that falls
out; §4 lists what is still the author's to decide, and nothing in
§1–§3 depends on those answers except where a row says so.

## 0. The levels

Every construct lands at exactly one of these:

| Level | Meaning |
|---|---|
| **G** | grammar, declared: the author writes it |
| **G-default** | grammar, defaulted: the author writes it only to override a derivation the loader states |
| **G-reserved** | grammar, marked reserved: intended consumer named; shape may move when it lands |
| **XSD** | a fact about the document, stated in the body grammar, not the DSL |
| **ENGINE** | a rule of the engine, stated in the contract as a rule, with no key |
| **BINDING** | project or platform configuration, not bundle content |
| **PROMPT** | content: prompt template or partial |
| **RETIRE** | removed from the grammar and the loader |

"Derived" in a G-default row means the loader computes the value and
the contract states the derivation in one sentence; the author can
still write the key. "No key" means the author cannot write it at
all.

## 1. Constructs

### 1.1 Chain axis

| Construct | Level | Derivation / rule / reason |
|---|---|---|
| `catapult.yaml` `chain:` / `workflow:` | BINDING | loader input naming one bundle per axis (core_dsl#7); stays |
| `bundle.yaml` `name`, `kind` | G | |
| `bundle.yaml` `version` | G-reserved | cutover (v5 §6); no consumer yet |
| `tiers:`/`edges:`/`flows:` globs | RETIRE | single-file chain (seam 1); a bundle is one `chain.yaml` plus `prompts/` and `schemas/` |
| `fragments:` vocabulary | RETIRE as a key; ENGINE derives | the vocabulary is the union of `produces` keys; the load check ("every `fragments[k]` walk names a produced kind") survives as a rule |
| `extends:` | ENGINE | one refusal line: unknown key; no layering (core_dsl#29) |
| tier name | G | map key |
| `scope: singleton \| per(X) \| child_of(X)` | G | required on every generated tier; `child_of(X)` single-sourced (ORC-247 `#45`, ENGINE rule stated with its readiness reason) |
| `scope: reference` | RETIRE | folded into the externally-sourced generator (seam 2, 3): such a tier has no scope by rule |
| `scope: cascade_visit` | G-reserved → likely ENGINE-derived | reserved with flows; under seam 12 the planning tier is derived from the flow declaration and no author writes this scope |
| `scope_filter:` | RETIRE | `questioned-rows.md` |
| `identity:` | G, required, no default | ORC-246; chosen per tier from the mint element's key. Placement (tier key vs `xs:appinfo` on the element) is §4.a |
| `fields: draft.* / mint.* / mint.parent.*` | G | |
| `fields: reference.*` | G-reserved | with the externally-sourced generator; no write path yet |
| `argument` reserved field | G-reserved → ENGINE-derived | with flows; a planning tier's fixed fields are the engine's if the tier is derived |
| `handle.fields` | G-default | default: every field plus what is produced onto the node; write to narrow. Add the subset check |
| `handle.fragments` | RETIRE as a key; derived | a node exposes what `produces` writes onto it |
| `draft.root_tag` | G-default | default: the tier name, hyphenated; 17 of 22 already are |
| `draft.grammar` | G-default | default: `schemas/<tier>.xsd`; 19 of 22 already are |
| `generator: llm` | G-default | the default when `prompt`/`draft` is present |
| `generator: synthesis` (join target) | RETIRE the name; G as absence | a tier with no `draft` and no generator is a join target (v4 A.1.1); if a keyword is wanted, `join`. The word `synthesis` is freed for aggregation if ever re-admitted |
| `generator: supplied` + `source:` | G | the one externally-sourced kind; absorbs `reference` |
| `generator: reference` | RETIRE | merged into `supplied` |
| `generator: external`, `template` | G-reserved | registry (Phase 7); `template` needs an owner named or joins the door-open note |
| `generator: git_commit`, `webhook` | G-reserved | author's intent recorded in `questioned-rows.md`: repo commits, history, events as context and flow triggers |
| generator option keys | with their generator | listed in the grammar table, not prose |
| `prompt:` | G-default | default: `prompts/<tier>.md.liquid`; existence checked at load, not dispatch |
| `executor:` | G-default | default `{effort: max}`; reserved consumer is executor-profile routing |
| `context:` | G, **map form** | name → walk or list of walks (seam 7, ORC-247). Naming is mandatory and explicit; the merge-by-tier rule and the `as:` form question dissolve; reserved names (`self`, `feedback`, `prior_review`, `draft`, `raft`) and key uniqueness are the only collision rules |
| walk forms: `self`, `self.parent`, hops, `~`, `->`, `.fragments[k]`, `all.<tier>`, `input.<role>`, `input.*` | G | unchanged; `-> <tier>` with `handle` as the default projection |
| `all.<tier>` driver-closure refusal | ENGINE | ORC-247 `#46`, stated with its readiness reason; `cascade_visit` targets included |
| `.synthesis` projection | RETIRE | no refusal line needed once the generator is renamed |
| `ticket.findings` walk source | G-reserved | flows + delivery findings |
| `produces:` | G, **map form** | `kind: draft.<path>`; owner implied (parent); `owner: self` retired |
| `delivery.phase` | G-default, **free names** (seam 20) | default: the kind implied by the tier (generation for `llm`, critique for a review); write to name a finer position. Unmatched fine name runs at its kind, silently (the depth rule) |
| `delivery.agent_step` | G-default | default from the tier's role (design / critique); reserved consumer is dispatch routing |
| `enforcement:` | G-reserved | v5 §6 profiles; Phase 7 |
| `reviews: <tier>` (review tiers) | RETIRE as tiers; G-default `review:` on the tier | default: `prompts/review/<tier>.md.liquid` if present; context equality holds by construction; the 17 files go |
| review tier `grammar:` | ENGINE default | `schemas/review.xsd` is platform-wide; a key only to override |
| body attrs `implementation:`, `swap:` | XSD | |
| edge name | G | groups instances of one type |
| `type:` | G | `fanout`, `reference`, `dependency`, `policy_application`; `synthesis` G-reserved with flows (and likely derived, seam 12) |
| inline `source`/`target` form | RETIRE | the instance is the unit (seam 4) |
| `instances[].{source, target, declared_in}` | G | |
| `source_ref` / `target_ref` | G-default | derived: `self` / `self.parent` structurally, `@from`/`@to`/`@ref` by row-attribute convention; written only when the convention cannot express the endpoint |
| `cardinality.{source,target}.{min,max}` | XSD | `minOccurs`/`maxOccurs` on the declaring element; the 62 shipped rows are all this |
| `cardinality.when` + named predicates | G-reserved | projection-time content invariants, rejecting the commit (v4 A.2.8); the predicate language survives for this |
| `cardinality.per_source` | RETIRE | |
| `graph_constraint` | ENGINE | acyclic + no self loop is a rule of the `dependency` type; `tree` retires with no use |
| `consistency` | G-reserved | v5 §2.6; no phase named |
| `navigation: true` | G | has a reader (walk ban); could become a type; either is one line |
| `constraint` | RETIRE | |
| flows: `name`, `walk`, `entry`, `prompt`, `targets`, `context` | G-reserved | the varying part (seam 12); flow-engine ticket re-settles |
| flows: planning tier, `plan_target`, `predicates.yaml` completion | ENGINE-derived, reserved | derived from the flow declaration; v4 A.5.5 already had the engine detect completion |
| `ticket.labels` | G-reserved | with the flow ticket face |
| prompt variables, partials | PROMPT | content contract, stated once in the chain doc's prompt section |
| XSD grammars | XSD | |
| extension registry, dialects, extension kinds | G-reserved, narrowed | holds executors (generator types, context sources, annotation namespaces, enforcement profiles); grammar grows by reviewed core edit |
| `role_holders:`, `mirror_mapping:` | BINDING, reserved | loader inputs, not bundle content |

### 1.2 Workflow axis

| Construct | Level | Derivation / rule / reason |
|---|---|---|
| `gates:`/`environments:`/`types:` globs | RETIRE | single-file workflow: one `workflow.yaml` |
| `entry:` | G | reserved consumer (provisioning) but the key is the only way to name the root |
| type name | G | map key |
| `skeleton:` | G, **open** (§4.c) | kept as today pending seam 21; if the third placement is taken it shrinks to lifecycle states |
| `statuses:` ordered array | G | |
| `status:` entry | G, **free names** | `status: <name>` where the name resolves to a *kind* by declaration: either `status: generation, name: features` (the existing keys) or `features: generation` (map form); the contract picks one spelling. The fixed set becomes the set of *kinds*, not of names |
| `review:` entry | G | |
| `environment:` entry | G-reserved | with a note that both lifecycle sequences drop it today |
| sub-array grouping | G | kept (author, `questioned-rows.md`) |
| `name:` on a status entry | G | kept; load-bearing for seam 20 and for multi-role review |
| `<anchor>.<name>` references | G | with sub-arrays |
| `flow:` on a population anchor | G | |
| `blocks:` | G | |
| `depth:` on `critique` | G-reserved | review passes at depth (generation target) |
| kinds `pending`, `generation`, `critique`, `checks`, `reconcile`, `merge`, `deploy`, `terminal` | G (closed set of kinds) | `reconcile`/`merge` are §4.c's question |
| kinds `setup`, `prep`, `main`, `retro`, `cleanup` | G | container five |
| kinds `design`, `architecture`, `implementation` | RETIRE | free names make them unnecessary (seam 20); ORC-179 becomes "which position each default tier names" |
| kinds `backlog`, `blocked`, `stubbed`, `validating` | ENGINE | plane states; in the engine doc, out of the bundle contract |
| gate `review` name, `role` | G | |
| gate `depth` | G | wanted (`questioned-rows.md`); the "0 is the rule" sentence goes |
| gate `throwback` | G-default | derived: the head of the enclosing sub-array; written to override |
| gate `escalation` | G-reserved | delivery Phase 7 |
| environment `promote_from`, `depth`, `lifetime` | G-reserved | with environments; `per_ticket` is PR environments |

### 1.3 What moved across the seam, in one place

- **Into the XSD:** plain cardinality; body attributes (already there).
- **Into engine rules with no key:** `graph_constraint`; the `fragments` vocabulary check; the driver-closure and single-source readiness rules; the plane-owned status kinds; `extends` refusal.
- **Into defaults:** `handle.fields`, `root_tag`, `grammar`, `prompt`, `generator: llm`, `executor`, `delivery.*`, review as a tier property, `source_ref`/`target_ref`, gate `throwback`.
- **Out of the grammar entirely:** `scope_filter`, `constraint`, `per_source`, `owner: self`, `scope: reference`, `generator: reference`, `reviews:` tiers, inline edge form, the globs, the `.synthesis` projection, the three named generation kinds, the merge-by-tier variable rule.
- **From loader derivation into declaration:** context variable names (the map form replaces `as:` and the merge rule).
- **From the workflow into the chain (open):** the generation → reconcile → merge relation, if seam 21's third placement is taken.
- **Nothing moved from engine code into the grammar.** The pass found no engine behaviour that a bundle author needs to vary and cannot.

## 2. Rules

Report C's 69 load-time checks, plus the chain checks `chain.ex`
implements that C does not list, each classified by whether a
runtime module depends on it. Two passes over the tree, one per axis
(`evidence/seam-rules-chain.md`, `evidence/seam-rules-workflow.md`),
each naming the module and function that misbehaves without the
rule, how, and the weaker form that suffices. Counts are from the
tables, recounted:

| Class | Chain (42 rows) | Workflow (44 rows) | Meaning |
|---|---|---|---|
| ENGINE | 20 | 6 | a runtime module misbehaves without it |
| LOADER-ONLY | 17 | 11 | keeps a loader derivation consistent; nothing downstream reads it, or the runtime tolerates the violation |
| HABIT | 2 | 18 | no reader; a convention or design opinion; a violating bundle loads and runs |
| NEGATIVE | 3 | 9 | a "no check exists" sentence or a derivation, not a rule |

### 2.1 What the engine actually requires

**Chain.** The live core is exactly what §1 kept. Edge endpoints must
name declared tiers (an undeclared target mints nodes no walk can
settle). `scope` must be one of the closed kinds (`ReadyScopes
.candidates/3` has one clause per kind and raises otherwise). Type-
level acyclicity is required **over `fanout` instances only**:
`tier_drained?` recurses driver chains with no visited set, so a
fanout cycle exhausts the stack, while `reference`/`dependency`
cycles are harmless to every runtime reader. The ORC-232/236
mirrors (`declared_in` and `draft.*` paths resolve in the XSD;
locator forms; `mint.parent` names a provided field) are engine-
required as stated, because they are the same `EdgeLocator` and
navigation the commit path runs, and the failure mode is a silent
`nil`. `all.<tier>` must name a declared tier and must not target a
reference-scope tier (permanent unreadiness). Walk hops must name a
declared edge with the walker on the right side, else readiness is
vacuously true and the prompt variable is silently missing. The
projection set is closed because `render_fragments/3`'s clause heads
are the set. Cardinality bounds must be integers where present.

Three rules are **weaker than stated** in the contract: `scope_filter`
is the only predicate slot with an evaluator (retired anyway); a
`scope: reference` tier must merely never be dispatchable, the
pairing itself is opinion (retired anyway); `-> <tier>` on a `self`
walk is a type annotation the runtime never consults. One rule is
**stronger than stated**: `produces` owner must be `self.parent`,
not "`self` or `self.parent`" (retired to the map form, owner
implied).

**Workflow.** Six rules, and three of them in a weaker form than the
contract states:

- Every `status:` kind must be an existing atom
  (`FeatureLifecycle.Sequence.to_position/1` calls
  `String.to_existing_atom` on the kind and crashes the process
  manager otherwise). It atomizes `status`, never `name`, so **free
  names are safe under the `status: <kind>, name: <free>` spelling**
  and the closed set is a set of kinds. This settles §4.b.
- A population anchor carries `flow:` (`Status.queue_shaped?` is what
  `ContainerQueues.admits?`, `unresolved_queues` and `Composition`
  branch on; without it a queue silently becomes a one-shot slot).
  The "absent elsewhere" half is tolerated.
- The declaration graph is acyclic and no type nests itself
  (`ContainerLifecycle.open_for/3` mints an unbounded ladder of
  containers otherwise).
- Every sub-array has **at least one** non-review-shaped agent-balled
  entry (`Type.namespaced_positions/1` raises on zero, and every
  runtime reader on both axes and both LiveViews goes through it).
  "Exactly one" is the contract's; the second anchor is tolerated.
- Names are unique within a namespace (two entries with one
  qualified name make the container dispatcher loop forever between
  them).
- No gate name equals any status name, bare or qualified (the gate
  lookup precedes namespace resolution; a collision pins a ticket at
  a gate it is not at).

### 2.2 What is loader-only, and what happens to it

Chain loader-only rules fall with the constructs §1 retired or
derived: the fragment vocabulary checks (derived from `produces`), the
review-tier rules including context equality (gone with review tiers;
`ContextAssembly` already recomputes the reviewed tier's context and
never reads the review tier's), the reference-scope rules (gone with
`scope: reference`), `enforcement`/`ticket.*` registrations
(reserved markers), the `extends` refusal (one line). Duplicate-name
and scope-target checks stay as ordinary referential checks.

Workflow loader-only rules: `throwback:` earlier-than (kept; it is
re-derived at the command edge, so the declaration is only a
default), `skeleton` membership, sub-array flatness, name-ambiguity
(kept with sub-arrays). Two are worth naming because the runtime
disagrees with the loader: `blocks:` is resolved by namespace at
load and matched by **bare kind** at runtime (`ContainerQueues` holds
on every occurrence of a recurring kind, which is the case the loader
refuses); and `entry:` has no reader anywhere outside the loader.

### 2.3 What is habit, and leaves the contract

Chain: `delivery.phase`/`agent_step` membership in the fixed
vocabulary (nothing reads `Tier.delivery`; replaced by free names
with the depth rule, seam 20). The navigation-edge walk ban has no
runtime reader either, but it is a platform design rule with a
recorded reason (v5 §4.3), not the default's habit; it stays as a
stated rule.

Workflow, eighteen rows, of which the ones that matter:

- **Both skeleton backbones** (`setup, prep, main, retro, cleanup,
  terminal`; `pending, generation…, checks, merge, deploy,
  terminal`). `ContainerLifecycle` iterates the declared array and
  closes at `terminal` *or* end of array; `FeatureLifecycle.Sequence`
  reads `checks` and `merge` only as a reachability boundary and
  tolerates their absence. Nothing reads `setup`/`prep`/`main`/
  `retro`/`cleanup` by name; `Composition` takes the first
  queue-shaped entry.
- **`merge` preceded by `reconcile`.** `reconcile` has no runtime
  reader at all.
- **`pending` immediately before each generation-shaped entry, and
  before `deploy`.** Nothing dispatches on `pending`; the projection
  auto-passes it; the fallback reads whether a group starts with one
  and tolerates absence.
- **`critique` adjacent to its generation entry.** No module positions
  on `critique`; the projection auto-passes it wherever it sits.
- The unknown-field rule and its four restatements, `depth:` shape
  (kept as plain typing), escalation shape, the two opt-in checks,
  the naming-discipline rule, the runtime-dialect refusal, and the
  explicit-`throwback:` requirement for an ungrouped review, which
  the loader never implemented.

This is the finding that bears on seam 21: **the ticket skeleton's
backbone and the generation → reconcile → merge relation are pure
contract today.** No runtime module enforces or reads them; the ~130
lines of §13 that state them (report C #26–#29) and the ~760 lines
of §15.1–§15.3 that explain them constrain authors without
constraining the engine. Whatever placement §4.c chooses, the rules
as written are the default bundle's shape stated as law, and the
contract should carry only the six rules in §2.1 plus whatever the
chosen placement genuinely needs.

### 2.4 Gaps the passes surfaced

Not rules, but things the contract claims or the runtime assumes that
the other side does not honour. Each is a ticket or a contract
sentence, and the redesign should not repeat the claim:

- `prompt:` and `draft.grammar` paths are never resolved at load
  (§13 says they are); a missing prompt is an Oban retry loop at
  dispatch. §1 makes existence a load check.
- `per(X)` scope chains are recursed by `tier_drained?` but never
  cycle-checked.
- A review tier's `context:` is dead at runtime (moot once reviews
  are tier properties).
- Every `ticket.<source>` walk blocks readiness unconditionally,
  registered or not (moot while reserved; the marker should say so).
- `blocks:` namespace semantics differ between loader and runtime
  (§2.2).
- `entry:` is validated three ways and read by nothing.
- The `throwback:`-required rule for ungrouped reviews is in the
  contract and not in the loader.

## 3. The target key set

What an author can write after §1, before any prototype iteration.
Reserved keys are included and marked; derived defaults are listed
under the key they default.

**`catapult.yaml`:** `chain`, `workflow`.

**`chain.yaml`:**

```
name, version*, kind: chain
tiers:
  <name>:
    scope            singleton | per(X) | child_of(X)      (absent on a supplied tier)
    identity         id | alias | name | slug               (required; §4.a may move it)
    fields           {<name>: draft.<path> | mint.<name> | mint.parent.<name> | reference.<name>*}
    handle           [<field>...]        default: all fields + produced kinds
    draft            {root_tag, grammar} defaults: <name>, schemas/<name>.xsd; absent = join target
    generator        llm (default) | supplied | external* | template* | git_commit* | webhook*
    source           input.<role>        (supplied only)
    prompt           default: prompts/<name>.md.liquid
    review           default: prompts/review/<name>.md.liquid if present
    executor         default: {effort: max}
    context          {<variable>: <walk> | [<walk>...]}
    produces         {<kind>: draft.<path>}
    delivery         {phase, agent_step}  defaults from the tier's role; phase may be a free name
    enforcement*     [<profile>...]
edges:
  <name>:
    type             fanout | reference | dependency | policy_application | synthesis*
    navigation       bool
    consistency*     eventual | transactional
    instances:
      - {source, target, declared_in, source_ref?, target_ref?, when*?}
predicates*:         {<name>: <predicate>}                 (cardinality.when, completion)
flows*:
  <name>: {walk, entry, prompt, targets, context, labels}
```

**`workflow.yaml`:**

```
name, version*, kind: workflow
entry: <type>
types:
  <name>:
    skeleton         ticket | container | absent          (§4.c)
    statuses:        [ <entry> | [ <entry>... ] ]
      <entry> :=  {status: <kind>, name?: <free>, flow?: <type>, blocks?: [...], depth*?: n | [a, b]}
                | {review: <gate>}
                | {environment*: <env>}
gates:
  <name>: {role, depth, throwback?, escalation*}
environments*:
  <name>: {promote_from?, depth?, lifetime}
```

Asterisks mark reserved. Kinds: `pending`, `generation`, `critique`,
`checks`, `reconcile`, `merge`, `deploy`, `terminal`, `setup`, `prep`,
`main`, `retro`, `cleanup`. Walk forms and predicate forms are
unchanged from the current §7 and §8.

Chain keys an author may write, counted from the listing above: 14
tier keys (`scope`, `identity`, `fields`, `handle`, `draft`,
`generator`, `source`, `prompt`, `review`, `executor`, `context`,
`produces`, `delivery`, `enforcement`), of which 7 carry a default
(`handle`, `draft`, `generator`, `prompt`, `review`, `executor`,
`delivery`) and 1 is reserved (`enforcement`); 4 edge keys (`type`,
`navigation`, `consistency`, `instances`) and 6 instance keys
(`source`, `target`, `declared_in`, `source_ref`, `target_ref`,
`when`), of which 2 are defaulted and 2 reserved; and the reserved
`predicates` and `flows` blocks. Down from the ~60 the current §1–§12
define, with no construct the engine reads removed.

## 4. Still the author's

- **a. Where identity is declared.** On the tier (`identity:`), or on
  the mint element in the XSD (`xs:appinfo`), which makes the schema
  the single source for "which attribute is the key" (seam 19). The
  prototype writes both and the author picks.
- **b. The `status:` spelling for free names.** Settled by §2.1 in
  favour of the existing keys, `status: generation, name: features`:
  the runtime atomizes `status` and never `name`, so the kind stays a
  closed atom set and the name is a free string with no code change.
  The map form would need the same guarantee re-established.
- **c. Where reconciliation lives** (seam 21), and with it whether
  `skeleton:` survives as more than `ticket | container`, and whether
  `reconcile`/`merge` stay authorable kinds.
- **d. A tier family with several drivers** (seam 2, ORC-247): three
  same-shaped policy tiers, or one declaration with three drivers and
  per-instance readiness in the engine. The grammar in §3 expresses
  the first; the second is engine work.
- **e. `generator: template`**: name an owner, or fold it into the
  door-open note with `git_commit`/`webhook`.
- **f. The acceptance number** (README §4.8).
