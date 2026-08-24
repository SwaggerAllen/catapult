# Catapult DSL — syntax reference (v0)

**Status:** the normative syntax for the DSL core, consolidating the
v4 spec's §A.2 with every v5 delta (v5 §6, §9). Where this document
and the v4 spec disagree, this document wins. The Phase 3 loader
ticket implements exactly these productions; reconciliation verifies
the loader against this file. Grammar changes are reviewed edits
here first, code second.

Two design invariants govern everything below (v5 §6, §9): **closed
vocabularies everywhere** — no bundle-side code, no
Turing-completeness, every enumerable set enumerated — and **the
core is frozen; growth happens in extensions** (§12 below).

---

## 1. On-disk layout

A project loads **two bundles on two independent axes** (v5 §7.18): a
**chain** bundle (the doc graph — what the agents build) and a
**workflow** bundle (the human cycle — gates, review states,
environments). Same language, same loader, separate files, imported
separately, so one organization's workflow can span decompositions
that differ by target stack.

```
catapult.yaml                  # repo root: pins one bundle per axis
bundles/<name>/                # kind: chain
  bundle.yaml                  # registry: name, version, kind, extends, files
  tiers/<tier>.yaml            # one file per tier declaration
  edges/<edge>.yaml            # one file per named edge instance
  predicates.yaml              # optional: named predicates
  prompts/<tier>.md.liquid     # one per LLM-generator tier
  prompts/review/<tier>.md.liquid
  prompts/partials/<name>.md.liquid   # shared fragments ({% render %})
  schemas/<name>.xsd           # body grammars referenced by tiers
  flows/<flow>/flow.yaml       # one directory per flow
  flows/<flow>/<prompt>.md.liquid
bundles/<name>/                # kind: workflow
  bundle.yaml
  gates/<gate>.yaml            # one file per declared review gate
  environments/<env>.yaml      # one file per deployment environment
  types/<name>.yaml             # one file per registered work-item type (§15.9)
  queues/project.yaml           # singular: the project's own declared queue sequence (§15.6-§15.7)
  queues/containers/<name>.yaml # one file per declared container (§15.6-§15.9)
```

`catapult.yaml`:

```yaml
chain: default           # directory name under bundles/, kind: chain
workflow: default-flow   # directory name under bundles/, kind: workflow
```

## 2. bundle.yaml

```yaml
name: default
version: "1.0.0"
kind: chain                       # chain | workflow (§11)
extends: platform-elixir          # optional; content layering (§11)
tiers: [tiers/*.yaml]             # glob lists; the loaded bundle is the union
edges: [edges/*.yaml]
fragments: [techspec, pubapi, privapi, policies, failure_surface]
flows: [flows/*/flow.yaml]
```

A workflow bundle's manifest carries `kind: workflow`, its own
`extends:` (the platform workflow layer, which ships the default UX
and engineering review gates and the `dev`/`staging` environments),
and `gates:` / `environments:` / `queues:` globs in place of the
chain's lists. The file-list keys are per-kind: a `tiers:` list in a
workflow bundle is an unknown field and a load error, per §13.

Fragment kinds are a **closed vocabulary per bundle**: a kind used in
any `handle:` or `produces:` must appear here.

## 3. Tier declarations

```yaml
tier: comparch                    # unique within the loaded union
scope: per(comp)                  # §3.1
scope_filter: is_domain           # optional predicate (§8)
identity: id                      # id | alias | name
fields:                           # scalar projections of body content
  name: draft.name
  techspec: draft.techspec
handle:                           # the public surface downstream walks read
  fields: [id, name]
  fragments: [techspec, pubapi]
draft:                            # omit entirely for join-target tiers
  root_tag: comparch
  grammar: schemas/comparch.xsd
generator: llm                    # §3.2
prompt: prompts/comparch.md.liquid
executor:                         # optional; how the generation runs
  effort: max                     # effort hint (v5 §B.2.4 lineage)
  # The design dialect's executor is agent-dispatch, always (v5 §1.2:
  # agents end-to-end); the runtime dialect uses the completion
  # adapter. Profile selection is dialect-level; `executor:` carries
  # per-tier hints (effort, model tier), not the mechanism.
context:                          # ordered edge-walk expressions (§7)
  - self.parent.handle
  - self.parent.fulfills -> resp.handle
  - self.parent.dependency -> comp.handle.fragments[pubapi]
                                  # the walk's target names a real tier
                                  # in the loaded union — "target" above
                                  # is illustrative prose for "whichever
                                  # tier the edge in question resolves
                                  # to", not a literal name a bundle may
                                  # write; the loader looks up exactly
                                  # the tier named after "->" (§13)
produces:                         # fragments this draft writes on other nodes
  - fragment: { owner: self.parent, kind: techspec, authored: draft.techspec }
delivery:                         # extension-provided namespace (§12)
  phase: generation                # a §15.1 system-status kind — platform-
  agent_step: design              # fixed vocabulary only (§11): statuses,
                                  # agent steps — never a display name from
                                  # a workflow bundle's declared review
                                  # sequence, and never a gate or environment
enforcement: []                   # extension-provided profiles, e.g. [codegen: restricted]
```

**A join-target tier's `fields:` source is `mint.<name>`, not
`draft.<name>`.** A tier with no `draft:` has no body of its own to
project scalars from, but it still needs a field source the way any
other tier does — a comp minting `kind` from the sysarch row that
named it, a subcomp minting `name` from the comparch row that named
it. `mint.<name>` names that source: the value the minting fanout
edge's `declared_in:` row carried for this node, or (when the value
is inherited rather than row-local — a comp copying its grandparent
sysarch's project-wide techspec, one hop further than a single context
walk can reach, §7 below) a plain copy made at the same mint moment
from the minting instance's own handle. Both are engine-side
resolution, exactly as unvalidated at load time as a `draft.<name>`
path already is (§13 checks cross-references, not path semantics);
naming the convention here is so two bundle authors, or one bundle
read twice, agree on what a join-target tier's `fields:` values mean.

Per-scope attributes that appear in *body* declarations rather than
tier files (they vary per node, not per tier): `implementation:
stubbed | real` with `swap: transparent | migration | reset` (v5
§2.16), declared in the comparch grammar; `locus: server | client`
(v5 §5.6) on backend-family component declarations.

### 3.1 Scope expressions — closed set

- `singleton` — one node per project.
- `per(X)` — one node per node of tier X. `self.parent` is that node.
- `child_of(X)` — nodes minted by X's fanout edge.
- `cascade_visit` — one node per node a flow's own cascade walk visits
  (§6's `walk: downward_cascade` / `up_then_down`), minted by the
  engine as the walk proceeds rather than by a `child_of` fanout edge
  read from a body. A tier at this scope has no fixed parent tier —
  which node minted a given instance varies with where the cascade is
  — so it carries no `self.parent` context walk; instead it reaches
  the node it is currently planning for through a declared `synthesis`
  edge (§4.1) and reads project-wide state through `all.<tier>` (§7).
  Exists for exactly one purpose: a flow's planning tier, one plan per
  visited scaffold node, closing the gap a `per(X)` scope can't (a
  cascade visits nodes across several different tiers, and `per(X)`
  names exactly one).

**Delta from v4: the phased variants (`per(X) × phase`) are removed**
with the phase machinery (v5 §6). There is no `phase` dimension.
`cascade_visit` replaces v4's informal `per(scaffold_tier)` +
`scope_filter: in_cascade_visit_set` (`seed-docs/catapult-default-
bundle-v4-examples.md` §2.1-§2.6): v4's `scaffold_tier` was never a
real tier `per(X)` could name — it meant "whichever tier the cascade
is currently touching" — and `in_cascade_visit_set` was a platform-
managed predicate with no counterpart in this loader's predicate
language (§8). One real scope kind replaces both.

### 3.2 Generator types — closed set, extension-growable

`llm` (default), `git_commit` (+ `code_repo_url`, `path_from_handle`),
`synthesis`, `webhook`, and the v5 additions: **`external`** (content
resolves from the component registry at the pinned version; requires
`package:` and optional `options:` per v5 §3.4) and **`template`**
(deterministic scaffold; requires `template:` path; slots filled from
context walks; no LLM call, same grammar validation).

### 3.3 Review tiers — `reviews: <tier>`

A review is a tier, not a nested block on the tier it reviews (v5
§7.19, revised). Declared like any other tier, with one addition and
several omissions:

```yaml
tier: comparch_review
reviews: comparch                 # marks this a review tier for `comparch`;
                                  # scope, identity and cardinality are
                                  # comparch's, 1:1, and are never restated
generator: llm
prompt: prompts/review/comparch.md.liquid
grammar: schemas/review.xsd       # the platform-wide review grammar (§10)
context:                          # must equal comparch's own context: below —
  - self.parent.handle            # a load-time check (§13), not the shared
  - self.parent.fulfills -> resp.handle   # assembly-path convention this
  - self.parent.dependency -> comp.handle.fragments[pubapi]  # replaces
  - self.reference -> ref.handle
delivery:
  phase: critique                 # a §15.1 system-status kind, same rule
  agent_step: critique            # as any other tier's delivery: (§11)
```

**No `scope:`, `identity:`, `handle:`, `fields:`, `draft:` or
`produces:`.** A review's cardinality and position are the reviewed
tier's by construction — `reviews: comparch` fully determines them, so
restating `scope:` would only be a second place for it to drift out of
step — and a review tier exposes nothing downstream: no committed
body, no handle another tier's context walk could target
(`docs/v5-design-decisions.md` §7.19). `self.parent` inside a review
tier's own `context:` resolves exactly as it does for the reviewed
tier, since the underlying node is the same one.

**`context:` is restated and checked, not inherited silently.** The
review tier declares its own `context:` list; the loader verifies it
is the same set of walks as the reviewed tier's own `context:` (§13).
This is what makes the per-tier triad invariant ("generation and
review receive identical context plus `draft`", §9) a load-time
property instead of a runtime discipline living in shared assembly
code. `draft` and `prior_review` are never `context:` entries — they
are template variables supplied automatically to a review tier's
prompt (§9), exactly as before.

**Never named from the workflow axis.** A workflow bundle turns the
critique slot that follows a given generation status *on* by
declaring it — `critique.yaml` (§15.5) — never by naming a review
tier (`comparch_review`): the declaration references the
platform-fixed status (`critique`) by its one fixed path, never a
bundle's own tier. Naming a review tier from a workflow declaration
is the identical cross-axis leak §11 already forbids for gates and
generation tiers. **Revised at ORC-92:** an earlier reading of this
paragraph had the direction backward — critique present by default,
disabled by naming it — which is not what actually happens: no
workflow bundle in this repo declares anything about critique today,
and that silence means "off," not "on and undeclared." §15.5 settles
it explicitly: absent a `critique.yaml`, no critique tier runs at
all; declaring one is what turns it on, at the depth it names.

## 4. Edge declarations

```yaml
edge: dependency                  # unique name within the union
type: dependency                  # fanout | reference | dependency |
                                  #   policy_application | synthesis
source: comp
target: comp
declared_in: comp.draft.dependencies[].@to
cardinality:
  source: { min: 0 }              # {min, max}; max default unbounded
  target: { min: 0 }
  # optional refinements:
  # when: kind == presentational
  # per_source: comp
graph_constraint: [acyclic, no_self_loop]   # also: tree
consistency: eventual             # dependency edges only:
                                  #   eventual (default) | transactional
                                  #   (v5 §2.6 — transactional couplings
                                  #   are declared, enumerable state)
navigation: false                 # default; true marks a cyclic-legal
                                  # navigation edge (§4's v5 rule below)
constraint: reaches(source, target)   # optional; §8's fourth predicate
                                  # slot, alongside scope_filter,
                                  # cardinality.when and a flow's
                                  # completion
```

Rules carried from v4, still normative: the full edge-instance graph
must be **type-level acyclic** at load; `graph_constraint: acyclic`
is additionally checked per-instance at projection time; `declared_in`
paths parse against committed bodies.

**`type: synthesis` is the one exception to that last rule.** Every
other type's `declared_in` names a location in a committed draft body
the reducer reads; a synthesis edge's instances have no such location
— they are computed by the engine itself (a `cascade_visit`-scoped
planning node's correspondence to the specific scaffold node it is
currently planning for, §3.1, is the motivating case) at the same
moment `mint.<name>` field values are (§3). `declared_in` stays a
required, human-readable string on a synthesis edge — naming what the
engine computes, not where it reads — for the same reason `policy`'s
mint-time fields do (§3's closed note): unvalidated at load time
exactly as a body path already is, but not therefore meaningless.

**v5 rule:** navigation edges (product tier, screen→screen) are
cyclic-legal reference edges and **must never appear in a readiness-
bearing context walk** — the loader rejects a context entry that
traverses an edge marked `navigation: true`.

### 4.1 Multi-instance edges — `instances:`

The shape above — one `source`/`target`/`declared_in`/`cardinality`
inline — is the common case: one relationship, one site. Some
relationships recur at several sites with **the same mechanism**: a
fanout that mints children the identical way at more than one tier
(`sysarch` mints `comp`, `comparch` mints `subcomp`,
`feature_expansion` mints `vocab` — one *kind* of edge, three sites),
or a dependency edge that means the same thing whether it links two
`comp`s or two `subcomp`s. `instances:` names that relationship once
and lists every site under it, instead of forcing a distinct edge name
per site:

```yaml
edge: decomposition
type: fanout
instances:
  - source: sysarch
    target: comp
    declared_in: sysarch.draft.components.component[]
    cardinality:
      source: { min: 1 }
      target: { min: 1, max: 1 }
  - source: comparch
    target: subcomp
    declared_in: comparch.draft.subcomponents.subcomponent[]
    cardinality:
      source: { min: 1 }
      target: { min: 1, max: 1 }
  - source: feature_expansion
    target: vocab
    declared_in: feature_expansion.draft.vocabulary.term[]
    cardinality:
      source: { min: 0 }
      target: { min: 1, max: 1 }
graph_constraint: [acyclic, no_self_loop]
```

`instances:` and the flat `source`/`target`/`declared_in`/
`cardinality` form are **mutually exclusive** — an edge declares one
instance inline, or several under `instances:`, never both, and never
neither. `type`, `graph_constraint`, `consistency`, `navigation` and
`constraint` sit above `instances:` and apply to every site: the
mechanism is one thing even when it fires at several places in the
tier graph. Every instance still contributes its own `{source,
target}` pair to the **type-level acyclicity** check (§13) — the
graph is over sites, not over edge names.

A context walk (§7) still names the edge once (`.decomposition`,
`.dependency`); the loader resolves which instance a given hop means
by matching the walking tier against each instance's `source` (a
reversed hop matches `target` instead — §7). When more than one
instance could match — the same source fanning out to several
different target tiers — the walk's own `-> <tier>.<projection>` on
the *last* hop picks the one landing on that tier; only when no
instance names that tier does the walk fail to resolve.

Authored-only (no derived fragments — derived views are context
walks). Declared in `bundle.yaml`'s closed vocabulary; written via
`produces:`; read via `handle.fragments` and
`...fragments[<kind>]` walk projections. Ownership and authorship
are projection state.

## 6. Flows

```yaml
flow: capability
delta:                            # schema delta while the flow is open
  tiers: [tiers/capability_plan.yaml]
  edges: []
walk: downward_cascade            # downward_cascade | up_then_down
ticket:                           # the delivery face (v5 §7.10)
  entry: requirements             # cascade start; upstream gates skip as no_diff
  labels: []
completion: capability_complete   # named predicate (§8)
```

Scaffolding is **not** a flow: it is the base schema with a ticket
face and an empty delta (v5 §7.10). The `up_then_down` walk's first
planning step decides how far up to go; terminating at height zero is
legal (v5 §7.11).

## 7. Context walks

Anatomy (unchanged from v4 §A.2.5): `self`, `self.parent`,
`.<edge_name>` follows a declared edge, `-> <tier>.<projection>`
types the target and names what to read — `.handle`,
`.handle.fragments[<kind>]`, `.synthesis`. Cardinality-many walks
yield collections; readiness requires **all** targets ready.
Context is the only readiness signal.

### 7.1 Hop chains and reversal

**Delta from the loader as first merged (ORC-5): a walk may name more
than one edge, and a hop may be reversed.** The original grammar
capped a walk at exactly one `.<edge_name>` before `->`; that cap is
what made a policy scoped **through a responsibility** — comp → resp
(`.fulfills`) → policy (inbound `policy_application`) — inexpressible,
since reaching it needs two hops and the second one runs against the
edge's declared direction. Both restrictions are lifted:

```
self.parent.fulfills.policy_application~ -> policy.handle
```

Reads as: `self.parent` (the comp), `.fulfills` (forward — comp is
`fulfills`'s declared `source`, land on the resp it names), then
`.policy_application~` (**reversed** — the trailing `~` means the
walker matches the edge's `target`, not its `source`, and the walk
continues from whichever `source` instance matches: every policy
whose `policy_application` instance targets this resp). Each hop is
checked independently against the declared edge (or, for a
multi-instance edge, against whichever instance actually matches —
§4.1); a hop naming an edge with no instance on the required side is
a load error, exactly as an unmatched single hop always was. A
reversed hop never turns a `navigation: true` edge readiness-bearing
— that check runs on every hop, not just a forward one.

This is engine-side resolution the same way a forward hop always was:
the loader's job is confirming the chain of edges is well-formed and
reachable from the walking tier, not evaluating it against instance
data (§13 checks cross-references, not runtime graph state).

### 7.2 `all.<tier>` — every instance, no edge

```yaml
context:
  - all.vocab.handle
  - all.comp.handle.fragments[techspec]
```

Reads every declared instance of `<tier>` in the project, unfiltered
by any relationship — no `self`, no edge, no walker to arrive from.
Two cases want this: a genuinely flat pool with no single owning
parent (`vocab`, `ref`, a project-global `policy` — v5 §4.5's first
grain, which by construction has no `policy_application` edge for a
graph walk to follow at all), and a `cascade_visit`-scoped planning
tier that needs to see the whole component graph rather than one
scoped slice of it (a `refactor` plan reasoning about which
components a structural change touches). The tier named after `all.`
must be declared; that is the entire cross-reference (§13) — unlike a
self-hop's target, there is no walker to check it against.

v5 additions:

- **`input.<role>`** — reads the intake documents tagged with a
  declared role (`input.project_doc`, `input.behavior_docs`,
  `input.mocks`; roles registered in the platform layer, v5 §7.3's
  intake list).
  **Roles are optional classification of a free-form raft, never
  requirements**: a role with no documents yields an empty
  collection and **never blocks readiness** (v5 §1.1 — requiring a
  specific file in the raft is the recorded antipattern).
  **`input.*`** reads the whole raft (the intake distillation
  tiers' walk). Both forms **resolve to the versions pinned at
  intake, always** — input documents freeze after the scaffold pass
  (v5 §1.1); a later file edit changes nothing a walk reads and
  stales nothing.
- **`ticket.findings`** — extension-provided source (§12): validation
  findings + ticket thread for the scope, available to flow planning
  tiers only (v5 §7.11).

## 8. Predicate language

Unchanged from v4 §A.2.6 and deliberately not Turing-complete. Six
operator families: comparison (`== != < > <= >=`), boolean
(`AND OR NOT`), edge counting (`has_edge`, `count(...) op N`),
existential (`exists(path where p)`), universal (`all/any(path ->
field)`), reachability (`reaches(a, b, via=[...])`). Exactly four
slots: `scope_filter`, `cardinality.when`, edge `constraint`, flow
`completion`. Named predicates compose in `predicates.yaml`; no
arithmetic, strings, or regex.

**A `cascade_visit`-scoped tier's own name, as a universal-quantifier
path root, means "every instance of this tier minted for the currently
open flow instance."** `all(refactor_plan -> resolved)` — a flow's
`completion:` predicate over its own planning tier, now that the tier
mints one node per visited scaffold node (§3.1) rather than one
singleton: completion is every visited node's plan resolved, not one
node's. This is engine-side resolution exactly like every other path
root in this language (`has_edge`'s edge name, `count`'s edge name):
the loader checks the predicate parses (§13), not what "refactor_plan"
resolves to at runtime.

## 9. Prompts

Liquid (Solid). Variables: one per named context walk
(cardinality-many walks iterate), `self`, `feedback`, `prior_review`,
and — review prompts only — `draft`. A variable's name is its target
tier's name (`resp`, `policy`, `comp`); an `all.<tier>` entry (§7.2)
gets the same name as a self-hop entry landing on that tier. **Two or
more context entries naming the same target tier combine into one
collection for that tier's variable** rather than colliding — a tier
can be reached more than one way (comparch reads `policy` through both
a direct `policy_application~` hop and a `fulfills.policy_application~`
hop, §7.1's worked example), and the prompt wants "every policy that
applies to me," not one variable per path that produced it. Shared
content via `{% render "partials/<name>" %}` (v5 §6: one source for
shared framing across the six architecture tiers). Generation and
review templates for a tier receive identical context plus `draft` —
the per-tier triad invariant. `draft` (and `prior_review`) are
supplied automatically by the shared context-assembly path; that a
review tier's own declared `context:` matches the reviewed tier's is
a load-time check instead (§3.3, §13).

## 10. Grammars

Body grammars are XML-fragmented markdown validated per tier
(`draft.root_tag` + XSD), at commit time, atomically — validation
failure is typed feedback, never a half-committed state. The review
grammar is platform-wide (v4 §B.3.2's `<review>` shape) and the same
file backs every review tier's `grammar:` (§3.3): `<intro>`, an
integer `<score>` (0-100, v4's buckets), and zero or more
`<finding id="...">` — the `id` is what a comment gets anchored under
when the finding is projected into the PR rather than committed as a
file (`docs/v5-design-decisions.md` §7.19). v5 grammar growth (the
productions, not the prose): comparch carries `<permissions>`,
`<enforcement>`, per-scope `<implementation>`; subcomparch carries the
process inventory; impl's `<tests>` block is normative for
reconciliation.

## 11. `extends:` — content layering

A bundle naming `extends: <layer>` loads the layer first, then
overlays: **declarations union; same-path files replace; the
*automation* protocol's own files never override** — the agent and
queue states, and the graph connecting them, ship in the platform
workflow layer and are not overlayable (v5 §7.10). **Narrowed at v5
§7.16/§7.18:** review states and deployment environments *are*
declarable, in a workflow bundle; what stays un-overlayable is the
automation graph itself. The admission rule is that a state may be
declared iff no plane logic branches on it.

**`extends:` layers within an axis and never across it.** A chain
extending a workflow, or the reverse, is a load error: the two axes
exist precisely so they can vary independently (v5 §7.18). Cycles in
`extends:` chains are load errors. Layering composes *content*; it
never adds vocabulary — that is §12's job, and the two mechanisms are
deliberately distinct (v5 §9).

**The axes do not reference each other at all. Both reference only
the platform's fixed vocabulary — statuses, queues, agent steps.** A
tier's `delivery:` block (v5 §7.10) names the phase it generates in
and the agent step that generates it, and nothing else; a workflow's
gates and environments attach to those same fixed positions. Neither
side can name a declaration belonging to the other, which is what
makes **any chain bundle composable with any workflow bundle** — no
shared gate or environment vocabulary, and no compatibility contract
to check (v5 §7.18). A gate's review set follows from where it sits:
it reviews whatever the chain produced at the step it follows.

## 12. Extension registration — the platform surface

Extensions are **platform-shipped modules** (never bundle content)
that register with the loader:

- **annotation namespaces** on existing declaration kinds (`delivery:`,
  `enforcement:`), each with a validation schema;
- **declaration kinds** (new file types — the flow ticket face);
- **generator types** (beyond §3.2's set);
- **context sources** (`ticket.findings`);
- **enforcement profiles** (`codegen: restricted`,
  `purity: replay_floor`) binding audit checks and/or delivery gates.

The loader validates the union of core + installed extensions; an
annotation against an uninstalled extension is a load error naming
the missing extension. A **dialect** is core + extension set +
defaults; two are registered: `design` (full Catapult) and `runtime`
(the embedded generation runtime, v5 §10 — no review lifecycle, no
git bodies).

## 13. Load-time validation

All-problems-at-once (orchestration's config style): unknown fields
rejected; every cross-reference resolves (edge endpoints, fragment
kinds, prompt/schema paths, predicate names); scope expressions and
generator types from the closed sets; type-level acyclicity over the
edge-instance graph; cardinality shapes well-formed; `delivery:`
values validated against the protocol vocabulary; navigation edges
absent from readiness walks; `extends:` acyclic. A bundle that loads
is a bundle the engine can run; only instance-level constraints
(dependency cycles, cardinality counts) wait for projection time.

Added with review tiers (§3.3, `docs/v5-design-decisions.md` §7.19):

- `reviews:` names a tier declared in the same loaded union — the
  same cross-reference rule as an edge endpoint or a fragment kind;
- a review tier's `context:` is the same set of walks as the tier it
  reviews — the triad invariant, checked rather than trusted; a
  review tier declaring a walk its reviewed tier doesn't (or missing
  one it does) is a load error naming the mismatch;
- a review tier carries no `scope:`, `draft:` or `produces:` — a
  review tier declaring any of them is a load error, since a review's
  cardinality is `reviews:`'s and it commits nothing (§3.3).

Added with the two axes and the declarable protocol surface (v5
§7.16, §7.18):

- every `delivery:` value on a tier — phase, agent step — resolves
  against the **platform's fixed vocabulary**, never against the
  loaded workflow bundle. A chain referencing a workflow declaration
  (or a workflow referencing a tier) is a load error naming the
  offending reference, because that reference is what would make the
  two bundles a matched pair rather than freely composable. There is
  deliberately **no chain/workflow compatibility check**: with no
  shared vocabulary there is nothing to check;
- every review status sits on an edge between **system statuses**
  (queue, generation, checks, merge, deploy) that exists, and its
  exits resolve within the workflow bundle (v5 §7.19);
- a **queue status precedes every generation and every deployment**;
- **every generation status has at least one blocked exit** — a
  generation that can fail with nowhere to land is the
  parked-ticket-nobody-can-act-on failure (v5 §7.6, §7.19). `Blocked`
  is a single system status; return routing is a rule over the
  ticket's effective sequence, not declared data, so there is nothing
  per-workflow to validate beyond this;
- **fan-out depth is never validated against the chain.** A depth
  exceeding a chain's actual fan-out applies at the levels that exist
  and is not an error: erroring would make the workflow's depth a
  claim about the chain's decomposition, which is the cross-axis
  coupling §11 forbids (v5 §7.19);
- **a `depth:` value is a non-negative integer, or a list of exactly
  two non-negative integers** (§7.19's `[first, rest]` pair) — on a
  gate, an environment, or `critique.yaml` (§15.5) alike, one grammar
  checked the same way at all three sites; any other spelling is a
  load error naming the offending value and the file it came from
  (v5 §7.19, ORC-92). The never-validated-against-the-chain rule
  above is unaffected: a pair's two positions are still ceilings,
  never claims checked against the chain's actual fan-out;
- **`critique.yaml` (§15.5) is optional, singular and
  structural-only at load time**, the same shape as `bundle.yaml`
  itself: at most one per loaded workflow bundle (`extends:` layers
  it by §11's same-path replace, never additively), unknown keys
  rejected, `depth:` validated by the rule above and defaulting to
  `0` when omitted. Its presence in the loaded union is the whole of
  what enables the critique slot — there is deliberately no
  `enabled:` field, for the same reason a gate needs no such field:
  absence from the union already means "does not run" (v5 §7.19,
  ORC-92). Neither this file's `depth:`, nor a gate's or an
  environment's `depth:`, is read by anything today — scheduling is a
  later consumer (v5 §7.19) — so there is no consumer to migrate;
- `extends:` never crosses axes, and each named bundle's `kind`
  matches the `catapult.yaml` key that named it;
- **a gate whose role has no holders is a load error**, not a runtime
  condition — otherwise a deadlocked gate is indistinguishable from a
  slow reviewer (v5 §7.16). Holders live in identity (Phase 7); until
  that component exists, the loader takes the roster as an opt-in
  input (a `role_holders:` resolver) and skips the check, rather than
  failing every load, when none is supplied — the same shape the
  mirror-mapping check below already has for the same reason;
- a gate's exits (forward and throwback) resolve to states that
  exist, and its declared escalation policy is well-formed;
- every declared review state has a counterpart in the mirror mapping
  when the outbound tracker add-on is configured (v5 §7.17) — an
  unmapped state is the failure that has halted a sweep before. Same
  opt-in shape as the role-holders check: a `mirror_mapping:` resolver
  is a loader input, not bundle content, since the add-on lands later
  (Phase 4+);
- §7.6's naming discipline over the *declared* set: no two states, or
  a state and a label, one hyphen apart in meaning — cheap against a
  fixed list, and an actual check against a declared one;
- a workflow bundle under the `runtime` dialect is a load error, not
  dead weight: that dialect has no review lifecycle (§12).

Added with container, project and work-item-type declarations
(§15.6-§15.9, ORC-105 — supersedes the milestone-only
`close/<kind>.yaml` shape ORC-103 drew up on its own unmerged branch
and this same ticket's own two earlier, since-reversed drafts (a
fixed seven-name project sequence checked against a two-member
`container:` registry, then a `flow:`/`opens:` pair on every queue
entry); nothing below has ever loaded, so this is the vocabulary's
first landing, not a revision of one in the loaded union):

- **`queues/project.yaml` is optional, singular and freely
  declared** — the same structural shape `critique.yaml` (§13 above)
  already has: at most one per loaded workflow bundle, `extends:`
  layers it by §11's same-path replace. Its `queues:` array names
  whatever queues the bundle wants, in whatever order and count the
  author chooses — array position is declared order, there is no
  `after:` field to duplicate it and no anchor sequence to check
  entries against, because a project needs no re-resolution anchor:
  every review happens at a lower level, and a project changes rarely
  enough that a workflow cutover mid-project is not the hazard a
  cutover mid-container is (§15.6). Each entry's `queue:` name is
  unique within the file; that is the only uniqueness rule;
- **`queues/containers/<name>.yaml` declares one named container**,
  and a bundle may hold many — directory-shaped like `gates/` for
  that reason, singular per name rather than singular per bundle.
  There is one container **kind**; `<name>` (and the file's own
  `container:` key) is that declaration's identity, not a selection
  from a platform registry — declaring `epic` or `program` is
  authoring, exactly like declaring a new gate or environment, never
  a platform change. A bundle may declare as many named containers as
  it wants, and any of them may nest inside any other (including
  itself in the trivial sense of "a container can be the thing a
  queue entry's `flow:` names" — see the acyclicity rule below for
  what actually bars self-nesting);
- **every container declaration's `queues:` array holds exactly the
  five platform-fixed anchor names, each exactly once, in exactly
  this order: `setup`, `prep`, `main`, `retro`, `cleanup`** (§15.6) —
  the container analogue of a ticket's system statuses, declarable by
  neither axis for the identical re-resolution reason. A missing
  name, a duplicate, an extra name, or the five out of order is a
  load error naming the declaration and the mismatch. There is no
  `after:` field on a container queue entry — position is the array
  index, and the array's shape is fixed, so there is nothing left for
  `after:` to say;
- **`types/<name>.yaml` registers one named work-item type**,
  directory-shaped like `gates/` and `queues/containers/`, for the
  identical reason: a bundle declares more than one. A type is,
  literally, a list of statuses — its `statuses:` names the declared
  gates (§15.2) this type's tickets visit; the system-status skeleton
  (§15.1) applies to every type unconditionally and is never repeated
  here. Order in `statuses:` carries no meaning of its own — each
  named gate already carries its own position via its own `after:`
  (§15.3) — so the array is checked for one thing only: every entry
  resolves to a gate declared in the loaded union. This inverts,
  rather than duplicates, what a gate's own former `ticket_types:`
  field did (§15.2 — now retired): the type names which gates it
  visits instead of every gate naming which types visit it, and there
  is exactly one place either fact is declared, so the two can no
  longer read as disagreeing;
- **container declarations and work-item-type declarations share one
  namespace** — the registry `flow:` resolves against. A `container:`
  name and a `type:` name may not collide, in either direction, and
  the loader does not care, when resolving a `flow:` reference, which
  of the two kinds of file produced the name — only what the resolved
  declaration's own content turns out to be;
- **`flow:` is the one field a queue entry carries, required, on
  every entry in `queues/project.yaml` and every entry in a
  `queues/containers/<name>.yaml` file alike** — naming a member of
  the registry above. This replaces the earlier `flow:`/`opens:` pair
  outright, not merely renames one half of it: there is no longer a
  structural difference, on the queue entry itself, between "this
  queue dispatches a ticket" and "this queue opens a nested
  container" for the loader to branch on. What the resolved name
  turns out to be — a plain type (dispatch terminates there, an
  ordinary ticket) or a container (dispatch mints a new instance,
  §15.8) — is visible only from what the *resolved declaration's own*
  array contains, never from anything the queue entry itself
  declares;
- **no cross-axis load-time check binds a queue's `flow:` value to a
  chain bundle's `flow:` declaration of the same name.** The
  identical non-binding §11 already holds between every other chain/
  workflow pairing, unaffected by the registry existing: a chain
  bundle shipping a flow whose `ticket:` face uses a matching label is
  what makes work actually dispatch there once a type opens, but that
  pairing is convention checked at ticket-open time (an unrecognized
  label opens no flow instance and files `Blocked`/`needs-setup`,
  `docs/v5-design-decisions.md` §7.4), never a loader cross-reference.
  The registry adds one guarantee this pairing didn't have before:
  `flow:` itself always resolves, on the workflow axis alone — there
  is no unresolvable reference left inside the workflow bundle's own
  graph, only the (unaffected, unchecked) question of whether the
  chain axis ever claims the name;
- **a `blocks:` entry must name a queue declared in the same file** —
  the same array (a container's five entries, or the project file's
  own list) — §2's scoping rule made mechanical: a queue cannot block
  something nested inside a different queue's own container
  instances, because that queue's internals are not this level's
  vocabulary to name. A `blocks:` entry naming a queue in a different
  declaration, or naming this queue itself, is a load error;
- **the declaration graph, over container names connected by `flow:`
  edges whose target resolves to another container** (from other
  containers' entries and from the project file's own entries), must
  be acyclic, and a container naming itself in one of its own
  entries' `flow:` is rejected outright as the degenerate one-node
  case of the same rule — checked statically, from the loaded bundle
  alone, before any container instance exists. A `flow:` edge whose
  target resolves to a plain type takes no part in this graph: a
  plain type declares no further `flow:` of its own, so it is always
  a leaf and can never sit on a cycle. This is the check that
  actually bars same-name nesting (a `milestone` declaration cannot
  open `milestone`) and bounds nesting depth: an acyclic graph has a
  finite longest path, so the maximum depth a bundle permits is
  knowable from the bundle itself, even though nesting composes
  arbitrarily (as many distinct named levels as the bundle declares).
  There is deliberately **no further, instance-level check** ("no
  container is its own ancestor") — it falls out of the declaration
  graph's acyclicity for free, and building it separately would leave
  unbounded depth *declarable*, caught only when some live chain of
  instances happens to close the loop, trading a load-time failure
  for a mid-flight one (the same trade this project has already made
  the other way: v5 §2.4's "failing at config load beats failing
  mid-flight").

## 14. Deliberately absent

Recorded so nobody re-adds them: **phases** (v5 §6 — dropped
entirely); **spawn declarations** (a plane rule at the Building
transition, not bundle content); **derived fragments** (context
walks at read time); **bundle-side code or open predicates**; **per-
project restructuring of the *automation* protocol** (v5 §7.10) —
narrowed at v5 §7.16/§7.18 from a flat "per-project protocol
restructuring": review gates and deployment environments are
declarable in a workflow bundle, while the automation graph, and the
agent and queue states composing it, stay platform-fixed. Also
absent, and newly so: **any cross-axis reference** — a `gate:` on a
tier, a tier name in a gate, a `requires_gates:` manifest key. All
three assume the chain and workflow bundles are a matched pair; they
are not, and composability with no shared vocabulary is the property
being protected (v5 §7.18). And a **second bundle system** for
delivery configuration (v5 §9, §7.18 — one language, two document
kinds). On a review tier specifically (§3.3): **`review_path:`**
(v4's paired `body_path:`/`review_path:`, `docs/v5-design-decisions.md`
§7.19 — a review projects to comments, never a committed file) and
**a per-tier `required:` gating flag** (dropped with the nested
`review:` block it lived on; threshold-based gating is a parked
scheduler item, §7.19, not bundle content).

**A milestone boundary ticket** (ORC-105, superseding ORC-103's own
unmerged framing of this same entry; `docs/v5-design-decisions.md`
§7.8): what is absent is the *pause-proxy* — a ticket standing in for
container state a borrowed tracker had nowhere else to hold, because
orchestration has no tracker of its own. Catapult owns its tracker
(v5 §7.17), so a container's progress is state on the container
entity itself (§15.6), and there is nothing for a proxy ticket to do.
**This is not the same absence as "no retro."** The retro pass is
present, as an ordinary work item dispatched through a milestone's
`retro` queue (§15.7) like any other flow instance — ORC-103's
`archive` close-step kind and this repo's own now-superseded "boundary
agent step" both did the retro's actual job under other names. Read
this entry as narrowing an earlier absence, not reversing it: the
ticket-as-state-proxy is gone; the ticket-as-work-item was never in
question.

**A stored per-queue ticket bucket.** A queue is a derived query —
the unresolved work items in a container or project assigned to this
queue's declared `flow:` (§15.7, `docs/v5-design-decisions.md` §7.8)
— never a materialized set the plane writes to and reads back. The
identical reason `ready_scopes` refuses to materialize applies
unchanged: a stale bucket is worse than none, because it is the kind
of thing a dispatcher acts on. What a queue holds is answerable by
query against the ticket store at any moment; nothing pre-computes it.

**A retro note.** Orchestration's boundary pass wrote one because
archived work becomes invisible to duplicate detection the moment it
archives, and the note was the only surviving trace. Containers and
projects alike keep references to their work items even once archived
(§15.6, `docs/v5-design-decisions.md` §7.8), which removes the
premise: a scan queue reads the container's own history directly, so
nothing needs to be written down solely so a later pass can find it
again.

**An `archive`-precedes-every-declared-queue load check.** ORC-103's
draft carried one, for the reason above: a scan reading ticket data
an unarchived-first sequence hadn't yet made durable. With archiving
policy rather than protocol, and containers never losing their
references to archived work, the failure that check existed to catch
cannot occur — keeping the check without its reason is the mistake
`docs/v5-design-decisions.md` §7.8 already argues against elsewhere.
Not built, and not merely omitted for now.

## 15. Workflow declarations

Placed after §14 rather than beside the chain declaration kinds
(§3–§10) so the existing section numbers, which the design record
cross-references throughout, stay stable. Everything here belongs to
a `kind: workflow` bundle (§2).

### 15.1 System statuses — the fixed vocabulary

Platform-fixed, referenced by both bundle axes, declarable by
neither (v5 §7.18, §7.19). They are the skeleton review statuses
attach to, and the anchor set a blocked ticket re-resolves against
when a workflow cutover removes the status it was parked at (v5 §6,
§7.19) — which they can only be because they are not declarable.

| kind | meaning | ball |
|---|---|---|
| `backlog` | committed to nothing yet | author |
| `queue` | committed, awaiting dispatch capacity | plane |
| `generation` | an agent run producing artifacts | agent |
| `critique` | an agent run reviewing a freshly produced draft | agent |
| `fanout` | children in flight; progress rolls up | plane |
| `checks` | CI running against produced work | world |
| `merge` | reconciliation into the parent branch | agent |
| `deploy` | promotion into a declared environment | world |
| `validating` | post-deploy verification (§7.11) | plane |
| `blocked` | single status, flavor labels, origin kept | varies |
| `stubbed` | waiting on an external timeline, by choice | world |
| `terminal` | shipped / done | — |

`ball` is v5 §7.11's author-owned vs machine-owned distinction, which
drives assignee rendering; `blocked` inherits from the status that
kicked to it.

**A `queue` precedes every `generation` and every `deploy`** — a
load-time check (§13), not a convention. **`stubbed` is exempt from
staleness and escalation** (v5 §7.6): nothing is stale about waiting
deliberately.

Mapping onto v5 §7.6's lifecycles, which are this vocabulary with
every review sequence at length one — feature: `Todo`(queue) →
*Product design*(generation) → **Product review**(review) →
*Architecting*(generation) → **Architecture review**(review) →
`Building`(fanout) → `Reconciling`(merge) → `Merged`(merge) →
`Validating`(validating) → `Shipped`(terminal). Child: `Ready for
dev`(queue) → `In progress`(generation) → `Checks`(checks) →
`Reconciling`(merge) → `Merged`(merge) → `Done`(terminal), with
`Ready for rework`(queue) / `Reworking`(generation) as the repair
loop. The two bolded statuses are the platform workflow layer's
default review declarations, not system statuses — which is what
makes them replaceable.

**Agent steps**, the other half of what a chain's `delivery:` block
may name (§3): `design` (produces a design-graph artifact for a
tier), `dev` (implements a child scope), `critique` (the review pass
over a freshly produced draft), `reconcile`, `validate` (§7.11's
repair loop). Adding one is a platform change, reviewed as one.

**`boundary` is retired from this list, and nothing replaces it
here.** It used to name "the milestone pass" as a single static agent
step, but no tier's `delivery:` ever actually named it — a milestone
close is not a chain tier's business, and the staticness was the
underlying problem (ORC-103's own finding, carried forward at
ORC-105). A container's progress is a declared sequence of queues
(§15.6-§15.9), not one fixed pass; the work that used to hide behind
`boundary` — the retro backward-looking pass and, at a container's own
fanout into a nested one, the forward-looking setup pass
(`docs/v5-design-decisions.md` §7.8) — dispatches as an ordinary flow
instance through a queue's declared `flow:`, the same mechanism as any
other ticket, needing no reserved slot in this closed set.

### 15.2 `gates/<gate>.yaml` — a review status

```yaml
review: ux-review               # status name; unique in the loaded union
after: product-review           # predecessor: a system status or another
                                #   review in this bundle (§15.3)
role: design                    # who signs off; identity holds the
                                #   holders, bindings the reviewers: map
depth: 1                        # fan-out depth (v5 §7.19); omitted = 0,
                                #   top level only. A maximum, never
                                #   validated against the chain. Also
                                #   accepts [first, rest] (§15.5) — the
                                #   project's first traversal of this
                                #   gate vs. every later one.
throwback: [product-design]     # exits it may reject to; each must be
                                #   earlier in the effective sequence
escalation: author              # policy; human gates are author-owned
```

Approval is the transition itself (v5 §7.16) — there is no approval
object, and no `approvers:` list. Who approved is answerable from the
log because the plane records the command with its actor.

**No `ticket_types:` field, as of ORC-105 — retired, not merely
undocumented.** A gate used to carry `ticket_types: [feature]`,
naming which types visited it; that fact is now declared the other
way, on the type (`types/<name>.yaml`'s `statuses:`, §15.9), and
there is exactly one place it lives. A bundle declaring `ticket_types:`
on a gate is an unknown field, rejected at load like any other (§13).

**Depth 0 is the rule for a gate, not merely its default** (v5 §7.19,
ORC-92). A gate is a human sign-off, and a human reads the top level;
setting a gate's depth by reasoning about how far the chain fans out
is arguing the auto-reviewer's case inside the human reviewer's own
declaration — that argument belongs to `critique.yaml` (§15.5), a
separate declaration for exactly this reason, not to a field on a
gate. Declare a gate at a nonzero depth only when the review genuinely
wants a human at every fanned-out node, which is unusual enough that
the file's own comment should say why.

### 15.3 Ordering, and why `after:` is a reference

Position is declared by naming a predecessor, never by an index. An
integer `order:` cannot survive `extends:` layering: an organization
inserting a review between two platform-layer reviews would have to
renumber files it does not own. Naming the predecessor lets the org
layer say `after: product-review` and leave the platform layer
untouched — which is the whole point of layering content (§11).

Since review is sequential (v5 §7.19), the order on an edge must be
total: **two review statuses declaring the same `after:` is a load
error**, as is a cycle in `after:` references.

### 15.4 `environments/<env>.yaml` — a deployment environment

```yaml
environment: staging
after: merge                    # the system status it deploys at
promote_from: dev               # previous environment; omitted = first
depth: 0                        # top level only, the usual case. Also
                                #   accepts [first, rest] (§15.5).
lifetime: persistent            # persistent | per_ticket (per-PR envs,
                                #   which are simply depth 0 + per_ticket)
```

**Endpoints, credentials and hostnames are not here.** They change
only how the plane connects and operates, so they are bindings —
plane entities, queried and picked, never repo content (v5 §7.10's
store test, and §8's BYO constraint: an endpoint in a bundle breaks
hosted onboarding). What lives here is which environments exist and
what promotion into one requires; that changes what is enforced, so
it is graph state, versioned, changed by PR.

### 15.5 `critique.yaml` — the auto-review knob

```yaml
depth: 1                        # same grammar as a gate's or an
                                #   environment's depth (§15.2, §15.4):
                                #   a non-negative integer, or a pair
                                #   [first, rest]. Omitted = 0, top
                                #   level only.
```

**Optional, singular, fixed path** — `bundles/<name>/critique.yaml`
at a workflow bundle's root, sibling to `bundle.yaml`, never a glob.
`gates/` and `environments/` are directories because a project
genuinely declares several of each; there is exactly one `critique`
status to configure, so a directory would hold at most one file and
buys nothing over a fixed path. `extends:` layers it exactly as it
layers any other bundle file (§11): a bundle naming `critique.yaml`
overlays whatever the layer beneath it declared at that same path.

**Presence is participation — there is no `enabled:` field.** A
workflow bundle whose loaded union (every `extends:` layer, not just
the leaf bundle) carries no `critique.yaml` runs no critique tier at
all, whatever the chain declares. One that does runs every review
tier the chain declares, filtered to `depth:`'s levels, exactly as a
gate's own depth filters which levels see it.

**This is the opt-in reading of v5 §7.19's "a workflow disabling the
critique slot," settled here rather than left to whichever the form
happened to imply.** An earlier draft of that sentence read as
critique-on-by-default, disabled by naming it — which, since no
workflow bundle in this repo declares anything about critique today,
would have made every existing project's chain review tiers start
running the moment this file's grammar shipped, decided by nobody.
Opt-in also fits the mechanism honestly: `extends:` composes by union
and same-path replacement (§11) and has no "the layer below declared
this; unmake it" primitive. A default-on critique could only be
turned off by a file whose entire content is a negative — a shape
this DSL has nowhere else. Default-off costs nothing equivalent:
turning critique on is an ordinary addition, the same shape a gate or
an environment already takes, and it never needs to un-declare
anything a lower layer holds.

**Configures a fixed kind; declares nothing.** `critique.yaml` never
names the status it configures. There is exactly one legal target
today (`critique`, §15.1) and the file's fixed path *is* the
reference to it, the same way `catapult.yaml`'s own fixed path needs
no field naming which repo it belongs to. This is what keeps the form
on the right side of §15.1's "declarable by neither axis": nothing
here mints a status name, and nothing here is a review tier's own
declaration (§3.3) — a chain still owns the review tiers themselves;
this file only says how far into the fan-out a workflow lets them
run.

**One spelling wherever a depth appears.** `[first, rest]` means the
same thing on a gate, an environment or here: "first" is the
project's first traversal of the status this depth attaches to —
never the first time a given *ticket* visits it, and never the pass
right after a throwback sends the status back for a repeat visit,
both of which are ordinary later traversals of a status the project
has already been through once (v5 §7.19). A bare integer still means
both positions at once, so no declaration written before this pair
form existed changes meaning.

### 15.6 Two forms: `project` and `container`

**A project is not a container, and the grammar gives them two
declaration shapes rather than one shape parameterized by kind**
(author review, superseding this same ticket's own first draft,
which gave both a fixed queue sequence off one `container:` field
checked against a two-member registry). They differ in exactly the
way that matters: a project's queue sequence is fully declared by the
workflow bundle, and a container's is not.

**A project holds no system statuses.** Its status is a position in
whatever ordered list of queues `queues/project.yaml` declares —
array order is declaration order, any names, any count, entirely the
bundle author's to choose. It needs no re-resolution anchor because
nothing here is fixed for a cutover to preserve: all review happens
at lower (container) levels, and a project changes shape rarely
enough that a workflow cutover mid-project isn't the hazard a cutover
mid-container is. `queues/project.yaml` is optional, singular and
structural-only at load time — the same shape `critique.yaml` already
has (§13): at most one per loaded workflow bundle, unknown keys
rejected, `extends:` layering it by §11's same-path replace.

**A container is one kind, arbitrarily nestable, and every instance —
whatever it's named — carries the identical fixed anchor sequence:
`setup` → `prep` → `main` → `retro` → `cleanup`.** Five names, not
four: an earlier draft dispatched `setup` as the value of `prep`'s own
`flow:`, which runs it once per *container* rather than once per
*mint* — wrong, because constituting a freshly minted instance is a
different event from an already-existing instance completing `prep`
again after a throwback. `setup` gets its own anchor position, first,
so it runs exactly once, at mint, before anything else in the
instance's own sequence (§15.8). This is the container analogue of
§15.1's system statuses: platform-fixed, declarable by neither axis,
for the identical re-resolution reason — the anchor a container
parked mid-sequence falls back to when a workflow cutover changes
what a queue dispatches underneath it. A container currently at
`main` stays at `main` across the cutover; only which type `main` now
dispatches changes. What varies per declared container is its
**name** (`milestone`, or any other name a bundle mints — `epic`,
`program`, whatever nesting a project wants) and what each of its
five anchor entries' `flow:` points at (§15.7, §15.9) — never the
anchor names, their count, or their order. A bundle may declare many
named containers (`queues/containers/<name>.yaml`, one file per
name), and any one of them may nest inside any other by naming it in
a `flow:` value (§15.7) — there is no kind registry to check a name
against, because `container:` no longer selects from a closed
platform vocabulary; it names the declaration being authored, the
same way a `gate:` file names its own gate or a `type:` file names
its own work-item type (§15.9) — all three share one registry
namespace.

**Nesting composes, and it is bounded without being counted.**
Declaring `epic` gets epics-and-milestones for free the moment an
`epic` container's own `main` entry's `flow:` names `milestone` — no
second mechanism, because there is only the one container kind and
one field. What is barred, and barred at load rather than left to a
live chain to discover, is a container reaching itself: the
declaration graph over container names, connected by `flow:` edges
whose target resolves to another container, must be acyclic, and a
container naming itself is the degenerate one-node case of the same
check (§13). A `milestone` declaration therefore cannot open
`milestone` — same-*declaration* nesting is refused outright, not
deferred pending a name for it, which resolves §7's open question:
there is no numeral to clash with fan-out `depth:` because nesting is
never counted, only named, and an acyclic declaration graph has a
finite longest path, so a bundle's maximum nesting depth is knowable
from the bundle alone even though the number of *distinct* levels an
author declares is unbounded.

**After a container's `cleanup` resolves, it reaches a fixed terminal
kind — not a further queue name**, the same shape a ticket's own
sequence ends at `terminal` (§15.1) without a workflow bundle
declaring content for `terminal` itself. A project has no equivalent
universal terminal, because it has no universal sequence to end: it
closes when its own last declared queue (whichever the bundle placed
last) resolves with nothing open behind it. **This settles §6's open
question of whether the root container has statuses and what closing
one means:** the root is a project, not a container, so it has
statuses the identical way any project does — its own declared queue
list — and closing it means that list's last entry resolving clean,
same mechanism as any project, merely the outermost and never itself
nested (`docs/v5-design-decisions.md` §7.8).

**No separate "blocked" anchor kind, and none is missing.** A
container or project currently at queue Q with an unresolved blocking
queue (§15.7's `blocks:`) is fully described by "at Q, blocked by
`blocks:`'s target" — derivable from the declared queue graph plus
live ticket state, the identical reasoning that keeps a queue itself
from being stored. Introducing a stored or fixed `blocked` status
here would be exactly the pending-work-on-the-node antipattern v5
§7.11's staleness projection already refuses.

### 15.7 Declaring queues: `queues/project.yaml` and `queues/containers/<name>.yaml`

A project's own sequence, fully authored:

```yaml
# queues/project.yaml
queues:
  - queue: initialization        # any name; array order is declared order
    flow: onboarding              # a registered plain type (§15.9); what
                                  #   actually lands here is business logic, not
                                  #   protocol — see below
  - queue: scaffolding
    flow: seed
  - queue: build-out
    flow: milestone               # names a declared container (§15.6, §15.9)
  - queue: iteration
    flow: milestone
  - queue: maintenance
    flow: maintenance
  - queue: deprecating
    flow: deprecation
  - queue: sunsetting
    flow: sunset
```

A declared container, its array fixed to the five anchor names in
order:

```yaml
# queues/containers/milestone.yaml
container: milestone            # this declaration's name — referenced elsewhere via flow:
queues:
  - queue: setup                 # §15.6's five anchor names, in this order, no more, no fewer
    flow: setup                  # runs once per mint, not once per container (§15.6, §15.8)
  - queue: prep
    flow: feature
  - queue: main
    flow: feature
    blocks: [retro]              # sibling-scoped (§15.8); never a queue nested inside a flow: target
  - queue: retro
    flow: retro
  - queue: cleanup
    flow: tech-debt
```

Each entry's `queue:` name is required on a container (checked
against the fixed set, §13) and optional-but-conventional on a
project (nothing to check it against). `flow:` is required on every
entry, project or container alike, and names a member of the
work-item-type registry (§15.9) — a declared container or a declared
plain type, uniformly; there is no second field for the container
case (§13, superseding this ticket's own earlier `flow:`/`opens:`
pair).

**A queue is a query, never stored** (`docs/v5-design-decisions.md`
§7.8): the unresolved work items in this project or container
assigned to this queue. Nothing writes a per-queue bucket; nothing
reads one back. The identical reason `ready_scopes` itself refuses to
materialize (v5 §1.2) and `Catapult.Engine.Scheduler` holds no memory
of what it last broadcast: a stale bucket is worse than an absent
one, because it is the kind of thing a dispatcher acts on.

**`flow:` resolves against the workflow bundle's own type registry
(§15.9), never against a chain bundle's `flow:` declaration.** No
load-time cross-reference binds the two (§13) — the same non-binding
§11 already holds between every other chain/workflow pairing. A chain
shipping a flow whose own `ticket:` face uses a matching label is
what makes work actually land in this queue once the type opens; that
pairing is authored convention, checked when a ticket of that type
opens (an unrecognized label opens nothing and files `Blocked`/
`needs-setup`, `docs/v5-design-decisions.md` §7.4), not something this
loader validates.

**The residual failure this leaves, named rather than left to be
discovered later:** a workflow bundle can register a type that no
chain bundle's `ticket: labels:` ever claims. That is not a load
error — catching it would reintroduce the cross-axis binding §11
forbids everywhere else — so it degrades to the identical defined
failure an unrecognized label already produces: nothing ever opens
that type. `docs/v5-design-decisions.md` §7.8 records this as the
accepted cost of composability, not a gap left to close.

**`initialization` is autopopulated by business logic, not
protocol.** This grammar declares that the queue exists and, once a
workflow bundle declares its `flow:`, what type it dispatches; *what
actually lands in it* on a fresh project is plane business logic
outside the loader's remit — a scoping line this grammar respects
rather than blurs (`docs/v5-design-decisions.md` §7.8).
`deprecating` and `sunsetting` are ordinary declared queues from the
outset — nothing here defers them to dummy status, since there is no
platform-fixed project sequence left to fill in later.

### 15.8 Blocking, and how a queue dispatches

**One queue may block another, declared, scoped to visible siblings
only.** `blocks:` on a queue names other queues declared in the
*same file* — a container's other four anchor entries, or another
entry in the same `queues/project.yaml` — whose completion it holds
open while this queue still carries unresolved work items — §13
rejects a `blocks:` entry naming a queue in a different declaration,
and rejects one naming a queue nested inside what *this* queue's
`flow:` opens. Reaching into a nested container's own queues would
make that container's internals part of its interface to the level
blocking it, exactly backwards from composability: to block on
something nested, block on the `flow:` entry that opens it, not on
what is inside it. `main` blocking `retro` is the instance that
generalizes what used to be a special case ("the retro can't finish
while milestone work is open") into this one declared relation.

**Dispatch is uniform: every queue entry's `flow:` names a member of
the type registry (§15.9), and what happens next follows from what
that member turns out to be — never from anything the queue entry
itself declares.** A `flow:` resolving to a plain type dispatches an
ordinary ticket of that type: opening a ticket of the declared type
opens a flow instance exactly as any other entry does (v5 §7.10's
"opening a ticket IS opening a flow instance"), with its own gates,
its own children, its own PR. A milestone's `retro` and `prep`
(which dispatches ordinary feature work) are no exception: both are
ordinary work items — "a work item, with its own bundles, dispatched
by machinery that already exists" (`docs/v5-design-decisions.md`
§7.8) — not a reserved agent-step slot the way `boundary` used to be
(§15.1). The chain bundle shipping `retro` and `setup` flows, with
tiers carrying ordinary `delivery:` blocks, is what gives each its
actual agent behavior; nothing in this grammar special-cases either
by name.

**A `flow:` resolving to a declared container mints one instance of
it and starts that instance at its own `setup` entry (§15.6).**
Minting and constituting are necessarily two different declarations —
the parent's queue entry lives in the parent's own file, the newly
minted instance's `setup` entry lives in the child's — so there is
nowhere `flow:` needs to name two things at once, and no "before
`setup`" position to invent: `setup`'s own `flow:` (typically the
`setup` plain type) is what runs `setup`'s actual job — grooming,
setting blockers, filling `prep` — once, at mint, because it is the
*first entry of the newly minted instance's own sequence* rather than
a value stashed on the parent's dispatch entry. The parent's queue
does not complete until the minted instance reaches its terminal kind
(§15.6) — nesting composes through the same completion rule any other
`flow:` queue already uses, because there was never a second
mechanism to begin with.

### 15.9 `types/<name>.yaml` — registering a work-item type

```yaml
# types/feature.yaml
type: feature                    # this declaration's name — what flow: (§15.7)
                                  #   and a chain bundle's own ticket: labels:
                                  #   reference (never a load-time cross-check —
                                  #   see §15.7 and the residual-failure note there)
statuses: [product-review]       # declared gates (§15.2) this type's tickets
                                  #   visit; the system-status skeleton (§15.1)
                                  #   is unconditional and never repeated here
```

**A type is a list of statuses — nothing more, and this is the same
inversion §15.6's container form already made, applied uniformly.**
Today, a type's effective sequence is assembled by *filtering*: each
gate (§15.2) used to carry its own `ticket_types: [feature]`, naming
which types visited it, and a type's sequence was whichever gates
happened to name it, discovered by scanning every gate rather than
read off any one declaration. Registering types inverts the index:
the type names its own gates, `ticket_types:` is retired from
`gates/<gate>.yaml` outright (§15.2), and there is exactly one place
either fact is declared — a gate and a type can no longer disagree
about whether the other applies, because there is only one of the two
facts left to state.

**`statuses:` is a set with array syntax, not a second ordering
mechanism.** Each named gate already carries its own position via its
own `after:` (§15.3); listing gates here says *which* apply to this
type, never *where* — order within the array carries no meaning, and
declaring the same gates in a different order changes nothing. What
does carry meaning is which system statuses (§15.1) a type passes
through, and that part is never declared at all: every type visits
`queue`, `generation`, `checks`, `merge`, `deploy` and `terminal`
unconditionally, the identical skeleton every ticket already has, so
naming them here would repeat a platform-fixed fact rather than
declare one.

**Container declarations and type declarations share one registry and
one namespace** (§13): `queues/containers/<name>.yaml` and
`types/<name>.yaml` both mint entries a queue's `flow:` (§15.7) can
resolve to, a `container:` name and a `type:` name may not collide,
and the loader does not branch on which kind of file produced a
`flow:` target — only on what that target's own declaration contains.
A container's own five anchor entries are exactly this recursive
case: each one's `flow:` is an ordinary reference into the same
registry, and it is *because* the registry is shared that a
container's `main` can point at a plain type (`feature`) while an
`epic`'s `main` points at another container (`milestone`), with no
second mechanism for either.

**No axis tag on a `flow:` value, and none is needed.** An earlier
draft of this grammar considered marking each `flow:` value with the
axis of what it names, to disambiguate a value that might resolve
several ways. That problem doesn't exist once every `flow:` reference
resolves against exactly one registry, on exactly one axis, load-
checked with no unresolvable case — the tag would have solved a
problem this design no longer has.

**This extends v5 §7.16/§7.18's declarable-protocol narrowing, and it
says so rather than leaving the extension implicit** (`docs/
non-goals.md`'s "No per-project restructuring of the automation
protocol" entry, amended alongside this section). Work-item types join
review gates and deployment environments as workflow-bundle content;
the automation graph and the anchor statuses underneath it — system
statuses (§15.1) and container anchors (§15.6) alike — stay
platform-fixed, so the admission rule that entry already states ("a
state may be declared iff no plane logic branches on it") covers this
addition without amendment to the rule itself, only to the list of
things declared under it.
