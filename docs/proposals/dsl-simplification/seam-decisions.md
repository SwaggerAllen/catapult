# The seam pass — recommended changes, each with its argument

README §5 step 3. This replaces an earlier version of this file that
listed conclusions without arguing them and classified a load rule as
a habit whenever no *current* runtime module read it. That test was
wrong: the same proposal classifies a construct as reserved when its
consumer is coming, and rules deserve the same class. Critique
adjacency, reconcile-before-merge and the ticket backbone all have
Phase 7 consumers the record names, and the earlier version called
them habits. §3 re-reads every rule with the corrected classes.

## 0. How to read this

Every recommended change carries five parts: the change; the
argument for it; the argument against it and what it costs; the
evidence, cited; and its standing. Standing is one of:

- **settled by evidence** — the tree or the record decides it, and
  the counter-argument would need a fact that was not found;
- **arguable** — I recommend it, the argument is stated, and a
  reasonable reader could weigh the costs differently;
- **open** — the author's call; both sides are argued and no
  recommendation is made, or one is made with low confidence and
  says so.

Each change also says what would change the recommendation. Inputs:
`seam-pass.md`, `classification-matrix.md`, `questioned-rows.md`,
`in-flight-tickets.md`, the two rule passes in `evidence/`.

## 1. How the two bundles interact

The proposal so far treated the axes as near-orthogonal and analysed
each on its own. They are not orthogonal, and several changes below
depend on saying exactly how they meet. This section is the analysis
that was missing.

### 1.1 The interaction points that exist by construction

**a. A tier names the status it generates in.** `delivery.phase` is
the one declared cross-axis reference, and it runs one way: the
chain references workflow positions; the workflow never names a
tier. Today nothing reads it at runtime (matrix 1.2); its Phase 7
consumer is dispatch gated by the ticket's resting position, which
is what makes a human gate hold generation at all.

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
chain that fans out. The earlier version of this file missed that,
and §2.C and §3 correct it.

**c. Chain review tiers run at the workflow's `critique` position.**
Every review tier names `phase: critique`; the critique entry in a
type's array is where they run once dispatch is gated. So critique's
place relative to the generation it reviews is structural, given by
the chain graph (a review tier is 1:1 with the tier it reviews), and
the workflow's adjacency rule is the workflow-side statement of that
structure. The earlier version called it a habit; it is a
reserved-enforced rule with a chain-side derivation.

**d. The default assumes architecture fans out and product does
not.** In the chain graph the product tiers *do* fan out
(`journeys → journey`, `screens → screen`, `requirements → resp`,
`feature_expansion → vocab`), but into join targets with no
generated content of their own, so no child ticket has anything to
generate. Architecture fans out into tiers that generate
(`comp → comparch → subcomp → subcomparch → impl`). For the workflow,
"fans out" therefore means "mints children that carry generation
tiers", which is a property of the chain the workflow cannot see and
does not declare. `default-flow`'s `feature.yaml` encodes the
assumption in its depths: critique `[2, 0]`, gates at `0`.

**e. Under fixed kinds, one `generation` position spans the whole
chain.** Every `llm` tier in the default names `phase: generation`
(ORC-179 deferred choosing further). So the product draft at depth 0
and each component's architecture at depth 1 are the *same
position*, distinguished only by depth. A gate "after product
generation" and a gate "after architecture generation" are
inexpressible with one position, which is exactly why v5 §7.18 added
`design`/`architecture`/`implementation` to the fixed table and why
the granularity question (§2.C.1) exists. Depth distinguishes
levels; it cannot distinguish positions at one level.

### 1.2 What each side assumes of the other, and what checks it

| Assumption | Held by | Checked? | On violation |
|---|---|---|---|
| Every phase a tier names is a position the paired workflow declares | chain | no (only membership in the fixed table) | today: nothing, since nothing reads phase; Phase 7: a tier at an undeclared position never dispatches, or dispatches at its kind |
| The chain fans out at the depths the workflow's gates and critique name | workflow | no, by decision (v5 §7.19 "must not be a load error") | depth is a maximum; a shallower chain applies the levels that exist, silently |
| A position that fans out has children to reconcile | workflow | no | v5 4231: the mechanical merge and the reconcile read happen regardless; with no children it is a no-op fan-in |
| A generation position has one agent step to group gates around | workflow (sub-arrays) | at load, within the workflow only | n/a |
| Children run the declared sequence filtered by depth, so generation-shaped entries apply at every level | both | implied by v5 §7.19 | a workflow with all gates at depth 0 handles a fanned chain: children generate, check, reconcile and merge with no human gates |

The last row answers the author's question about serial versus
fanned tiers at every level: the depth mechanism *does* let one
workflow accept both, because fan-out changes only which levels the
gates apply at, not whether the sequence runs. What it does not let
a workflow do is gate two different generation passes at the same
level differently, which is 1.1.e again. So the incompatibility is
not fan-out versus serial; it is that positions, not levels, are
what a gate needs to name, and fixed kinds give the workflow too few
of them. A chain that fans out at *product* (a decomposition whose
journeys each generate) would still run under `default-flow`; its
per-journey children would just have no gates until someone added
depth to the product gates, which the fixed table lets them do.

### 1.3 Compatibility versus autonomy

This is the decision under §2.C.1 (free status names) and it is open.
Both sides:

*For compatibility (fixed kinds).* Bundles exist for community-scale
sharing (v5 §8's premise; the author's framing). A workflow shared
across chains must gate on positions every chain has, and the fixed
kinds are that shared vocabulary. Free names let a workflow become
specific to one chain's position names; a shared workflow that used
them would silently degrade on any other chain. The fixed table is
small and platform-owned, which is also what makes tooling (the
board, lane keys, the status columns) uniform across projects.

*For autonomy (free names).* The fixed table forces batching that the
author considers a bug, and every new position anyone wants is a
platform vocabulary change, which is the growth-in-content-tickets
pattern. Siege allowed review after every tier. The depth rule
already established that a workflow may name something a chain does
not have and degrade silently; names are the same trade at the
position axis that depth is at the level axis.

*The middle, which is what I recommend, with the reason.* Kinds stay
the shared vocabulary and are what a portable workflow uses; a fine
name is an opt-in that degrades to its kind on any chain that does
not declare it. A workflow using only kinds is portable exactly as
today; one using fine names is chain-specific *by the author's
choice*, which is the same choice depth already gives them. Sharing
is not harmed because a shared workflow either uses kinds (portable)
or is shared as a pair with its chain (where fine names are fine).
What would change this: evidence that community sharing is
predominantly workflow-alone rather than pair or chain-alone, in
which case the fixed table should stay closed and grow by platform
decision, and the author should decide the batching is acceptable.

## 2. Recommended changes

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
700-line YAML file is its own readability problem. *Evidence:* D
parts 1 and 4; F part 2. *Standing:* arguable. The prototype is the
test: if the single file does not read well, keep per-tier files and
take only the defaults below.

**A.2 Defaults for `root_tag`, `grammar`, `prompt`, `generator: llm`,
`executor`, derived from the tier name.** *Argument:* 17 of 22
root tags, 19 of 22 grammars and nearly every prompt path already
equal the derivation; `executor` is `max` in all 10 uses; `llm` is
already the default. A default the author writes to override costs
nothing where the value differs and removes a line everywhere else.
*Against:* implicit paths are harder to grep for. *Evidence:* D part
2. *Standing:* settled by evidence.

**A.3 `handle.fields` defaults to every field; `handle.fragments` is
derived from what is produced onto the node.** *Argument:* checked
against the tree, **no shipped tier narrows its handle**: every one
of the nine spine tiers and all ten join targets expose `[id] +
every field`. The 34 blocks carry no information. v4's purpose for
`handle` (A.1.6, the public surface) survives as an override for a
tier that wants to narrow, and a subset check should be added since
today none exists. *Against:* information hiding between tiers is a
real design tool and a default of "everything" nudges authors away
from it. *Evidence:* the tree, read directly. *Standing:* settled by
evidence for the default; the nudge concern is real but costs one
line to act on.

**A.4 Review as a tier property (`review:`), not a review tier.**
*Argument:* all 17 review tiers are seven keys of which four are
constants and one is a byte-identical copy of the base tier's walks;
the load rule that the copy is exact exists only because the copy
exists; and `ContextAssembly` already ignores the review tier's
context and recomputes from the reviewed tier (seam rules, chain
#10). The rule's reason (core_dsl#9) dissolves when equality holds by
construction. *Against:* a review tier could one day want a
different context than its base. *Evidence:* D part 3; E; the
equality rule itself forbids the counter-case. *Standing:* settled by
evidence; the counter-case is forbidden by the current contract.

**A.5 `context:` as a map from variable name to walk.** *Argument:*
ORC-247 found the merge-by-tier rule silently fusing distinct reads
at eighteen sites, unseen for the bundle's whole life, and the fix on
that branch adds an `as:` key, a merge-by-name rule, two collision
errors, and a still-open form question. Mandatory naming removes the
merge rule, reduces collisions to key uniqueness plus a short reserved
list, and makes every prompt variable visible in the declaration.
*Against:* the common single-walk entry now needs a name, which is a
line of ceremony for the 109 `self.*` reads; a default name (the
target tier) would recover the ceremony but reintroduce the merge
rule. *Evidence:* `in-flight-tickets.md` ORC-247 review 5; seam 7.
*Standing:* arguable. I weight the eighteen-site defect over the
ceremony; the prototype shows whether the ceremony is tolerable.

**A.6 `produces:` as a map `kind: draft.<path>`; owner implied;
`fragments:` vocabulary derived.** *Argument:* every one of the 24
shipped rows and every v4 example is `owner: self.parent`; `owner:
self` never existed in v4 and the engine discards it; the bundle-
level vocabulary is the union of produced kinds and nothing else.
*Against:* none found. *Evidence:* `questioned-rows.md`; D part 2; E.
*Standing:* settled by evidence.

**A.7 Plain cardinality moves to the XSD; `cardinality.when` stays,
reserved.** *Argument:* all 62 shipped `min`/`max` rows are either
`minOccurs` facts about the declaring element or tautologies of the
edge type ("every comp has exactly one mint"), and nothing enforces
them at runtime. v4's real use was `when`-conditioned bounds
("foundation at every level"), a cross-node invariant the XSD cannot
express, enforced by rejecting the commit; that mechanism stays,
reserved, with the predicate language for it. *Against:* keeping
cardinality in the DSL keeps all structural facts in one place; the
XSD is a second place to look. *Evidence:* `questioned-rows.md`
(v4 A.2.3, A.2.8, bundle §4.1); D part 2. *Standing:* arguable on
placement; settled that the plain rows carry no DSL-level
information.

**A.8 The instance is the unit; drop the inline edge form.**
*Argument:* 58 of 62 declarations are instances; the inline form and
its exclusivity check exist for four files. *Against:* the inline
form is shorter for a single-instance edge. *Evidence:* D part 2.
*Standing:* settled by evidence.

**A.9 Endpoint locators default by convention (`self`, `self.parent`,
a row's `from`/`to`/`ref` attribute); explicit only when the
convention cannot express the endpoint.** *Argument:* all six uses
are `@from`/`@to` in one file and ORC-247's `@ref` follows the same
pattern; the closed form was derived by tracing the default's
instances and closed to exactly what they need (core_dsl#37).
*Against:* an explicit locator is self-documenting and the
convention is one more rule to know. *Evidence:* D; F part 4.
*Standing:* arguable; low stakes either way.

**A.10 Retire `scope_filter`, edge `constraint`, `per_source`.**
*Argument:* each served a v4 mechanism v5 removed by recorded
decision (the domain/presentational split, the cascade visit set,
phases), none is used, and `scope_filter` is the only evaluated
predicate slot. *Against:* a future bundle may want a conditional
scope. *Evidence:* `questioned-rows.md`. *Standing:* settled by
evidence; re-admission is one slot if a need appears.

**A.11 Rename the join-target generator; merge `reference` into
`supplied`; retire `scope: reference`.** *Argument:* v5 §5.1 reused
v4's `synthesis` (a computed aggregation body) for a node with no
body, so the word now means two things; a tier with no draft is a
join target by v4 A.1.1 and needs no keyword. `reference` and
`supplied` are both "externally sourced, never generated, never
drained", and `scope: reference` restates `generator: reference`
(the pairing rule exists because the fact is written twice, A part
4). *Against:* renaming touches ten tiers and the record; `reference`
nodes have a write path still to build and may want their own kind.
*Evidence:* `questioned-rows.md`; seam 2, 3. *Standing:* arguable on
the merge; settled on the rename.

**A.12 `delivery.phase` and `agent_step` default from the tier's
role.** *Argument:* both are fully determined by generator and
`reviews` in every shipped tier; the key stays because it is the
cross-axis binding (§1.1.a) and the only way to name a finer position
under §2.C.1. *Against:* none. *Evidence:* D part 2. *Standing:*
settled.

### B. Workflow grammar

**B.1 Keep sub-arrays; keep `name:`; keep gate `depth`.** *Argument:*
the author's, recorded in `questioned-rows.md`: sub-arrays give the
default throwback, bound how far a child may lead its parent, scope
reconcile and merge, and are the board's grouping, with consecutiveness
free; `name:` is the only way to distinguish two entries of one kind
once several roles share review duty, and §2.C.1 reuses it; gate depth
is wanted (scaffolding reviews the whole tree, a feature the top
levels). *Against:* none that survives the author's reasons.
*Standing:* settled by the author.

**B.2 Delete the sentence "Depth 0 is the rule for a gate."**
*Argument:* `dsl-syntax.md` 2349 attributes it to v5 §7.19, which
says the opposite ("`1` adds components; `2` adds subcomponents");
it contradicts the author's intent and is why every shipped gate
carries `depth: 0`. *Evidence:* both passages quoted in
`questioned-rows.md`. *Standing:* settled by evidence.

**B.3 Gate `throwback` defaults to the enclosing sub-array's head.**
*Argument:* that is the current derivation; the command edge
re-derives legality anyway (seam rules, workflow #24), so the
declaration is only a one-click default. If the derived default is
never what authors want, the author's own rule applies: fix the
default. *Standing:* settled (it is the tree).

**B.4 Reconcile the `blocks:` semantics between loader and runtime.**
*Argument:* the loader resolves `blocks:` targets by namespace and
refuses a recurring kind; `ContainerQueues.held_or_resolved/3` matches
by bare kind and holds on every occurrence. One of them is wrong.
*Standing:* settled that they disagree; which to keep is the
author's, and it is a small ticket either way.

**B.5 Either implement or drop the "ungrouped review must declare
`throwback:`" rule.** *Argument:* it is in the contract and not in the
loader; the runtime tolerates a nil default (a gate with no one-click
target). *Standing:* settled that the contract and loader disagree.

**B.6 `entry:` stays; note that nothing reads it yet.** *Argument:* it
is the only way to name the root type; its consumer is provisioning.
*Standing:* settled.

**B.7 The ticket backbone and merge-after-reconcile stay, as
reserved-enforced rules.** This reverses the earlier version of this
file. *Argument:* §1.1.b: Phase 7 opens one PR per child ticket and
merges them into the feature branch; `reconcile` is where an agent
joins the children's output and where a human can look at the fanned-
out results in aggregate, with gates legal before and after it;
`merge` is the plane-balled join into the parent that follows; `checks`
is CI against produced work. The order is what PR mechanics require,
not the default's taste. That no current dispatcher reads `reconcile`
(seam rules, workflow #28) means the rule is reserved, not that it is
a habit. *Against:* the container backbone's five-member requirement
(`setup`, `prep`, `main`, `retro`, `cleanup`) is weaker: `Composition`
takes the first queue-shaped entry and the dispatcher closes at
end-of-array, and v5 §7.8 describes the milestone model rather than
requiring every member. *Evidence:* v5 §7.5, §7.19, 4231; core_dsl#21,
#22. *Standing:* settled for the ticket backbone; arguable whether the
container backbone should require all five members or only their
relative order when present.

**B.8 `pending` before each generation-shaped entry stays, as a
reserved-enforced rule; "immediately before" can weaken to
"before".** *Argument:* `pending` is the dispatch-wait position; once
dispatch is gated by the ticket's resting position, a ticket must
have a position to rest at while no agent has picked it up, and that
position precedes the generation it waits for. *Against:* nothing
today dispatches on it; the projection auto-passes it. *Evidence:*
seam rules, workflow #14. *Standing:* arguable on the adjacency,
settled on the existence.

**B.9 Critique adjacency stays; state it as derived from the chain.**
*Argument:* §1.1.c. A review tier is 1:1 with the tier it reviews, so
the critique position follows the generation it reviews by
construction; the workflow rule restates chain structure. It should
be stated once, in the chain contract, as "a review runs at the
`critique` position following its tier's generation position", and
the workflow's adjacency rule cited to it rather than restated.
*Standing:* settled that it is structural; arguable where it is
stated.

### C. Cross-axis

**C.1 Free status names, degrading to kinds by the depth rule.**
Argued in §1.3. *Standing:* **open**; my recommendation is the
middle, with low-to-medium confidence, and the thing that would change
it is named there. What is settled underneath it: the direction is
already tiers → statuses and stays; the runtime atomizes the kind and
never the name, so the `status: <kind>, name: <free>` spelling is safe
with no code change; and gate enforcement against dispatch is Phase 7
work either way, so freeing names changes what the board shows and
nothing about what runs until that lands.

**C.2 Reconciliation stays a workflow position; the chain may attach
a fan-in document to it.** This narrows seam entry 21 and withdraws
its third placement. *Argument:* the author's: fan-outs need a
reconcile because child PRs must merge into the parent predictably,
with gates possibly before and after; that is a *position* in the
ticket's sequence, which only the workflow can place gates around.
The chain's contribution is already what v5 4231 allows: an optional
synthesis tier at the reconcile position, authored so a human reading
the post-join gate sees a document rather than a composed diff.
Folding reconcile into the fan-out declaration would move the position
into the chain and lose the workflow's ability to gate before and
after it, which is the point. *Against:* the skeleton's generation →
reconcile → merge relation is still derivable from the chain's fan-out
edges, so the workflow restates chain structure; but restating a
required position is cheaper than a cross-axis derivation. *Standing:*
arguable, leaning to keep. What remains open is the container
skeleton (B.7).

**C.3 A declared chain-shape check, as lint.** *Argument:* §1.2 shows
every cross-axis assumption is unchecked by decision. A load-time
*warning* (never an error, per v5 §7.19's reason) when a workflow's
depths exceed the chain's fan-out, or a tier's fine phase matches no
position, costs nothing and turns silent degradation into a visible
one. `load_axes/5` has both bundles in hand. *Against:* §14 forbids
cross-axis reference, and a warning is a compatibility contract in all
but name. *Standing:* arguable; the reason §14 gives is about
*errors*, and a warning does not fork workflows per stack.

### D. Docs and record

**D.1 Write the contract docs fresh; each rule once with an id, a
reason in the sibling, and a live/reserved marker.** *Argument:*
README §3, §4.6, §4.7; the duplication structure is the bloat
generator and the six-round sibling failure is its symptom.
*Standing:* settled by evidence (reports A, B, G).

**D.2 State the interaction points of §1.1 in the chain contract,
once, as the section where the workflow is mentioned at all.**
*Argument:* nothing in the record states them together; each is
recoverable only by reading v5 §7.5, §7.18, §7.19 and core_dsl#22
side by side. *Standing:* settled.

**D.3 Amend the record in the same change** (v5 §6, §9, §3.4, §7.18,
§7.19; core_dsl and platform_content standing decisions named in
README §2.4; `non-goals.md` for the retired constructs). *Standing:*
settled by the repo's own rule.

## 3. Rules, re-read with the corrected classes

The two passes in `evidence/seam-rules-*.md` classified each load rule
by whether a runtime module reads it *today*. That is the right input
and the wrong last step. The classes used here:

- **ENGINE** — a runtime module misbehaves without it now.
- **RESERVED-ENFORCED** — a Phase 7 (or named later) consumer the
  record identifies will depend on it; stays in the contract, marked.
- **DERIVED** — true by construction of the grammar in §2; the rule
  disappears with the construct that needed it.
- **DISCIPLINE** — loader hygiene (unknown keys, duplicates, typing);
  stays, stated once.
- **HABIT** — no consumer now or named; a convention; leaves the
  contract, may live as lint or in the default's own comments.

**Chain (42 rows).** ENGINE 20, as the pass found. Of the 17 loader-
only rows: fragment vocabulary (2c, 2d), review-tier rules (9, 10,
11), reference-scope rules (65, 66, 68), the inline-form exclusivity,
and the `.synthesis` refusal become DERIVED under §2.A; `enforcement`
and `ticket.*` registration are RESERVED-ENFORCED markers; unknown
keys, duplicates and scope-target resolution are DISCIPLINE. Of the 2
habits: `delivery.phase` membership splits into RESERVED-ENFORCED
("a phase names a position", Phase 7 dispatch gating) and OPEN ("the
position is in the fixed table", §2.C.1); the navigation-walk ban is a
platform design rule with a recorded reason (v5 §4.3) and stays as a
stated rule, not a habit.

**Workflow (44 rows).** ENGINE 6, as the pass found, three in a weaker
form (§2.B). The 18 the pass called habits re-read as:

| Rows | Class | Why |
|---|---|---|
| 26 (ticket backbone), 27, 28 (merge after reconcile) | RESERVED-ENFORCED | §2.B.7: Phase 7 PR-per-child merge mechanics |
| 14, 15 (`pending` placement) | RESERVED-ENFORCED, weaker form | §2.B.8: a dispatch-wait position must exist; adjacency is arguable |
| 20 (critique adjacency) | RESERVED-ENFORCED, derivable | §2.B.9: chain structure restated |
| 26 (container backbone membership) | arguable: RESERVED-ENFORCED for order, HABIT for requiring all five | §2.B.7 against |
| 23 (escalation shape), 31, 32 (opt-ins) | RESERVED-ENFORCED / BINDING | delivery Phase 7; bindings |
| 1, 19, 21, 30, 35 (unknown keys ×5), 18 (depth typing), 34 (dialect) | DISCIPLINE | stated once, not five times |
| 33 (naming discipline) | HABIT → lint | style |
| 50 (`throwback` required when ungrouped) | unimplemented | §2.B.5 |

So the honest count on the workflow axis is not "6 of 44 matter" but:
6 engine-required now, roughly 10 reserved-enforced by Phase 7, 7
discipline, 1 lint, 1 unimplemented, and the rest negatives or
derivations. What the earlier version got right is narrower than it
claimed: the *number of times* these rules are stated (eight for
`pending`, five for critique adjacency) is the bloat; the rules
themselves mostly have reasons.

## 4. The target key set

Unchanged from the earlier version in shape, now marked as provisional
on §2.C.1 (free names) and §2.C.2 (reconcile stays). Reserved keys are
marked with an asterisk; derived defaults are listed under the key
they default.

**`catapult.yaml`:** `chain`, `workflow`.

**`chain.yaml`:**

```
name, version*, kind: chain
tiers:
  <name>:
    scope            singleton | per(X) | child_of(X)      (absent on a supplied tier)
    identity         id | alias | name | slug               (required; §5.a may move it)
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
    delivery         {phase, agent_step}  defaults from the tier's role; phase may be a fine name (§2.C.1, open)
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
    skeleton         ticket | container | absent
    statuses:        [ <entry> | [ <entry>... ] ]
      <entry> :=  {status: <kind>, name?: <free>, flow?: <type>, blocks?: [...], depth*?: n | [a, b]}
                | {review: <gate>}
                | {environment*: <env>}
gates:
  <name>: {role, depth, throwback?, escalation*}
environments*:
  <name>: {promote_from?, depth?, lifetime}
```

Kinds: `pending`, `generation`, `critique`, `checks`, `reconcile`,
`merge`, `deploy`, `terminal`, `setup`, `prep`, `main`, `retro`,
`cleanup`. The three named generation kinds retire only if §2.C.1 is
taken; otherwise they stay and ORC-179 assigns them.

Counted from the listing: 14 tier keys (7 defaulted, 1 reserved), 4
edge keys and 6 instance keys (2 defaulted, 2 reserved), and the
reserved `predicates`/`flows` blocks. Down from the ~60 the current
§1–§12 define, with no construct the engine reads removed and no
reserved construct dropped.

## 5. Still the author's

- **a. Where identity is declared** (tier key or `xs:appinfo` on the
  mint element; seam 19). The prototype writes both.
- **b. Free status names** (§1.3, §2.C.1). Open; the recommendation
  is the middle, with the condition that would change it stated.
- **c. The container backbone**: require all five members, or only
  their order when present (§2.B.7).
- **d. `blocks:` semantics**: the loader's or the runtime's
  (§2.B.4).
- **e. A tier family with several drivers** (seam 2, ORC-247): three
  same-shaped tiers, or one declaration with per-instance readiness in
  the engine.
- **f. `generator: template`**: an owner, or the door-open note.
- **g. Whether a cross-axis *warning* is acceptable** (§2.C.3).
- **h. The acceptance number** (README §4.8).
