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
runtime module depends on it. Written from two passes over the
tree, one per axis (`evidence/seam-rules-chain.md`,
`evidence/seam-rules-workflow.md`); this section is the summary and
the decisions.

(Filled in from those passes below.)

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
- **b. The `status:` spelling for free names.** `status: generation,
  name: features` (existing keys) or `features: generation` (map
  form). One spelling; the contract states it.
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
