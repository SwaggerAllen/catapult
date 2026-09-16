# DSL simplification — evaluation of the proposed methodology

A proposal, not part of the record. Nothing in `docs/`, `systems/`, or
`bundles/` is changed by this directory; it argues for changes and
sequences them. Its `dsl-syntax.md` citations are the retired spec
being analysed rather than a live reference, and
`docs/dsl/retired-spec-index.md` maps its sections onto the rules that
replaced them. The measurements it rests on are in `evidence/`
(seven reports, each scoped to one source so that no single pass had
to hold the whole spec in view). Numbers in this memo come from those
reports and are approximate where the reports say so. `seam-pass.md`
is the first draft of the seam step and `seam-decisions.md` its
execution (every construct assigned a level, every load rule
classified by its runtime consumer, the target key set);
`classification-matrix.md` and `questioned-rows.md` are step 2;
`in-flight-tickets.md` folds in the two DSL tickets that were in
design when this was written (ORC-246, ORC-247) and says where each
of their decisions lands.

## 1. Verdict in brief

The complaints are right, and the measurements say why:

- **The spec is a design log with a grammar embedded in it.** Of
  `docs/dsl-syntax.md`'s 3750 lines, roughly 570 state grammar. The
  rest is, in descending order, rationale and round-correction
  narrative (~1200), narration of engine mechanism (~770), a
  validation checklist that is 60% argument (§13, ~500), and worked
  examples that no longer match the shipped bundle (~380).
- **About a third of the grammar has no reader yet, and the doc does
  not say which third.** The loader parses and validates, in detail,
  constructs that no engine module reads and that the default bundle
  does not use: the whole flow apparatus, three of four predicate
  slots (and the fourth is never used), the extension registry, five
  of eight generator types, and the `executor`/`enforcement`/
  `delivery` annotations. Most of these are intended and will be
  built soon; flows are MVP, because without them nothing modifies
  code after scaffolding. The defect is not that they exist. It is
  that the doc describes them in the same voice as the live core, so
  a reader cannot tell contract from intent, and defects hide in the
  gap (ORC-236: "declared and none wired"; ORC-235; ORC-232).
- **The default bundle is ten times larger than its information
  content.** Its 2692 YAML lines are 53% comment (the workflow bundle
  is 77% comment); the 17 review tiers are byte-identical copies of
  their base tiers' walks; a third of the remaining keys take one
  value across every file. What varies, and therefore carries the
  design, is on the order of a few hundred lines. That is the
  adjacency-list-sized artifact originally imagined, and it is
  already in there.
- **The pipeline is a bad instrument for this specific job**, and
  the record already knows it: at least eleven design-review rounds
  on the status-sequence grammar alone, each fixing the previous
  round's residue; every growth event in the "frozen" core landed
  inside a content ticket; a rule stated at five sites had one site
  corrected per round for six rounds. Grammar design needs the whole
  grammar in view, which a per-ticket agent with a partial file map
  cannot have.

The six-step plan is sound in its parts and wrong in its order and
in one premise. Recommended changes, argued below:

1. **Classify against the code, not the doc** (step 2). The
   protocol/implementation cut is the wrong first cut. Classify each
   construct three ways: **live** (read by the engine), **reserved**
   (intended, not yet read; stays in the grammar, marked as such,
   with its intent stated so tickets can be cut against it and
   implementers can hedge), or **questioned** (no reader and no
   recorded intent). Only the last is a candidate for removal.
2. **Add a seam pass** (new step). Before deciding the target
   grammar, ask of every flexibility the DSL offers: what it enables,
   what it costs, what constraint it puts on authors, whether that
   constraint belongs at this level, and whether it is the engine's
   requirement or the default bundle's habit. A first pass is in
   `seam-pass.md`.
3. **Decide before you split** (steps 3–5). The target grammar comes
   before writing documents about it; otherwise the split produces
   five bloated documents and a second rewrite.
4. **Rewrite, do not split** (step 4). The grammar is ~570 lines; a
   fresh write from the inventory is smaller than the edit, and the
   existing text's duplication structure is the bloat generator.
5. **Add the bundle to the plan.** The methodology has six steps
   about the DSL and its docs and none about the default bundle,
   which is the artifact the size complaint is really about.
6. **Prototype the single-file chain by hand before any doc work.**
   It is the one experiment that answers the feasibility question
   ("is the DSL worth having, and can a small one express the
   default?") and it costs an afternoon.
7. **Do the grammar redesign out of band; use the pipeline for the
   mechanical work that follows.**

## 2. What the measurements say

### 2.1 The spec

| Region | Lines | Grammar | Author rules | Mechanism | Rationale / history | Examples |
|---|---|---|---|---|---|---|
| §1–§12, §14 (chain) | 937 | ~284 | ~171 | ~171 | ~256 | ~55 |
| §13 (load-time checks) | 508 | ~40 | ~200 | ~120 | ~130 | ~18 |
| §15 (workflow) | 2290 | ~245 | ~405 | ~480 | ~840 | ~313 |
| **Total** | **3735** | **~570 (15%)** | **~775** | **~770** | **~1225 (33%)** | **~385** |

Source: reports A, B, C. "Author rules" are load-time rules an author
must satisfy; "mechanism" is narration of what the loader or engine
does. Distinctive findings:

- §5 is missing from the numbering and its body (fragments) survives
  as an orphan paragraph at the end of §4.1, so `produces:` and
  fragment kinds have no owning section (A).
- §15.8 and §15.9 contain no grammar at all; §15.9 is titled
  "…continued" (B).
- 21 rules are stated two or more times within §15 alone; the
  "`pending` heads every generation-shaped sub-array" rule is stated
  eight times (B). §13 restates a further dozen of its own rows (C).
- The §15.2 `feature.yaml` and §15.11 `component.yaml` worked examples
  do not match the shipped `bundles/default-flow/types/feature.yaml`;
  three of the four gate files they cite do not exist (B).
- The doc's vocabulary count is inflated by things that are not the
  DSL: prompt template variables, review grammar XML elements,
  extension kinds, loader inputs. The chain axis proper is about 60
  keys; the workflow axis about 21 keys plus 20 status kinds (A, B).

### 2.2 The bundles

| Directory | Lines | Comment | Content | Content % |
|---|---|---|---|---|
| default/tiers (51 files) | 1619 | 676 | 943 | 58% |
| default/edges (10) | 673 | 267 | 369 | 55% |
| default/flows + predicates | 99 | 49 | 50 | 51% |
| default-flow (13) | 286 | 221 | 65 | 23% |
| **All YAML** | **2692** | **1221** | **1434** | **53%** |

Source: report D. Of the 1434 content lines, the information that
varies between files and therefore carries the design is roughly:

| Carrier | Count |
|---|---|
| Distinct context-walk strings | 36 |
| Edge declarations (after collapsing `plan_target`'s 21-row product and 9 identical `-> ref` rows) | ~40 |
| `draft.*` field sources / `mint.*` field sources | 33 / 39 |
| `produces:` rows | 24 (six files, every `owner: self.parent`) |
| Workflow statuses (all four types) | ~65 lines |
| Named predicates | 5, one form |

Everything else is constant across a cluster or derivable from the
tier name: `identity: id` in all 34 that carry it; `executor: {effort:
max}` in all 10; `delivery:` a pure function of `generator` +
`reviews` in this bundle (it is the cross-axis binding point and
stays as a key with a default; `seam-pass.md` entry 13); `grammar:
schemas/review.xsd` in all 17 review tiers;
prompt/grammar/root_tag paths matching the tier name in most files;
all 17 review tiers' `context:` blocks byte-identical to their base
tier's (65 duplicated lines, plus a 7–10 line header saying the same
thing 17 times). The 21-instance `plan_target` edge is a 5-row table
written out as 126 lines.

Unused anywhere in either bundle: `scope_filter`, edge `constraint`,
`cardinality.when`, `per_source`, `lifetime: per_ticket`, nonzero
gate depth, `name:` on a status, `<anchor>.<name>` references, the
`design`/`architecture`/`implementation` kinds, `backlog`/`blocked`/
`stubbed`/`validating`.

### 2.3 What the engine reads today

Source: report E. The loader has ~126 distinct problem templates
across 6000 lines. Set against what any module outside `lib/catapult/
dsl/` reads. This is a snapshot of the tree, not a verdict on what
belongs in the grammar: the second list is mostly intended
functionality that will be built (§4.3), and the point of separating
it is so the contract doc can mark it, not so it can be removed.

**Read at runtime (live: a load rule has a matching runtime
consumer):** tier `scope`, `identity`, `fields`
(`draft.*`, `mint.*`, `mint.parent.*`), `handle`, `draft`, `generator`
in `{llm, supplied, reference}`, `prompt`, `context` (including `~`,
multi-hop, `all.<tier>`, both projections), `produces` with `owner:
self.parent`, `reviews`; edge `type` (fanout, reference, dependency,
policy_application), `instances[]` with `source_ref`/`target_ref`;
workflow `types[].statuses` as an ordered grouped sequence, `status`/
`review`/`name`, `flow:`, `blocks:`, `skeleton`, gate `role`
(display) and `throwback`, the fixed status table.

**Parsed, validated, and read by nothing:** the entire `flows/`
declaration (`delta`, `walk`, `ticket`, `completion`) and with it the
`cascade_visit` scope (candidates always `[]`) and the `synthesis`
edge type; three of four predicate slots (only `scope_filter` is
evaluated, and the bundle never uses it, so the 317-line predicate
parser serves nothing); `executor`, `enforcement`, `delivery`; five
generator types with no executor (`git_commit`, `external`,
`template`, `webhook`, `synthesis` as a generator); edge
`consistency`, `navigation` (load-only), `constraint`; gate `depth`
and `escalation`; environment `promote_from`, `lifetime`, `depth`
(an `environment:` entry is dropped by both lifecycle sequences);
status `depth`; workflow `entry:`; the extension registry, dialects
and behaviour (zero registrations, so `enforcement:` and `ticket.*`
walks cannot be authored at all); `reference.*` field sources (no
write path); `produces` with `owner: self` (validated, then dropped
at runtime); `GraphConstraints.violations/2` (no caller outside
tests).

That last list is invisible from inside the doc, because the doc
describes each of these in the same voice as the first list. Two
things follow. The contract doc needs a status marker per construct
(live / reserved) so a reader knows which rules the engine enforces
today and which describe an intended consumer. And a reserved
construct's grammar is provisional by nature: it was designed ahead
of the module that will read it, and ORC-232/235/236 show that such
grammar tends to be wrong in ways only the consumer reveals. So the
simplification available on this list is in *shape* (a 21-row edge
that is a 5-row table; five planning tiers of one template), not in
existence, and its exact grammar should be re-settled by the ticket
that builds its consumer, with the doc saying so.

### 2.4 What the record decided

Source: report F. The DSL's purpose is stated in one sentence, inside
a parked item (v5 §8): "Customization is why the DSL exists rather
than hard-coded chain logic." The community/independent-iteration
rationale in the task brief is not in the record. Neither "a single
adjacency-list file" nor "the chain graph in code" is discussed
anywhere; the chain-as-YAML decision is v4's, carried across the
inversion by silence. The record never names a protocol/
implementation split; three doctrines imply it (v5 §7.10 "declare the
shape, implement the semantics"; v5 §9 vocabulary-is-extension/
instances-are-content; core_dsl #4 "a bundle that loads is a bundle
the engine can run"), and `systems/core_dsl.md`'s standing decisions
mix grammar rules with loader internals in the same bullets. Note
that "protocol" in this repo already means the delivery automation
protocol; the new split needs a different word (below).

Decisions a simplification argues with, and whether their reason
survives the simplification:

| Decision | Recorded at | Reason given | Survives? |
|---|---|---|---|
| Frozen core, growth by extension | v5 §9, core_dsl #2 | no dialect forks | Intended and reserved, but the rule as stated has been bypassed by every growth event. Narrow it to what an extension can actually hold (generator types, context sources, annotation namespaces) and state that scope kinds and walk grammar grow by reviewed core edits, which is what happens. |
| Review is a tier (`reviews:`) | core_dsl #9, platform_content #25 | context must be load-checked equal | If the review is derived from the tier, equality holds by construction and the check is unnecessary. Reason dissolves. |
| Named predicates, four slots | core_dsl #12, v5 §3.4 | avoid double parsing | Reserved: `completion` is needed by flows; the other three slots have no consumer planned that the record names. Keep the language, mark each slot's status, and let the flow work re-settle `completion`'s form. |
| Closed generator set | v5 §6, §9 | closed vocabularies | Survives; the set shrinks to what has an executor. |
| One `types/<name>.yaml` with inline `statuses:` | core_dsl #14 | position where it is read, no `after:` | Survives and is the precedent for doing the same on the chain axis. |
| Fork, never layer | v5 §3.1, core_dsl #29 | git has a merge story, Hex does not | Survives untouched. |
| Two axes, no cross-reference | v5 §7.18 | composability | Survives untouched. |
| No bundle-side code, non-Turing predicates | v5 §6, non-goals | scheduler/audit/security | Survives; removing the predicate language strengthens it. |
| Derive rather than declare (throwback, gate scope, rootness, namespaces) | core_dsl #17–#27 | a field that restates a derivable fact is refused | Questionable: each derivation costs a paragraph of prose and an "engine-derived" concept the author must know; a declared field costs one line and is greppable. See §4.4. |

### 2.5 How it got this way

Source: report G. The visible history is shallow (78 commits, ten
days), but the record narrates the rest in its own rule titles:
core_dsl #14–#16 are the fourth, fifth and sixth ORC-105 passes;
#21–#25 are ORC-151's design pass and its third through sixth
reviews, each titled with what the previous one left standing.
Corrective commits to `dsl-syntax.md` outnumber additive ones about
7:2. Three consecutive tickets (ORC-134, 184, 193) found that no
prompt in the bundle ever rendered `{{ feedback }}`; ORC-236's title
is that mint fields, six edges, supplied tiers and walk projections
were "all declared and none is wired". Two whole tickets (ORC-187,
ORC-200) are coherence sweeps of the record against itself. The
retros contain no reflection on any of this; they are ticket lists.

The pattern was running while this memo was written. ORC-247 was
filed as a content bug in the `policy` grain and, over five design
rounds, acquired three new load rules, a new walk-naming form, a
rewrite of how walks bind to prompt variables, and a tier split, with
two record-review declines for narrating its own rounds. Each step
was locally right. `in-flight-tickets.md` has the detail.

## 3. The six steps, evaluated

**Step 1 — isolate syntax and vocabulary to see its size.** Right,
and now done (§2.1, reports A and B). Two amendments. First, measure
the bundle's information content alongside the grammar's size (§2.2):
the grammar being large is a symptom; the bundle being ten times
larger than its content is the disease, and the two have different
cures. Second, do not count prompt variables, XML grammar elements
or extension kinds as DSL vocabulary; they inflate the count and are
not what an author writes.

**Step 2 — break the doc into protocol vs implementation.** The
premise needs sharpening before it is useful. The doc contains at
least five kinds of text (grammar, author-facing rule, mechanism
narration, rationale/history, worked example), and the split that
matters most is not among them: it is between constructs the engine
reads, constructs it is intended to read, and constructs nobody has
claimed (§2.3). A protocol/implementation cut applied to the text
will present, on the "protocol" side, a flow grammar and a predicate
language in the same voice as the walks the engine runs on, and a
reader cannot tell which rules bind today. So classify each
*construct* (not each paragraph) as **live**, **reserved** or
**questioned**, using three columns: used by the default bundle; read
by the engine; intended by the record or the author. Reports D and E
give the first two columns for every construct today; the third is
the author's, with the record's "Initial vs target" sections and
`build-plan.md` as the starting point. Then classify the *text* by
which construct it serves. Also rename the split: "protocol" is taken
in this repo; use **contract** (what a bundle must satisfy to load
and run, the loader's rules) versus **mechanism** (how the plane
processes a loaded bundle).

**New step — the seam pass.** With the construct list in hand, ask of
each flexibility the DSL offers: what does it let a bundle author
vary; what does that cost in loader, engine, doc and bundle; what
constraint does it place on authors; is that constraint the engine's
requirement or the default bundle's habit; and is this the right
level to impose it (grammar, XSD, prompt, engine code, binding)?
This is the pass that decides whether the code/data seam is drawn in
the right place, and it precedes the target grammar because it can
move constructs across the seam in both directions. `seam-pass.md`
is a first pass over the sixteen flexibilities the evidence names; it
is a starting table for that step, not its conclusion.

**Step 3 — evaluate how much simplifies away by isolating
implementation.** The honest answer is: less than by the seam pass
and the boilerplate cut. Isolating mechanism from the doc removes
~770 lines of prose and changes no grammar. What removes grammar is
the seam pass (constraints that turn out to be the default's habits,
or that belong in an XSD or a default rather than a declaration) and
the census (keys that take one value everywhere). What removes
bundle lines is derivation of review tiers and defaults for the
constant keys. Reserved constructs shrink in shape, not in number.

**Step 4 — split into four or five shorter docs, contract and
mechanism per bundle type.** Agree on the shape, disagree on the
method and on the mechanism half. Method: do not split the existing
text. Its duplication is structural (CLAUDE.md: "each load-time rule
stated at least twice by construction"), its examples have drifted,
and its grammar is ~570 lines; a fresh write from the inventory is
smaller than the edit and does not inherit the sibling-statement
failure mode. Mechanism half: the implementation record already
exists as `systems/core_dsl.md` (loader), `systems/engine.md`,
`systems/generation.md` and `systems/delivery.md` (consumers).
Writing "implementation for processing chain bundles" as a new
document creates a third copy of engine mechanism to keep coherent.
Instead, move the mechanism narration in the spec into those docs
where it is not already there, and delete it where it is. Recommended
set (§5.4): a shared bundle doc, a chain contract, a workflow
contract, reasons siblings, and no new mechanism docs.

**Step 5 — a second simplification pass on semantic significance per
bundle type.** Right, but it is the same work as step 3 done well,
and it must precede step 4, not follow it. Deciding what a chain
bundle *is* (which constructs are load-bearing) is the input to
writing the chain contract; doing it after produces a second
rewrite. Merge 3 and 5 into one "decide the target grammar" step.

**Step 6 — revise DSL docs and system docs.** Right, with one
addition: the design record (`v5-design-decisions.md`, `non-goals.md`,
`core_dsl.md`'s standing decisions) must be amended in the same
change, per the repo's own rule that a revised decision lives in the
document that records it. §2.4's table names the entries. And what
is removed goes into `non-goals.md` so it does not come back
(predicate language, extension registry, flows-in-v0).

**Missing step — the bundle.** No step touches `bundles/default` or
`bundles/default-flow`, and those are the artifact the size
complaint is about. The bundle rewrite is where the "ten times
larger" number is fixed, and it is the only test that the simplified
grammar still expresses the default.

## 4. Structural findings the methodology does not cover

### 4.1 The single-file chain is feasible and is the right first experiment

The chain graph's design content is ~40 edges, ~36 walk strings, ~70
field sources, 24 `produces` rows and ~30 tier-shape facts (scope,
parent). That fits in one file with tiers as a map and each tier's
edges and walks inline, on the order of 300–400 lines without
comments. Prompts and schemas stay as files; they are content, not
graph. The workflow axis already made this move (core_dsl #14: one
declaration, position inline, no side file) and the record never
decided file granularity on the chain axis, so there is nothing to
argue with.

Recommendation: before any doc work, hand-write `bundles/default` as
one `chain.yaml` in the target grammar, with no loader support, and
look at it. If it is readable in one sitting, the DSL is worth
keeping and the grammar it needed is the v0 grammar. If it is not,
the answer to "pipeline as data or as code" has changed and the doc
work should not start. This is the cheapest decisive experiment
available, and it is the kind of work (global, all-in-view) the
pipeline cannot do.

### 4.2 Reviews should be derived, not declared

Seventeen files carry about twenty lines of information between
them: a name, and a prompt path derivable from the name in 16 of 17.
The rule that made them tiers (a review's context must equal the
reviewed tier's, checked at load) is satisfied by construction if the
review is a property of the tier (`review: prompts/review/x.md.liquid`,
or a bundle-level convention that every `llm` tier with a review
prompt file has one). This reverses core_dsl #9 and platform_content
#25 and dissolves their reason rather than contradicting it.

### 4.3 Reserved constructs stay, marked, and shrink in shape

Everything under `flows/`, the `cascade_visit` scope, the `synthesis`
edge type, the five `*_plan` tiers, the 21-instance `plan_target`
edge, `predicates.yaml` and the `completion` slot exist for a
capability the engine does not have yet (report E: no consumer for
any of it; `cascade_visit` yields no candidates). Flows are MVP
regardless: without them nothing modifies code after scaffolding.
The same holds, with less urgency, for the five generator types
without executors, `enforcement:`, gate `escalation`, environment
promotion, and the extension registry. Tickets will be cut against
these, and implementers building neighbouring code need to see them
to hedge. So they stay in the grammar.

What changes is how they are carried:

- **Marked.** Each construct in the contract doc carries a status:
  live (the engine reads it; the rule names its consumer) or reserved
  (intended; the rule names the intended consumer and the record
  entry or build-plan phase that owns it). A reader building against
  a reserved construct knows its exact form may move when its
  consumer lands; a reader auditing the loader knows which checks
  have a runtime counterpart.
- **Stated by intent as well as grammar.** For a reserved construct
  the intent is the durable part and the grammar is provisional.
  The doc says what the construct is for and what the consumer will
  need from it, then gives the current grammar. That is what a
  ticket needs to be cut from and what a hedge is against.
- **Simplified in shape, not removed.** Five planning tiers of one
  template, a 21-row edge that is a 5-row table, a predicate file
  with one form: the same intent in a fraction of the declaration is
  a simplification that survives the consumer landing. The flows
  entry in `seam-pass.md` asks whether the planning-tier shape is the engine's
  requirement or the default's habit; that question is worth
  settling before the flow engine is written, not after.
- **Re-settled by the consumer's ticket.** The ticket that builds a
  reserved construct's consumer owns the final grammar and amends the
  contract doc in the same change. The record's "the tree will be
  made to match the record" rule holds; what is added is that a
  reserved rule announces it is ahead of the tree.

The `.synthesis` projection is the precedent for the other
direction: retired because no consumer existed and none was
intended (core_dsl #42). "Questioned" constructs are the ones with
neither a reader nor a recorded intent, and there are few:
`scope_filter`, `cardinality.when`, `per_source`, edge `constraint`,
`consistency`, the `name:` on a status entry, `lifetime: per_ticket`.
Each needs one sentence from the author: intended, or not.

### 4.4 Prefer declared fields to narrated derivations on the workflow axis

The §15 pattern is: whenever a field could restate a derivable fact,
refuse the field and describe the derivation. Each derivation costs a
paragraph the author must understand (derived throwback, derived gate
scope by position relative to `reconcile`, derived rootness, derived
namespaces, per-instance effective sequences), and the bundle's own
comments show authors restating the derived value anyway ("restates
the derived default rather than overriding it"). For a community-
facing grammar, an explicit one-line field that the loader checks for
consistency is cheaper to document, cheaper to read, and greppable.
Revisit each derivation in core_dsl #17–#27 with that trade in view.
Not all should flip; the ones whose derivation is a paragraph should.

### 4.5 The extension registry is a seam nobody has used yet

Dialects, the registry, the behaviour, `enforcement:`, `ticket.*`
sources: fully built, zero registrations, and the doctrine it serves
(core_dsl #2, frozen core) has been bypassed by every growth event.
It is reserved and stays. What needs correcting is the doctrine's
scope: an extension can hold a generator type, a context source, an
annotation namespace or an enforcement profile, because each is a
thing with an executor behind it. It cannot hold a scope kind, a
walk form or an edge locator, because those are grammar the core
parser must know. State the rule that holds: the core grammar grows
by a reviewed edit to the contract doc and the loader in one change;
executors grow by extension. That is simpler, true, and what the
record's own "grammar changes are reviewed edits here first" line
already says.

### 4.6 Every rule stated once, with an id; §13 disappears

The repo's own rationale mechanism (rule ids, `.reasons.md` siblings,
`pipeline reasons`) was applied to `systems/*.md` and never to
`dsl-syntax.md`, which has no reasons sibling and carries its reasons
inline. Apply it: each contract rule lives with its construct, once,
with an id and a one-line "load error naming X"; the reason lives in
the sibling. §13 as a separate checklist is the second statement of
every rule and is what made the six-round sibling failure possible.
If a checklist is wanted, generate it from the loader's problem
templates rather than maintaining it by hand.

### 4.7 No worked examples in the contract; the bundle is the example

The spec's embedded YAML has already drifted from the tree (report
B). Cite bundle files by path instead, and make "the shipped bundles
load under the loader" a test, which it presumably already is. An
example that is the tree cannot drift from it.

### 4.8 Is the community goal still worth it?

The evidence says yes, conditionally. The DSL's live core (§2.3's
first list) is small, coherent and genuinely what the engine runs on;
it is the walks, scopes, fields and the status sequence. That is
"pipeline as data" in the sense v5 §7.10 already decided: shape in
data, semantics in code. What made it feel like a DSL rather than
data is the parts that lean toward being a program (predicates,
derivation rules) and the parts described as running before they
run (flows, the registry). Mark the second group, shrink the first
to what a consumer needs, and what remains is a graph file plus one
small expression language (walks) that has real semantics, with a
clearly fenced reserved section behind it. The condition is the one
v5 §8 states:
customization is the premise, and "if customizing requires learning
YAML, that premise is half-delivered". The acceptance test for the
whole effort is therefore not the grammar's size but whether a
newcomer can read the default chain in one sitting. Put a number on
it and hold the redesign to it.

### 4.9 The pipeline is the wrong instrument for the redesign

The DAG model works when a ticket's correctness is checkable locally
against a file map. Grammar design fails that test: every rule
interacts with every other and with the bundle, and the record shows
what happens when it is done in per-ticket passes (§2.5). Do the
redesign (target grammar, single-file prototype, contract docs,
record amendments) out of band, in one or a few sessions with the
whole thing in view. Hand the pipeline what it is good at afterwards:
loader shrink to the new grammar, bundle regeneration, coherence
checks, and a drift guard (a task that emits the loader's key
inventory and diffs it against the contract doc).

## 5. Recommended methodology, revised

0. **Freeze.** No DSL grammar changes through the pipeline until the
   redesign lands; growth-in-content-tickets is the pattern that
   produced the current state.
1. **Measure.** Done; `evidence/`. Refresh the numbers only if the
   tree moves.
2. **Classify constructs, against the code and the intent.** One
   matrix: construct × {used by default bundle, read by engine,
   intended}. Reports D and E are the first two columns; the third
   is the author's. Read + anything = **live**. Unread + intended =
   **reserved**: stays, marked, intent stated, shape simplified,
   grammar re-settled by its consumer's ticket. Unread + unintended
   = **questioned**: one sentence from the author decides.
3. **Run the seam pass.** For each flexibility (start from
   `seam-pass.md`): what it enables, what it costs, what it constrains,
   whether the constraint is the engine's or the default's, and
   whether this is the level to impose it. Outputs: constructs that
   move across the seam (into XSD, into a default, into engine code,
   or out of engine code into the grammar), and constraints that are
   the default bundle's habits and should be dropped from the
   contract. This is the step that decides whether the seam is
   drawn in the right place.
4. **Decide the target grammar by prototype.** Hand-write
   `bundles/default` as a single chain file and `bundles/default-flow`
   as a single workflow file in the candidate grammar, reserved
   constructs included in their simplified shape. Iterate on the
   grammar until the files read well. This is where §4.2, §4.4 and
   the review-derivation question are settled, by looking at the
   result rather than by argument.
5. **Write the contract docs fresh.** From the inventory, the seam
   pass and the prototype, not from the existing text: `docs/dsl/
   bundle.md` (layout, `catapult.yaml`, manifest, fork rule,
   deliberately absent), `docs/dsl/chain.md`, `docs/dsl/workflow.md`,
   each with rule ids, a live/reserved marker per construct, the
   intended consumer named on every reserved rule, and a `.reasons
   .md` sibling; examples by path into the bundle; no checklist
   section. Ids follow the scheme PR #161 lands: the redesign is
   author-minted, so its rules take bare numbers, and a ticket that
   later amends a contract doc mints `#ORC-n-m`. The in-flight
   tickets' rules that survive the redesign keep their ids. Target
   sizes: a few hundred lines each. Written: `docs/dsl/bundle.md`
   (14 ids), `chain.md` (40) and `workflow.md` (40) with their
   siblings, 99, 308 and 231 lines. One id is retired, `chain.md` #7,
   whose reasons entry carries why the binding reversed. `docs/dsl-syntax.md` and the
   `dsl-syntax.md` citation shorthand retire with step 6, since the
   shorthand is author-owned config and the record's citations move
   in the same pass.
6. **Amend the record.** v5 §3.4, §6, §7.10, §7.18, §7.19 and §9, and
   the core_dsl and platform_content standing decisions §2.4 names;
   add to `non-goals.md` anything the seam pass removed and why.
   §7.10 and §7.19 are where the cross-axis binding is stated, four
   passages between them, and the reversal touches every one. Move mechanism
   narration from the old spec into `systems/*.md` where it is not
   already there. Give each reserved construct a home in the relevant
   system doc's "Initial vs target" section so the build plan can
   cut tickets against it.
7. **Implement, via the pipeline.** Loader: remove parsers and checks
   only for questioned constructs the author retired and for
   constraints the seam pass moved elsewhere; keep reserved parsing;
   add the single-file loader. Bundle: replace the tree with the
   prototype. Add the drift guard. Then the ordinary coherence pass.
8. **Hold to the acceptance test.** The default chain file is
   readable in one sitting by someone who has not read the engine,
   and a reader can tell from the contract doc alone which rules
   bind today. The number (`seam-decisions.md` §5.b): the chain file
   at most 800 lines including comments with comments at most a
   fifth, the workflow file at most 240, both read in thirty
   minutes.

## 6. Decisions the author has made

The author reviewed every change in `seam-decisions.md` §2 and each
entry there carries the decision beside its argument. The ones that
changed a recommendation:

- Free tier-status binding, strict (§1.3, §2.C.1): the middle option
  (kinds shared, fine names degrading to kinds) fails because the
  skeletons stipulate several positions per kind. Names are the
  pair's; the loader refuses a `phase:` the paired type lacks; the
  chain flow names its type; a traversability check and a cross-axis
  warning replace the fixed table.
- Context derives from edges by default (§2.A.5): each edge declares
  its projection, a tier receives every edge from self or its parent,
  and only `all.*`, `input.*` and additions are explicit. Two thirds
  of the shipped walks derive.
- `agent_step` is dropped and `phase:` is required (§2.A.12); the
  three uses of "role" are named there.
- Endpoint locators stay explicit (§2.A.9).
- Gate depth defaults to all depths; less review is explicit (§2.B.2).
- `pending` becomes an engine flag (§2.B.8); critique placement is
  order-only (§2.B.9); the ungrouped-throwback rule is dropped
  (§2.B.5); `blocks:` keeps the loader's namespaced semantics and the
  runtime is corrected (§2.B.4).
- The container backbone requires `main` and relative order; `fills:`
  on a status names where a population step's tickets land and
  implies the rest (§2.B.7).
- The reconcile prompt lives on the fan-out tier; the position stays
  in the workflow (§2.C.2).
- The XSD/DSL seam: intra-node facts in the XSD, inter-node facts in
  the DSL (`seam-decisions.md` §5).

- `fills:` on the status rather than the tier (`seam-decisions.md`
  §5.a).
- The acceptance number (§4.8, `seam-decisions.md` §5.b): the chain
  file at most 800 lines, the workflow at most 240, thirty minutes to
  read.

Nothing in the seam pass is open. §5 step 4, the hand-written
prototype, is at `prototype/`: both bundles as one file each, a check
script that derives context, runs traversability and measures, and a
README naming what the prototype found (a subtraction case in the edge
default, an instance-level projection, the plan tiers' global reads,
and the inventory duplicated across `scaffold` and `delta`).

The binding between the two axes was reversed after the pair was
written: a workflow position now names its tiers and a ticket type
names the flows it serves, and the chain names nothing in the
workflow. §2.C.1 carries the author's reason and the three
consequences; the prototype, the three contract docs and their reasons
are written against the reversed direction.
