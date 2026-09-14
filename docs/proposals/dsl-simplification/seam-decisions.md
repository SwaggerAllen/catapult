# The seam pass — the changes, each with its argument and the author's decision

README §5 step 3. This file argued every change and left the standing
to the author; the author has now reviewed every item, and each entry
below carries the decision alongside the argument that was made for
it, the argument against, and the evidence. Where the author's answer
changed the recommendation, the entry says what the earlier
recommendation was and why the author's reason wins, because that is
the reason a later pass would otherwise re-derive the earlier shape.

## 0. How to read this

Every change carries: the change; the argument for it; the argument
against it and what it costs; the evidence, cited; and its
**decision**, one of:

- **decided** — the author accepted the change as argued, or with the
  amendment the entry states;
- **decided, amended** — the author took a different shape from the
  one recommended, and the entry gives the author's reason;
- **decided, on review** — a shape this pass proposed after the first
  review and the author confirmed or corrected in the second (§5).

Inputs: `seam-pass.md`, `classification-matrix.md`,
`questioned-rows.md`, `in-flight-tickets.md`, the two rule passes in
`evidence/`, and the author's review of the earlier version of this
file.

## 1. How the two bundles interact

The proposal so far treated the axes as near-orthogonal and analysed
each on its own. They are not orthogonal, and several changes below
depend on saying exactly how they meet. This section is the analysis
that was missing, and it now states the interaction as it will be once
§2 lands.

### 1.1 The interaction points that exist by construction

**a. A tier names the position it runs at, and the reference runs one
way.** `phase:` is the declared cross-axis reference: the chain
references workflow positions; the workflow never names a tier
(`dsl-syntax.md` §11, v5 §7.10). Today nothing reads it at runtime
(matrix 1.2); its Phase 7 consumer is dispatch gated by the ticket's
resting position, which is what makes a human gate hold generation at
all. Under §2.C.1 the reference is **strict**: the position a tier
names must exist in the workflow type its flow dispatches into, and
the loader refuses a chain whose tiers name positions the paired type
does not declare.

**b. Chain fan-out becomes workflow child tickets.** v5 §7.5: "One
feature branch with one PR to main; each child ticket gets its own PR
merging into the feature branch." core_dsl#22: architecture fan-out is
recursive child tickets, and `merge` fires only at the root. v5
§7.19: a status carries a fan-out depth and "a child's effective
sequence is the declared sequence filtered to its depth". So a
`fanout` edge in the chain (`sysarch → comp`, `comparch → subcomp`,
the frontend families) implies, on the workflow side: child tickets
running the same declared sequence one level down, their PRs joined
into the parent's at `reconcile`, and `merge` at the root. This is
the relation the ticket skeleton encodes, and it is not the default
bundle's habit: it is what Phase 7's PR mechanics require of any
chain that fans out.

**c. A tier's review runs at a critique position after the tier's
own.** Under §2.A.4 a review is a property of the tier it reviews, so
its position is derived: the first critique-kind position after the
tier's own position in the paired type, overridable by an explicit
`phase:` on the review block. The workflow's rule about where a
critique may sit (§2.B.9) is the workflow-side statement of the same
structure.

**d. A fan-out's reconcile prompt lives on the fan-out tier; the
reconcile position lives in the workflow.** §2.C.2. The chain says
what an agent does when the children are joined; the workflow says
where in the sequence that happens and what gates sit before and
after it.

**e. A population step's tickets land where the workflow says.**
§2.B.7. A `setup` or `retro` tier emits tickets; the workflow's
`fills:` on the status names the queue they land in. The chain says
what a node emits, the workflow says where it goes, which is the same
split 1.1.d makes for reconcile.

**f. Under free names, a position is whatever the workflow declares
and a tier names.** Every `llm` tier in the default names `phase:
generation` today, so the product draft at depth 0 and each
component's architecture at depth 1 are the same position,
distinguished only by depth, and a gate between `feature_expansion`
and `journeys` is inexpressible. §2.C.1 frees the names: a workflow
declares as many generation-shaped positions as it wants gates
between, and each tier names its own. The fixed kinds remain the
*shapes* the engine branches on (generation-shaped, review-shaped,
the plane states); the *names* are the bundle pair's.

### 1.2 What each side assumes of the other, and what checks it

| Assumption | Held by | Checked? | On violation |
|---|---|---|---|
| Every position a tier names exists in the type its flow dispatches into | chain | **yes, at load** (§2.C.1) | load error |
| The flow's tiers, ordered by their walks, fit the type's positions in order | chain | **yes, at load** (§2.C.1 traversability) | load error |
| Every generation-shaped position in the type is named by some tier of the flow | workflow | at load, as a **warning** (§2.C.3) | the position is skipped, the same way a depth the chain never reaches is |
| The chain fans out at the depths the workflow's gates name | workflow | at load, as a warning (§2.C.3) | depth is a maximum; a shallower chain applies the levels that exist |
| A position that fans out has children to reconcile | workflow | no | v5 4231: the mechanical merge and the reconcile read happen regardless; with no children it is a no-op fan-in |
| Children run the declared sequence filtered by depth | both | implied by v5 §7.19 | a workflow with all gates at depth 0 handles a fanned chain: children generate, check, reconcile and merge with no human gates |

The last row answers the question about serial versus fanned tiers at
every level: the depth mechanism *does* let one workflow accept both,
because fan-out changes only which levels the gates apply at, not
whether the sequence runs. What fixed kinds could not do was gate two
different generation passes at the same level differently; free
names do that, and strict binding is what keeps a shared pair
coherent.

### 1.3 Compatibility versus autonomy — decided: autonomy, strict

The question was whether status names stay a platform-fixed table
(compatibility: a workflow shared alone can gate on positions every
chain has) or are free per bundle pair (autonomy: gates wherever the
pair wants them, and no platform vocabulary change per new gate
position).

*For compatibility.* Bundles exist for community-scale sharing (v5
§8's premise). A workflow shared across chains must gate on positions
every chain has, and the fixed kinds are that shared vocabulary.

*For autonomy.* The fixed table forces batching the author considers a
bug; every new position anyone wants is a platform vocabulary change,
which is the growth-in-content-tickets pattern; Siege allowed review
after every tier.

*The middle that was recommended, and why it fails.* The earlier
version of this file recommended kinds as the shared vocabulary with
fine names as an opt-in that degrades to its kind on a chain that
does not declare it. The author's objection is decisive: the skeletons
already stipulate several positions of most kinds, so "degrade to the
kind" has no single position to degrade to. A tier naming `design`
under a workflow declaring `design/features` and `design/journeys`
would need a rule for which position it runs at, gates after the
empty one would need a rule for whether they hold, and throwback to an
empty position would need a fallback. That is a second mechanism to
carry for the sake of a portability the author does not want to
promise.

*Decision.* **Free tier-status binding, strict.** Standard names are
expected to emerge from use as convention rather than be handed down;
the default pair ships with the names the author wants gates between.
The loader is strict: a position a tier names must be present in the
paired type. The traversability check (§2.C.1) and the cross-axis
warning (§2.C.3) are what replace the fixed table's guarantee. A
workflow shared alone is shared with its position names, and a chain
that wants to run under it names them; a pair is shared as a pair.

## 2. Recommended changes and decisions

### A. Chain grammar

**A.1 One `chain.yaml` instead of one file per tier and edge.**
*Argument:* the file layout was never decided (report F); 51 tier
files carry 600 lines of header comment and a tier name repeated in
three paths each; the design-carrying content is a few hundred lines
(report D part 6); the workflow axis already made this move
(core_dsl#14) with no regret recorded. A single file is what the
author originally imagined and what a newcomer can read in one
sitting, which README §4.8 makes the acceptance test. *Against:* per-
file diffs are smaller and per-tier ownership is clearer in review; a
long YAML file is its own readability problem. *Evidence:* D parts 1
and 4; F part 2. *Decision:* **decided.** The author adds the
strongest argument: a modification UI edits one document, and a
per-file layout would have it creating and deleting files to add a
tier. The single-file diff story is also preferred.

**A.2 Defaults for `root_tag`, `grammar`, `prompt`, `generator: llm`,
`executor`, derived from the tier name, plus a bundle-level
`defaults:` block.** *Argument:* 17 of 22 root tags, 19 of 22 grammars
and nearly every prompt path already equal the derivation; `executor`
is `max` in all 10 uses; `llm` is already the default. A default the
author writes to override costs nothing where the value differs and
removes a line everywhere else. *Against:* implicit paths are harder
to grep for. *Evidence:* D part 2. *Decision:* **decided, amended.**
The chain file carries a `defaults:` block at its top, sitting between
the platform derivations and the tier, for per-tier scalars such as
the executor profile and the generator, never for context. The
author's reason for the effort default belongs on that block as a
comment: the first steps of the chain are sorting steps, which need
the extra effort because they are not primarily text generation.

**A.3 `handle` defaults to every field plus every produced kind;
narrowing is an override with a subset check.** *Argument:* checked
against the tree, **no shipped tier narrows its handle**: every one
of the nine spine tiers and all ten join targets expose `[id] +
every field`. The 34 blocks carry no information. v4's purpose for
`handle` (A.1.6, the public surface) survives as an override.
*Against:* information hiding between tiers is a real design tool and
a default of "everything" nudges authors away from it. *Decision:*
**decided.** The author's reason: if a tier generates something, it
is almost always so it can be passed as context. The subset check is
added, since today none exists.

**A.4 Review as a tier property (`review:`), not a review tier.**
*Argument:* all 17 review tiers are seven keys of which four are
constants and one is a byte-identical copy of the base tier's walks;
the load rule that the copy is exact exists only because the copy
exists; and `ContextAssembly` already ignores the review tier's
context and recomputes from the reviewed tier (seam rules, chain
#10). *Against:* a review tier could one day want a different context
than its base. *Decision:* **decided.** Reviews were a special case
already; if a review ever needs different context from the tier it
reviews, `review:` takes a `context:` key rather than a new tier. The
review's position is derived per §1.1.c, overridable with `phase:`
inside the block.

**A.5 Context: derived from edges by default, named when explicit.**
*Argument as first made:* ORC-247 found the merge-by-tier rule
silently fusing distinct reads at eighteen sites, and mandatory naming
removes the merge rule. *The author's question* was how much of
context could be a default behaviour based on edges, since with few
exceptions every tier reads its ancestors whole and then its upstream
siblings, and every edge except navigation carries context. *The
census answers it.* Across all tiers, reviews included:

| Pattern | Walks |
|---|---|
| `self.parent.handle` | 28 |
| `self.parent.<edge> -> tier.handle[.fragments[k]]` | 40 |
| `self.reference -> ref.handle` | 18 |
| `self.plan_target -> ...` (the five flows) | 21 |
| reversed or two-hop walks | 2 |
| `all.<tier>.handle` | 41 |
| `input.<role>` | 15 |

The first four rows, 107 of 165, are each an edge whose source is
self or the scope parent, and the projection varies by *edge type*,
not by tier: every `dependency`-typed edge reads `fragments[pubapi]`,
every `reference`-typed edge reads the whole handle, `fanout` edges
are never read, and `navigation` is never read. Checked for the
subtraction case, a tier that has such an edge and does not read it:
none. *Decision:* **decided, amended** to the following shape.

- The scope parent's handle is derived from `scope: per(X)`.
- Each edge declaration carries its default context projection, or
  none: `dependency: {type: dependency, context: handle.fragments
  [pubapi]}`, `navigation: {type: reference, context: none}`. A tier
  receives every edge instance whose source is self or its parent,
  projected by the edge, and the variable is the edge name.
- A tier's own `context:` map is additive: the three collarch tiers
  that also read `failure_surface` add one line each; comparch's
  reversed `policy_application~` walk stays explicit; `all.*` and
  `input.*` reads, 56 walks, are not edges and are always explicit
  and named.
- The naming rule from the earlier version applies to the explicit
  reads only; derived reads need no name.

*Cost, and its mitigation:* a derived read is not visible in the tier
(the same cost A.2 accepts), so the prototype ships with a task that
prints a tier's effective context, and the prompt author reads that
rather than the declaration.

**A.6 `produces:` as a map `kind: draft.<path>`; owner implied;
`fragments:` vocabulary derived.** *Argument:* every one of the 24
shipped rows and every v4 example is `owner: self.parent`; `owner:
self` never existed in v4 and the engine discards it; the bundle-
level vocabulary is the union of produced kinds and nothing else.
*Decision:* **decided.**

**A.7 Plain cardinality moves to the XSD; `cardinality.when` stays,
reserved.** *Argument:* all 62 shipped `min`/`max` rows are either
`minOccurs` facts about the declaring element or tautologies of the
edge type. *The author's concern* was that cardinality should be
enforced to keep the AI honest, and that the split should be
consistent if `when` is forced to the DSL side. *What the tree says:*
the XSD is already the enforcer. The commit path validates every
draft against its grammar before the event lands (`Dsl.validate_draft`
in `generation/commit_path.ex`), so `minOccurs` and `maxOccurs` reject
a body today, and the DSL's 62 rows are the copy nothing reads.
*Consistency:* the line is not "counts in the XSD, `when` in the
DSL"; it is **a constraint over one document is the document
grammar's; a constraint across nodes is the chain's.** `when` is
cross-node by construction, since it counts children by a field value
(v4's "foundation at every level"), so the split is by what the
constraint ranges over. *Decision:* **decided**, with that sentence in
the contract.

**A.8 The instance is the unit; drop the inline edge form.** Edges are
declared two ways today. Six files carry an `instances:` list of
`source`, `target` and `declared_in` rows, 58 rows in all. Four files
(`calls`, `navigation`, `renders`, `uses_shapes`) put a single
instance's keys at the top level of the file, and the loader has a
rule that a file is one shape or the other. *Argument:* always write
the list, even for one instance; the second shape and its exclusivity
check go, at the cost of two lines on four edges. *Decision:*
**decided.**

**A.9 Endpoint locators stay explicit.** The earlier recommendation
was to default them by convention (`self`, `self.parent`, a row's
`from`/`to`/`ref` attribute). *Decision:* **decided, amended**: the
author prefers explicit locators for self-documentation and to remove
a rule to remember. Low stakes either way; explicit wins.

**A.10 Retire `scope_filter`, edge `constraint`, `per_source`.**
*Argument:* each served a v4 mechanism v5 removed by recorded
decision, none is used, and `scope_filter` is the only evaluated
predicate slot. *Evidence:* `questioned-rows.md`. *Decision:*
**decided.**

**A.11 Rename the join-target generator; merge `reference` into
`supplied`; retire `scope: reference`.** *Argument:* v5 §5.1 reused
v4's `synthesis` (a computed aggregation body) for a node with no
body; a tier with no draft is a join target by v4 A.1.1 and needs no
keyword. `reference` and `supplied` are both "externally sourced,
never generated, never drained". *Decision:* **decided**, with the
author's condition: enough syntax stays to identify supplied nodes and
propagate changes from them. That syntax is `generator: supplied` plus
`source:`; `ref`'s write path (ORC-236) becomes a `source:` value
rather than a second generator, so the two kinds of supply are one key
with two values, and re-pinning a source is what re-drains downstream.

**A.12 `delivery.phase` explicit and required; `agent_step` dropped.**
The earlier recommendation was to default both from the tier's role.
*The author's question* was what the "roles" are, since tier roles
and user roles have already been confused. *What the tree says:*
there is no `role:` key on a tier. Three things carry the word: a
gate's `role:`, the human holder set, live and checked against
holders; `input.<role>`, the intake document tag, live; and
`delivery.agent_step`, whose values are `design | dev | critique |
reconcile | validate`, which v5 calls agent kinds. The bundle uses
`design` on all 22 generating tiers and `critique` on all 17 reviews,
nothing at runtime reads it, and its intended consumer was the
bindings file mapping agent kind to a runtime implementation. That is
the collision: `ux-review` carries `role: design` and every tier
carries `agent_step: design`, meaning different things. *Decision:*
**decided, amended.** `agent_step` is dropped; its job belongs to the
executor profile and its current value is derivable. `phase:` stays,
is required on every tier (§2.C.1), and is the only cross-axis key a
tier carries. The `delivery:` wrapper goes with `agent_step`, since
`phase:` alone does not need a block.

### B. Workflow grammar

**B.1 Keep sub-arrays; keep `name:`; keep gate `depth`.** *Argument:*
the author's, recorded in `questioned-rows.md`: sub-arrays give the
default throwback, bound how far a child may lead its parent, scope
reconcile and merge, and are the board's grouping; `name:` is the only
way to distinguish two entries of one kind, and under §2.C.1 every
position name is a `name:`; gate depth is wanted. *Decision:*
**decided.**

**B.2 Gate depth defaults to all depths; less review is the explicit
choice.** The earlier change was only to delete the sentence "Depth 0
is the rule for a gate" (`dsl-syntax.md` 2349, attributed to v5 §7.19
which says the opposite). *The author went further:* "gate only the
highest-level artifact" may apply to more nodes, but there is no way
today to say "run at all depths", and having that be the default makes
doing less review always an explicit choice. *Why it is well defined:*
under v5 §7.19 a gate applies in every child whose depth it reaches,
so "unbounded" is a legal value and the default. *Decision:*
**decided.** The sentence goes; the default flips; `depth: 0` is
written where the top level alone is meant.

**B.3 Gate `throwback` defaults to the enclosing sub-array's
generation position.** *Argument:* that is the current derivation; the
command edge re-derives legality anyway (seam rules, workflow #24), so
the declaration is only a one-click default. *Decision:* **decided.**
Under B.8, "kick back to pending" becomes "kick back to the group's
generation position with the waiting flag set", which is the same
thing.

**B.4 `blocks:` targets by namespace, with the throwback reference
syntax; the runtime is corrected.** *Argument:* the loader resolves
`blocks:` targets by namespace and refuses a recurring kind;
`ContainerQueues.held_or_resolved/3` matches by bare kind and holds on
every occurrence. One of them is wrong. *Decision:* **decided**: the
loader is right. `blocks:` and `throwback:` share one reference syntax
(they already share `resolve_reference/2`), and the projection's
matcher is rewritten against the namespaced reference. One function;
a small ticket.

**B.5 Drop the "ungrouped review must declare `throwback:`" rule.**
*Argument:* it is in the contract and not in the loader; the runtime
tolerates a nil default (`derived_throwback/2` returns nil for an
ungrouped gate), and a nil target only means no one-click landing
point. *The author's case:* a gate after the top-level PR closes,
between a staging and a prod deploy, has no obvious throwback (most
tickets would not go back to implementation, architecture or product
design in any predictable way), so there should be none. *Decision:*
**decided.** A gate with no throwback declines to a human-chosen
earlier position.

**B.6 `entry:` stays; nothing reads it yet.** *Decision:* **decided.**

**B.7 The ticket backbone and merge-after-reconcile stay; the
container backbone is order-only, plus `fills:`.** *Argument:* §1.1.b:
Phase 7 opens one PR per child ticket and merges them into the
feature branch; `reconcile` is where an agent joins the children's
output and where a human can look at the fanned-out results in
aggregate, with gates legal before and after it; `merge` is the
plane-balled join that follows; `checks` is CI against produced work.
The order is what PR mechanics require. *The container backbone:* the
author's question was whether `setup` should require `prep` and
`retro` require `cleanup`, given that an explicit population step for
the queues and an explicit work queue for the sub-flows feel
mandatory, and given the idea, not previously written down, of a
bundle for setup and retro, which would need a standard interface for
scheduling work. *What v5 §7.8 says:* `setup` "grooms, sets blockers,
and fills `prep`"; `retro` files into `cleanup` and the next
milestone's `prep`. So a population step needs the queue it fills,
but a queue does not need its population step, since humans can fill
it. *Decision:* **decided, amended** to this shape.

- `main` is always required: the work queue the sub-flows run in.
- Order among the members present is required; membership is not,
  except as `fills:` implies it.
- A status whose agent step emits tickets declares where they land:
  `- status: setup, fills: prep`; `- status: retro, fills: [cleanup,
  prep]`. The loader checks that every named queue exists in the
  array, which is the whole of "setup implies prep" and "retro implies
  cleanup" as one check rather than two special cases.
- A queue named by `fills:` that sits *earlier* than the filling
  position refers to the next instance of the type, which is how
  `retro` reaches the next milestone's `prep`. This is the case the
  prototype tests.
- **Placement is the status, not the tier** (decided, §5.a):
  "setup fills prep" is a relation between two positions in one
  array, and the workflow owns every relation of that shape
  (`blocks:`, `throwback:`, grouping); the tier already says where it
  runs through `phase:`; and a population tier on the status side
  stays reusable across workflows that route its output differently.
  This is the interface for a setup-and-retro bundle: the chain's tier
  emits tickets and names its `phase:`; the workflow's status names
  the queue.

**B.8 `pending` becomes an engine flag, not a status.** The earlier
change kept `pending` as a reserved-enforced rule and weakened
"immediately before" to "before". *The author's observation:* the
default missed `pending` before `reconcile` and `critique`, which both
need it, and it might be easier as an engine concern. *Argument for
the flag:* every agent-balled position needs a wait state, without
exception, which is exactly why two were found missing; a declaration
that must always be present in a fixed place is not a choice, so it
should not be syntax. The projection already auto-passes `pending`,
so the engine treats it as transient today. *What it removes:* the
`pending` kind, the opens-with-pending and pending-precedes rules, the
sub-array-head rule, and the special case `retro`'s group needed
(ORC-151, ORC-155). *What stays:* `backlog`, author-balled before the
ticket opens, which is a different thing. *Against:* it is an engine
change (projection and sequence), not only grammar. *Decision:*
**decided.** The board renders the flag as a substate of the position.

**B.9 Critique placement is order-only, derived from the chain.**
*Argument:* a review is 1:1 with the tier it reviews, so its position
follows the generation it reviews by construction (§1.1.c). *The
author's question:* some people may want `checks` before critique;
is that an order-only limitation or adjacency with `checks` as a
special case? *The reason for adjacency* is that a critique must read
the draft it reviews with nothing regenerating it in between, and only
a generation-shaped position regenerates. So the rule is: **a critique
position follows the generation position it reviews with no other
generation-shaped position between; `checks`, gates and environments
may sit between.** No special case. *Decision:* **decided.** Stated
once, in the chain contract, and cited from the workflow's.

### C. Cross-axis

**C.1 Free tier-status binding, strict.** Argued in §1.3. *Decision:*
**decided**, with three consequences the author accepted or that
follow from strictness.

1. `phase:` is required on every tier; a review's position derives
   per §1.1.c with an explicit override.
2. Strictness needs to know which type to check against. Today a
   chain flow pairs with a workflow type by *label convention* that
   the spec deliberately does not check (`dsl-syntax.md` §11, the
   passage on `flow:` and labels). So the chain flow names its type:
   `ticket: {type: feature}`. This is the same chain-names-workflow
   direction and amends §11 from "no cross-reference" to **"the chain
   references the workflow, checked at load; the workflow never
   references the chain."**
3. The traversability check, per flow and type: every tier in the
   flow names a position in the type; for every walk where B reads A,
   A's position precedes B's at the same depth; a fan-out's child
   tiers bind within the child's own filtered sequence; and a
   generation-shaped position no tier of the flow names is skipped
   with a warning (C.3), the same shape as a depth the chain never
   reaches, because the five plan flows share the `feature` type and
   will not name every position.

What is settled underneath it: the direction is tiers → statuses and
stays; the runtime atomizes the kind and never the name, so
`status: <kind>, name: <free>` is safe with no code change; and gate
enforcement against dispatch is Phase 7 work either way.

**C.2 The reconcile prompt lives on the fan-out tier; the reconcile
position stays in the workflow.** *Argument:* fan-outs need a
reconcile position because child PRs must merge into the parent
predictably, with gates possibly before and after; only the workflow
can place gates around a position. The prompt, though, is what an
agent does when the children are joined, and that is chain content
for the same reason a review prompt is (A.4). *Decision:* **decided**:
the fan-out tier carries a `reconcile:` block the way it carries
`review:`, and the workflow keeps the explicit `reconcile` position
the block runs at. The two are not mutually exclusive, and seam entry
21's third placement stays withdrawn.

**C.3 Cross-axis warnings.** *Argument:* §1.2 shows the assumptions
the strict check does not cover; a load-time warning when a
workflow's depths exceed the chain's fan-out, or a position no tier of
a flow names, costs nothing and turns silent degradation into a
visible one. `load_axes/5` has both bundles in hand. *Decision:*
**decided**: there is a contract whether or not it is named, and with
free binding a misspelling must be caught. A misspelled `phase:` is an
error under C.1; the warning covers the other direction.

### D. Docs and record

**D.1 Write the contract docs fresh; each rule once with an id, a
reason in the sibling, and a live/reserved marker.** *Decision:*
**decided.**

**D.2 State the interaction points of §1.1 in the chain contract,
once.** *Decision:* **decided**: the author does not want to re-derive
them.

**D.3 Amend the record in the same change** (v5 §6, §9, §3.4, §7.18,
§7.19; core_dsl and platform_content standing decisions named in
README §2.4; `non-goals.md` for the retired constructs). *Decision:*
**decided**: all the docs in one go, so they are consistent.

## 3. Rules, re-read with the decisions applied

The two passes in `evidence/seam-rules-*.md` classified each load rule
by whether a runtime module reads it *today*. The classes used here:

- **ENGINE** — a runtime module misbehaves without it now.
- **RESERVED-ENFORCED** — a Phase 7 (or named later) consumer the
  record identifies will depend on it; stays in the contract, marked.
- **DERIVED** — true by construction of the grammar in §2; the rule
  disappears with the construct that needed it.
- **DISCIPLINE** — loader hygiene (unknown keys, duplicates, typing);
  stays, stated once.
- **RETIRED** — the decision in §2 removes the construct or the rule.

**Chain (42 rows).** ENGINE 20, as the pass found. Of the 17 loader-
only rows: fragment vocabulary (2c, 2d), review-tier rules (9, 10,
11), reference-scope rules (65, 66, 68), the inline-form exclusivity,
and the `.synthesis` refusal are DERIVED under §2.A; `enforcement` and
`ticket.*` registration are RESERVED-ENFORCED markers; unknown keys,
duplicates and scope-target resolution are DISCIPLINE. `delivery.phase`
membership becomes ENGINE at load in its strict form (§2.C.1: the
position exists in the paired type) and RESERVED-ENFORCED at runtime
(Phase 7 dispatch gating); `agent_step` membership is RETIRED with the
key; the navigation-walk ban is a platform design rule with a recorded
reason (v5 §4.3) and stays, now stated on the edge declaration as
`context: none`.

**Workflow (44 rows).** ENGINE 6, as the pass found. The 18 the pass
called habits re-read as:

| Rows | Class | Why |
|---|---|---|
| 26 (ticket backbone), 27, 28 (merge after reconcile) | RESERVED-ENFORCED | §2.B.7: Phase 7 PR-per-child merge mechanics |
| 14, 15 (`pending` placement) | RETIRED | §2.B.8: `pending` is an engine flag |
| 20 (critique adjacency) | RESERVED-ENFORCED, order-only, derived | §2.B.9 |
| 26 (container backbone membership) | RESERVED-ENFORCED for order and `main`; membership via `fills:` | §2.B.7 |
| 23 (escalation shape), 31, 32 (opt-ins) | RESERVED-ENFORCED / BINDING | delivery Phase 7; bindings |
| 1, 19, 21, 30, 35 (unknown keys ×5), 18 (depth typing), 34 (dialect) | DISCIPLINE | stated once, not five times |
| 33 (naming discipline) | lint | style |
| 50 (`throwback` required when ungrouped) | RETIRED | §2.B.5 |
| `blocks:` resolution | ENGINE, loader form | §2.B.4; the runtime is corrected to it |

So the honest count on the workflow axis is: 6 engine-required now,
8 reserved-enforced by Phase 7 or a binding (rows 26, 27, 28, 20, the
container half of 26, 23, 31, 32), 7 discipline, 1 lint, 3 retired
(14, 15, 50), and the rest negatives or derivations. The *number of times*
these rules are stated (eight for `pending`, five for critique
adjacency) was the bloat; the rules themselves mostly have reasons.

## 4. The target key set

Reserved keys are marked with an asterisk; derived defaults are listed
under the key they default. Facts about one document live in the
XSD (identity, plain cardinality, fields); facts relating nodes live
here (§5.a's rule of thumb).

**`catapult.yaml`:** `chain`, `workflow`.

**`chain.yaml`:**

```
name, version*, kind: chain
defaults:                              # bundle-level, per-tier scalars only
  executor: {effort: max}              # reason on the block: the first steps sort, not write
tiers:
  <name>:
    scope            singleton | per(X) | child_of(X)      (absent on a supplied tier)
    phase            <position name in the paired type>    (required; the one cross-axis key)
    draft            {root_tag, grammar} defaults: <name>, schemas/<name>.xsd; absent = join target
    generator        llm (default) | supplied | external* | template* | git_commit* | webhook*
    source           input.<role> | write*                 (supplied only)
    prompt           default: prompts/<name>.md.liquid
    review           {prompt?, context?, phase?}  default prompt: prompts/review/<name>.md.liquid; phase derived
    reconcile        {prompt, phase?}             (fan-out tiers only; phase derived)
    executor         default: defaults.executor
    handle           [<field or kind>...]  default: all fields + produced kinds; subset-checked
    context          {<variable>: <walk>}   additive to the edge-derived reads
    produces         {<kind>: draft.<path>}
    enforcement*     [<profile>...]
edges:
  <name>:
    type             fanout | reference | dependency | policy_application | synthesis*
    context          <projection> | none        default read for every instance from self/parent
    consistency*     eventual | transactional
    instances:
      - {source, target, declared_in, source_ref, target_ref, when*?}
predicates*:         {<name>: <predicate>}                 (cardinality.when, completion)
flows*:
  <name>: {walk, entry, ticket: {type, labels}, prompt, targets, context}
```

**`workflow.yaml`:**

```
name, version*, kind: workflow
entry: <type>
types:
  <name>:
    skeleton         ticket | container | absent
    statuses:        [ <entry> | [ <entry>... ] ]
      <entry> :=  {status: <kind>, name?: <free>, flow?: <type>, blocks?: [<ref>...], fills?: [<ref>...], depth*?: n | [a, b]}
                | {review: <gate>}
                | {environment*: <env>}
gates:
  <name>: {role, depth: all (default) | n, throwback?: <ref>, escalation*}
environments*:
  <name>: {promote_from?, depth?, lifetime}
```

Kinds, which are shapes the engine branches on and no longer a name
table: `backlog`, `generation`, `critique`, `checks`, `reconcile`,
`merge`, `deploy`, `terminal`, `setup`, `prep`, `main`, `retro`,
`cleanup`. `pending` is an engine flag (§2.B.8). `design`,
`architecture` and `implementation` retire as kinds and return as the
default pair's `name:` values (§2.C.1).

Counted from the listing: 14 tier keys (`scope`, `phase`, `draft`,
`generator`, `source`, `prompt`, `review`, `reconcile`, `executor`,
`handle`, `context`, `produces`, `enforcement`, and `defaults` at the
bundle level), of which 7 default and 1 is reserved; 4 edge keys and 6
instance keys; and the reserved `predicates`/`flows` blocks. The
status entry gains `fills:`; the gate's `depth` default flips.

## 5. The last two, decided

- **a. `fills:` placement — on the status.** Decided. Argued under
  §2.B.7: "setup fills prep" is a relation between two positions in
  one array, and the workflow owns every relation of that shape; the
  alternative, on the tier, would have told the reader which two
  statuses relate to a tier in one place at the cost of a second
  cross-axis hookup and of binding the chain to one workflow's queue
  names.
- **b. The acceptance number (README §4.8).** Decided. Today the chain
  bundle is 2378 lines of YAML (1411 without comments) and the
  workflow 286 (104). The single chain file is at most **800 lines
  including comments, comments at most a fifth**; the workflow file at
  most **240 lines**; a reader who has not seen the engine reads both
  in **thirty minutes**. The chain figure is the 600 to 800 the author
  estimated at the outset, doubled from this pass's first proposal of
  400, which was derived from the surviving keys alone and left no
  room for the comments that carry a rule's reason. Separately, and
  not this number: a review's acceptance threshold, a key alongside
  the review prompt with a default of 90, which belongs in the
  `review:` block's grammar.

The rule of thumb the author confirmed for the XSD/DSL seam (seam
entry 19): **intra-node facts in the XSD, inter-node facts in the
DSL.** Identity, plain cardinality and fields are annotated on the
schema element; `produces`, `declared_in` and walks stay in the chain.
The schemas carry no `xs:appinfo` today, so this is a move of three
facts, not a reshuffle of existing annotations.

The other items the earlier version listed as open are decided above:
identity placement (this section's rule); free names (§1.3, §2.C.1);
the container backbone (§2.B.7); `blocks:` semantics (§2.B.4); a tier
family with several drivers (three same-shaped tiers, with the
invariant that a tier has exactly one minting parent, which ORC-247's
single-sourced `child_of` already implies and YAML anchors make cheap
in one file); `generator: template` (kept: a tier whose body is a
template rendered from its context walks, no agent run, validated
like any draft; its owner is the commit path); cross-axis warnings
(§2.C.3).
