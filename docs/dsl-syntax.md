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
bundles/<name>/                # kind: workflow — forked from a platform
  bundle.yaml                  #   template, never `extends:`-layered (§11)
  gates/<gate>.yaml            # one file per declared review gate (§15.4)
  environments/<env>.yaml      # one file per deployment environment (§15.4)
  types/<name>.yaml             # one file per declared work item — ticket,
                                #   container or the project itself,
                                #   distinguished by `skeleton:` (§15.1-§15.2)
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

A workflow bundle's manifest carries `kind: workflow`, no `extends:`
field at all (§11 — forked from the platform's default gates,
environments and types instead, never layered), `gates:` /
`environments:` / `types:` globs in place of the chain's lists, and
one further key the chain axis has no counterpart for:

```yaml
name: default-flow
version: "1.0.0"
kind: workflow
gates: [gates/*.yaml]
environments: [environments/*.yaml]
types: [types/*.yaml]
entry: project                    # names the type a fresh project
                                   #   dispatches from (§15.2, §15.6)
```

**`entry:` names the type the plane instantiates when a new project
starts — a fact rootness alone does not answer** (a sixth-pass
addition). §15.6's declaration graph derives which types are
*roots* — nodes nothing else's `flow:` targets — and a bundle
declaring `epic` without ever nesting it under something else has two
of them; roots are not projects, and "the project is a project by
convention" was never a rule the loader could check anything against.
`entry:` is a reference, the identical shape `catapult.yaml` already
has pinning one bundle per axis, not a duplicated fact: it names a
`type:` and the loader checks three things at load — the name
resolves in the loaded union, the resolved declaration carries a
queue-shaped anchor (`container`-skeleton or skeleton-less, §15.6),
and it is a root in the declaration graph (§13). Rootness itself stays
derived, for the acyclicity argument §15.6 makes; only *which* root is
the entry point is declared, once, beside the other bundle-wide facts
`bundle.yaml` already carries.

The file-list keys are per-kind: a `tiers:` list in a workflow bundle
is an unknown field and a load error, per §13, and so is `extends:`
itself on that same manifest.

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

**`argument` is a reserved `fields:` name on a flow's entry tier — the
human-readable case for the work, v5 §7.2 — read by the work surface,
never enforced at load time** (ORC-114). `docs/ui-spec.md` §3.1's
`ticket` screen opens on "the argument, first," and nothing in a
node's `fields` carried prose before this: a tier's own `fields:`
already supports any name the bundle chooses, so `argument` is not new
grammar, only a name the loader now knows to expect at exactly one
place — the tier a flow opens at (`FlowOpened.entry_node_id`) —
without checking that it is there. A type whose entry tier declares no
`argument` renders a blank one on `ticket` rather than failing to
load, the same "declared but absent reads as unset" posture `input.
<role>` and `prior_review` already have; adding a load-time
requirement that every entry tier carry it is a further protocol
change this ticket does not make. `systems/platform_content.md` names
which tiers in the shipped bundle declare it.

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
code. `draft` and `prior_review` are never `context:` entries. `draft`
is supplied automatically to a review tier's prompt alone; `prior_review`
is supplied to every tier's prompt, generation and review alike (§9) —
the same fact, read once per node, rendered wherever it's declared.

**Never named from the workflow axis.** A workflow bundle turns the
critique slot that follows a given generation status *on* by
declaring a `critique` entry next to that `generation` entry in a
type's own `statuses:` array (§15.5) — never by naming a review tier
(`comparch_review`): the declaration references the platform-fixed
status (`critique`) by its fixed vocabulary word, never a bundle's own
tier. Naming a review tier from a workflow declaration is the
identical cross-axis leak §11 already forbids for gates and
generation tiers. **Revised at ORC-92, and the file it revised is
itself retired at ORC-105's fourth pass:** an earlier reading of this
paragraph had the direction backward — critique present by default,
disabled by naming it — which is not what actually happens: no
workflow bundle in this repo declares anything about critique today,
and that silence means "off," not "on and undeclared." §15.5 settles
it explicitly, now as an inline entry rather than a standalone
`critique.yaml` file: absent a `critique` entry next to a given
`generation` entry, no critique tier runs there; declaring one is
what turns it on, at the depth it names.

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
and — review prompts only — `draft`. `feedback` and `prior_review`
render on every prompt a tier has, generation and review alike; `draft`
alone is withheld from generation prompts (`systems/delivery.md`'s
ORC-34 entry pins this against the ambiguity §3.3 leaves). `feedback`
is an ordered list of maps, one per harvested comment — `body`,
`locator` (nullable; always absent before `docs/ui-spec.md` §5's v2
per-sentence anchoring ships), `author_id`, `posted_at`
(`systems/engine.md`'s `CommentPosted`/`CommentFeedback`, ORC-34) —
never a string beside `draft`, the same representational choice
`prior_review` makes below. `prior_review` is a map — `score`,
`findings`, `kind`, `body_sha` — the node's own most recent review
regardless of which draft it landed against (`systems/engine.md`'s
`reviews_for_node/2`, ORC-34); `body_sha` names which committed body
the review applies to, since reading across drafts on purpose means a
prompt can no longer assume it is the current one. Both render blank via Solid's own unset-is-empty
behavior where nothing has been posted or reviewed yet. A variable's
name is its target
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
the per-tier triad invariant. `draft` is supplied automatically by the
shared context-assembly path to a review tier's prompt alone;
`feedback` and `prior_review` are supplied the same way to every
tier's prompt. That a review tier's own declared `context:` matches
the reviewed tier's is a load-time check instead (§3.3, §13).

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

**Chain-axis only, since this ticket's fourth pass.** A chain bundle
naming `extends: <layer>` loads the layer first, then overlays:
declarations union, same-path files replace (v5 §7.10, §9). Cycles in
`extends:` chains are load errors.

**Reversed: a workflow bundle carries no `extends:` field, and there
is no platform workflow base layer left to compose against.** v5
§7.18 originally gave the workflow axis its own base layer, mirroring
the chain axis's `platform-elixir` layer, specifically so a project's
gates and environments could live "in its bundle's `extends:` layer,
versioned in the repo, changed by PR." That reasoning does not survive
contact with how bundles are actually distributed: v5 §3.1 already
chose **fork, tailor, and merge upstream later** as the lifecycle for
bundles and policy packs generally, because git has a merge story hex
does not — and a workflow bundle is exactly this shape, never layered
at runtime by a loader. `bundles/`'s platform workflow content is a
template a project's workflow bundle forks from and tailors, pulling
later platform revisions in by ordinary git merge, the same as any
other forked artifact (v5 §7.8). Declarable review states, deployment
environments and work-item types (§15) are the forked bundle's own
content from the start, never a leaf layer composed onto a base one
at load time. The admission rule this reversal leaves untouched is
v5 §7.16/§7.18's own: a state may be declared iff no plane logic
branches on it — that rule was never about *how* declarable content
reaches a project, only about *what* may be declared, and forking
answers the first question without touching the second.

**A chain bundle's `extends:` may never name a workflow bundle, or
the reverse, because there is no longer a workflow-axis `extends:` to
name.** Naming `extends:` at all inside a workflow bundle is an
unknown field, rejected at load like any other (§13). Layering
composes *content*; it never adds vocabulary — that is §12's job, and
the two mechanisms are deliberately distinct (v5 §9).

**The axes do not reference each other at all. Both reference only
the platform's fixed vocabulary — statuses, queues, agent steps.** A
tier's `delivery:` block (v5 §7.10) names the phase it generates in
and the agent step that generates it, and nothing else; a workflow's
gates and environments attach to those same fixed positions (§15.2).
Neither side can name a declaration belonging to the other, which is
what makes **any chain bundle composable with any workflow bundle** —
no shared gate or environment vocabulary, and no compatibility
contract to check (v5 §7.18). A gate's review set follows from where
it sits: it reviews whatever the chain produced at the step it
follows.

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
- every declared gate or environment entry sits on an edge between
  **skeleton anchors** (§15.1) that exist in the citing type's own
  array, and its exits resolve within the same array (v5 §7.19);
- a **`pending` entry precedes every `generation` and every `deploy`
  entry in the same array**;
- **every `generation` entry has at least one blocked exit** — a
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
  gate, an environment, or a `critique` entry (§15.5) alike, one
  grammar checked the same way at all three sites; any other spelling
  is a load error naming the offending value and the declaration it
  came from (v5 §7.19, ORC-92). The never-validated-against-the-chain
  rule above is unaffected: a pair's two positions are still ceilings,
  never claims checked against the chain's actual fan-out;
- **a `critique` entry must sit immediately after a `generation` entry
  in the same type's `statuses:` array** (§15.5) — no skeleton
  mentioned, and none is needed: a `container`-skeleton type and a
  skeleton-less type have no `generation` anchor to sit after in the
  first place, so this one rule already excludes both without a
  separate skeleton check to duplicate it (a fifth-pass simplification
  — an earlier draft named the excluded skeletons explicitly, which
  said the same thing a second way). A `critique` entry not adjacent
  to a `generation` entry is a load error naming the declaration and
  the position. There is deliberately no `enabled:`
  field anywhere in this grammar: a `generation` entry's mere absence
  of an adjacent `critique` entry already means "does not run" (v5
  §7.19, ORC-92). Neither a gate's, an environment's, nor a
  `critique` entry's `depth:` is read by anything today — scheduling
  is a later consumer (v5 §7.19) — so there is no consumer to
  migrate;
- a gate's forward exit (the next entry in the citing type's own
  array) and its declared escalation policy are well-formed. **A
  gate's own `throwback:`, if declared, must be earlier in the citing
  type's own array** (§15.4, §15.10) — the one load-time check the
  field still needs, now that it names a single landing point rather
  than an allow-list. An *undeclared* decline's target is a runtime
  pick, checked at the command edge against the same "earlier in the
  effective sequence" bound, never load-time bundle content;
- **a `type:` name is unique in the loaded union, whatever `skeleton:`
  it declares or omits** — `container`- and `ticket`-skeleton types
  and skeleton-less types share one namespace (§15.2);
- **every `container`-skeleton type's `statuses:` array holds exactly
  the five platform-fixed anchor names, each exactly once, in exactly
  this order: `setup`, `prep`, `main`, `retro`, `cleanup`, followed by
  `terminal`** (§15.1) — the container analogue of a ticket's system
  statuses, declarable by neither axis for the identical
  re-resolution reason. A missing name, a duplicate, an extra name, or
  the five out of order is a load error naming the declaration and
  the mismatch;
- **every `ticket`-skeleton type's `statuses:` array opens with
  `pending`, closes with `terminal`, and holds `generation`, `checks`,
  `merge` and `deploy` at least once each, in that relative order**
  (§15.1) — `generation` and `merge` may recur; `pending` and
  `terminal` may not. A `ticket`-skeleton array missing one of these
  anchors, or holding one out of its fixed relative order, is a load
  error naming the declaration and the mismatch;
- **there is no `after:` field anywhere in this grammar** — on a
  gate, an environment, or a type's own anchor entries alike, position
  is the array index and nothing else (§15.3). A declaration carrying
  `after:` is an unknown field, rejected at load like any other;
- **a gate whose role has no holders is a load error**, not a runtime
  condition — otherwise a deadlocked gate is indistinguishable from a
  slow reviewer (v5 §7.16). Holders live in identity (Phase 7); until
  that component exists, the loader takes the roster as an opt-in
  input (a `role_holders:` resolver) and skips the check, rather than
  failing every load, when none is supplied — the same shape the
  mirror-mapping check below already has for the same reason;
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
  dead weight: that dialect has no review lifecycle (§12);
- **a workflow bundle carrying an `extends:` field is a load error**
  (§11) — there is no platform workflow base layer left to name.

Added with the unified work-item declaration
(§15.2-§15.9, ORC-105's fourth pass — supersedes the milestone-only
`close/<kind>.yaml` shape ORC-103 drew up on its own unmerged branch,
this same ticket's first draft (a fixed seven-name project sequence
checked against a two-member `container:` registry), its second
(a `flow:`/`opens:` pair on every queue entry), and its third (one
registered type per file, but still three file locations for
`project`, `container` and plain-type declarations); nothing below
has ever loaded, so this is the vocabulary's first landing, not a
revision of one in the loaded union; amended at the fifth pass —
`skeleton:` becomes optional rather than a three-valued field, and the
`review:`/`environment:`/`flow:` restrictions below are corrected to
match; amended again at the sixth — `entry:` (§2) gets a load check of
its own, and the `singleton:` bullet is corrected to bound a queue's
whole lifetime rather than its momentary population):

- **`types/<name>.yaml` is the one declaration shape, directory-shaped
  because a bundle declares more than one** — `type:` names the
  declaration, `skeleton:` optionally selects `ticket` or `container`
  (§15.1; omitted means no anchors), and `statuses:` is the ordered
  array §15.1's per-skeleton checks above and §15.3-§15.5's positional
  checks below both run over. There is one shared registry `flow:`
  resolves against (§15.2), whatever skeleton a given declaration
  picks or omits;
- **a `statuses:` array entry is exactly one of: a skeleton anchor
  (`status:`, from the closed set §15.1 fixes for this declaration's
  own `skeleton:`, or an author-chosen name if `skeleton:` is
  omitted), a gate reference (`review:`, naming a gate declared in the
  loaded union), or an environment reference (`environment:`, naming
  an environment declared in the loaded union)** — an entry carrying
  more than one of these three keys, or none of them, is a load error;
- **a `review:` or `environment:` entry is legal in any type's array,
  whatever `skeleton:` it declares or omits** (a fifth-pass reversal —
  the fourth pass's own load error for a `review:` or `environment:`
  entry in a skeleton-less type's array is retired along with the
  reasoning it was checking: "all review happens at lower levels" was
  never a claim about what a skeleton-less array may contain, only
  about why it needs no re-resolution anchor, §15.2). Critique alone
  stays restricted — see the `container`-and-skeleton-less exclusion
  above;
- **`flow:` and `blocks:` are legal only on a queue-shaped anchor
  entry** — a `status:` entry whose name is one of a `container`-
  skeleton type's five anchors, or any `status:` entry in a
  skeleton-less type's array. `flow:` is required there and absent
  everywhere else; `blocks:` is optional there and absent everywhere
  else. A `review:` or `environment:` entry carrying either is a load
  error, as is a `ticket`-skeleton type's `generation`, `checks`,
  `merge` or `deploy` entry carrying `flow:` — those anchors dispatch
  by chain-side tiers, not by a workflow-declared `flow:`;
- **`flow:` is required on every queue-shaped anchor entry and names a
  member of the type registry above.** This replaces the earlier
  `flow:`/`opens:` pair outright, not merely renames one half of it:
  there is no structural difference, on the entry itself, between
  "this queue dispatches a ticket" and "this queue opens a nested
  instance" for the loader to branch on. What the resolved name turns
  out to be — a `ticket`-skeleton type (dispatch terminates there, an
  ordinary ticket) or a type with a queue-shaped anchor of its own, a
  `container`-skeleton type or a skeleton-less one alike (dispatch
  mints a new instance, §15.8) — is visible only from what the
  *resolved declaration's own* `skeleton:` says (or omits), never from
  anything the queue entry itself declares. **A `flow:` naming a
  skeleton-less type is legal** (a fifth-pass reversal of the fourth
  pass's "nothing nests into a project" load error): a skeleton-less
  type's own array is entirely queue-shaped, exactly the property that
  makes any other type nestable, and refusing it as a target was an
  unstated assumption rather than an argued rule — one the declaration
  graph below needs reversed to catch the cycle it would otherwise
  miss;
- **no cross-axis load-time check binds a queue's `flow:` value to a
  chain bundle's `flow:` declaration of the same name.** The identical
  non-binding §11 already holds between every other chain/workflow
  pairing, unaffected by the registry existing: a chain bundle
  shipping a flow whose `ticket:` face uses a matching label is what
  makes work actually dispatch there once a type opens, but that
  pairing is convention checked at ticket-open time (an unrecognized
  label opens no flow instance and files `Blocked`/`needs-setup`,
  `docs/v5-design-decisions.md` §7.4), never a loader cross-reference.
  The registry adds one guarantee this pairing didn't have before:
  `flow:` itself always resolves, on the workflow axis alone — there
  is no unresolvable reference left inside the workflow bundle's own
  graph, only the (unaffected, unchecked) question of whether the
  chain axis ever claims the name;
- **a `blocks:` entry must name a queue-shaped anchor declared in the
  same type's `statuses:` array** — §15.6's scoping rule made
  mechanical: a queue cannot block something nested inside a different
  queue's own container instances, because that queue's internals are
  not this level's vocabulary to name. A `blocks:` entry naming a
  queue in a different declaration, or naming this queue itself, is a
  load error;
- **the declaration graph — nodes are every type with a queue-shaped
  anchor (a `container`-skeleton type or a skeleton-less one alike),
  edges are `flow:` references between them** — must be acyclic, and a
  type naming itself in one of its own queue-shaped entries' `flow:`
  is rejected outright as the degenerate one-node case of the same
  rule — checked statically, from the loaded bundle alone, before any
  container instance exists. A `flow:` edge whose target resolves to a
  `ticket`-skeleton type takes no part in this graph: a `ticket`-
  skeleton type has no queue-shaped anchor of its own, so it is always
  a leaf and can never sit on a cycle. **The node set is corrected at
  the fifth pass** — the fourth pass's version admitted only
  `container`-skeleton types as nodes, which excluded every edge
  *into* a skeleton-less type by construction (the previous bullet's
  own load error, now reversed) and left a genuine cycle undetected:
  `milestone`'s `main` entry naming `flow: project` and `project`'s
  `build-out` entry naming `flow: milestone` is two nodes and two
  edges under the corrected definition, and a load error; under the
  fourth pass's narrower one, the first edge was never part of the
  graph to begin with, so the cycle went unbuilt and undetected until
  some live chain of instances happened to close it. This is the check
  that actually bars same-name nesting (a `milestone` declaration
  cannot open `milestone`) and bounds nesting depth: an acyclic graph
  has a finite longest path, so the maximum depth a bundle permits is
  knowable from the bundle itself, even though nesting composes
  arbitrarily (as many distinct named levels as the bundle declares).
  There is deliberately **no further, instance-level check** ("no
  container is its own ancestor") — it falls out of the declaration
  graph's acyclicity for free, and building it separately would leave
  unbounded depth *declarable*, caught only when some live chain of
  instances happens to close the loop, trading a load-time failure for
  a mid-flight one (the same trade this project has already made the
  other way: v5 §2.4's "failing at config load beats failing
  mid-flight");
- **a queue-shaped anchor entry may carry `singleton: true`, bounding
  it to at most one work item assigned over its whole lifetime — never
  a second, even once the first has resolved** (§15.7) — legal
  wherever `flow:` is legal, regardless of what the resolved
  declaration's own skeleton turns out to be. This is not a load-time
  cardinality check (assignment history is live ticket state,
  unknowable at load) and is not implied by an anchor's name — `retro`
  and `setup` are singleton by nature but the bundle still has to say
  so, the same way nothing about `main` or `cleanup` is inferred from
  their names either;
- **`entry:` is required on every workflow bundle's `bundle.yaml`
  (§2), and must name a `type:` that resolves in the loaded union,
  carries a queue-shaped anchor, and is a root in the declaration
  graph below** — an absent `entry:`, one naming a `ticket`-skeleton
  type, one that doesn't resolve, or one some other declaration's
  `flow:` targets, is each a load error naming the mismatch. Unlike
  `role_holders:` and `mirror_mapping:` above, there is no later
  component this field waits on — a bundle author writes it the same
  turn they write the type it names — so it takes no opt-in exemption.

Added with sub-arrays (§15.10, ORC-115):

- **a `statuses:` array entry that is itself an array is a sub-array**,
  and every entry inside one is still exactly one of `status:`,
  `review:` or `environment:` — the existing "exactly one of these
  three keys" rule (above) applies unchanged inside a sub-array, and a
  sub-array nested inside a sub-array is a load error naming the
  position (§15.10's own grammar is flat; nesting is explicitly
  undecided, not silently accepted);
- **a sub-array must hold exactly one entry whose `status:` is a
  non-critique agent-balled system status** (`generation`, `retro`,
  `setup` or `merge` — §15.1's `ball` column minus `critique`, which is
  excluded for the same reason §15.5 already excludes it from standing
  alone). Zero such entries or two or more is a load error naming the
  declaration, the sub-array's position, and the count found;
- **a `status:` entry naming a queue-shaped anchor (one carrying
  `flow:` or `blocks:`, §13 above) may not appear inside a sub-array**
  — a load error naming the declaration and the position. Nothing in
  this grammar yet lets a container instance be an agent dispatch
  target on its own (`systems/delivery.md`'s open question), so a
  queue-shaped anchor keeps its existing, ungrouped position whatever
  type declares it;
- **`throwback:`'s own load-time check is unaffected by sub-array
  membership** (third design review, below): whether the citing status
  sits inside a sub-array or not, a declared `throwback:` need only be
  earlier in the citing type's own array — sub-array membership is not
  itself a bound, only a source of the derived default the field may
  override;
- **a `review:` entry inside a sub-array resolves its one-click
  default to that sub-array's own non-critique agent-balled entry** —
  computed, never stored, the identical "derive, never hold" posture
  `ready_scopes` and staleness already take. This is a default action,
  not a bound on legality: the full set of legal targets is
  `docs/v5-design-decisions.md` §7.19's own earlier-prefix rule, the
  same one Blocked-return uses, and the check above only guarantees
  the default itself is unambiguous.

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
entity itself (§15.2), and there is nothing for a proxy ticket to do.
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
(`docs/v5-design-decisions.md` §7.8), which removes the premise: a
scan queue reads the container's own history directly, so nothing
needs to be written down solely so a later pass can find it again.

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

### 15.1 Skeletons — the fixed vocabulary

Platform-fixed, referenced by both bundle axes, declarable by
neither (v5 §7.18, §7.19). They are the anchors everything else —
gates, environments, critique, and a container's own queues —
positions against (§15.2), and the set a blocked work item
re-resolves against when a workflow cutover removes the status it was
parked at (v5 §6, §7.19) — which they can only be because they are
not declarable.

| kind | meaning | ball |
|---|---|---|
| `backlog` | committed to nothing yet | author |
| `pending` | committed, awaiting dispatch capacity | plane |
| `generation` | an agent run producing artifacts | agent |
| `critique` | an agent run reviewing a freshly produced draft | agent |
| `fanout` | children in flight; progress rolls up | plane |
| `checks` | CI running against produced work | world |
| `merge` | reconciliation into the parent branch | agent |
| `deploy` | promotion into a declared environment | world |
| `validating` | post-deploy verification (§7.11) | plane |
| `blocked` | single status, flavor labels, origin kept | varies |
| `stubbed` | waiting on an external timeline, by choice | world |
| `setup` | constitutes a freshly minted container, once (§15.8) | agent |
| `prep` | work a container requires before it opens | varies |
| `main` | the container's own working period | varies |
| `retro` | backward-looking close of a container | agent |
| `cleanup` | work missed during the container's own period | varies |
| `terminal` | shipped / done | — |

`ball` is v5 §7.11's author-owned vs machine-owned distinction, which
drives assignee rendering; `blocked` inherits from the status that
kicked to it.

**Renamed from `queue`, at this ticket's fourth pass.** A single work
item's own wait-for-dispatch status and a container's own named queue
position (§15.2) used to share one word, and once both could appear
in the same declared array (§15.2) the collision stopped being
theoretical. `pending` keeps the fixed-vocabulary meaning exactly —
"committed, awaiting dispatch capacity" — freeing "queue" for the
sense the rest of this section actually needs it in. This is
Catapult-local DSL vocabulary rather than orchestration's protocol
(`internal/protocol/protocol.go`'s `AllStates` has no `queue` member
to rename), so the rename touches this file plus
`lib/catapult/dsl/system_status.ex` and nothing in the two-repo
protocol — recorded as dev's diff against ORC-104, the same way
`:boundary`'s retirement below is, not actioned here.

**A `pending` precedes every `generation` and every `deploy`** — a
load-time check (§13), not a convention. **`stubbed` is exempt from
staleness and escalation** (v5 §7.6): nothing is stale about waiting
deliberately.

Mapping onto v5 §7.6's lifecycles, which are this vocabulary with
every review sequence at length one — feature: `Todo`(pending) →
*Product design*(generation) → **Product review**(review) →
*Architecting*(generation) → **Architecture review**(review) →
`Building`(fanout) → `Reconciling`(merge) → `Merged`(merge) →
`Validating`(validating) → `Shipped`(terminal). Child: `Ready for
dev`(pending) → `In progress`(generation) → `Checks`(checks) →
`Reconciling`(merge) → `Merged`(merge) → `Done`(terminal), with
`Ready for rework`(pending) / `Reworking`(generation) as the repair
loop. The two bolded statuses are the platform workflow layer's
default review declarations, not system statuses — which is what
makes them replaceable.

**Two fixed skeletons, and `skeleton:` is optional — there is no
third value standing for "neither."** A declared work-item type
(§15.2) may select a `skeleton:` of `ticket` or `container`, which
fixes which of the anchors above its `statuses:` array must contain,
each at least once, in the relative order given here — never their
names, their presence, or (bar the exceptions §15.4 and §15.5 name)
how many times each may appear:

- **`ticket`** — `pending`, then any interleaving of `generation`
  (each optionally paired with a `critique` entry, §15.5) and declared
  gates (§15.4), then `checks`, `merge`, `deploy` (optionally paired
  with declared environments, §15.4), then `terminal`. `generation`
  and `merge` may recur — v5 §7.6's own feature lifecycle above
  already visits `generation` twice (*Product design*, *Architecting*)
  and `merge` twice (`Reconciling`, `Merged`) — `pending` and
  `terminal` may not: first and last, exactly once.
- **`container`** — the five names fixed at this ticket's first pass:
  `setup`, `prep`, `main`, `retro`, `cleanup`, each exactly once, in
  exactly this order, then `terminal`. This is the container analogue
  of the ticket skeleton, for the identical re-resolution reason: the
  anchor a container parked mid-sequence falls back to when a
  workflow cutover changes what a queue dispatches underneath it. A
  container currently at `main` stays at `main` across the cutover;
  only which type `main` now dispatches changes.

**A type with no `skeleton:` has no anchors at all** (a fifth-pass
correction: an earlier draft spent a `skeleton: none` value on
exactly the fact the field's own absence already states, which made
"is this the one `none`-skeleton declaration" a bundle-wide fact a
value had to police rather than a structural one the loader could see
for itself, §15.6). Its `statuses:` array is entirely author-declared
queue positions, in whatever order and count the bundle wants, with
no re-resolution anchor to preserve and no fixed relative order to
check. This is the project's shape (§15.2): a project needs no anchor
because all review happens at lower levels and a project changes
shape rarely enough that a workflow cutover mid-project is not the
hazard a cutover mid-container is.

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
(§15.2-§15.8), not one fixed pass; the work that used to hide behind
`boundary` — the retro backward-looking pass and, at a container's own
fanout into a nested one, the forward-looking setup pass
(`docs/v5-design-decisions.md` §7.8) — dispatches as an ordinary flow
instance through a queue's declared `flow:`, the same mechanism as any
other ticket, needing no reserved slot in this closed set.

### 15.2 One work-item declaration: `types/<name>.yaml`

**A container is any work item whose skeleton has queues. A ticket is
any work item whose skeleton has a generation. They are otherwise
interchangeable, and the grammar gives them one declaration shape,
not three** (author review, superseding this ticket's own second
draft, which had already collapsed `flow:`/`opens:` into one field
but still split `queues/project.yaml`, `queues/containers/<name>
.yaml` and `types/<name>.yaml` into three file locations). A
milestone with a `main` queue, then a human sign-off gate, then a
staging deployment, then `retro` is an ordinary sentence this grammar
can say; there is no reason a container should be unable to carry a
gate, or a project a deployment, merely because earlier drafts gave
each shape its own file and its own rules.

```yaml
# types/milestone.yaml
type: milestone                  # this declaration's name — what a
                                  #   flow: value (§15.7) and a chain
                                  #   bundle's own ticket: labels:
                                  #   reference (never a load-time
                                  #   cross-check — see §15.7)
skeleton: container              # ticket | container | omit for none (§15.1)
statuses:                        # every anchor the skeleton fixes,
                                  #   plus whatever else is declared,
                                  #   in array order (§15.3)
  - status: setup
    flow: setup
    singleton: true              # at most one work item, ever (§15.7)
  - status: prep
    flow: feature
  - status: main
    flow: feature
    blocks: [retro]
  - review: ux-review             # a declared gate (§15.4), positioned here
  - status: retro
    flow: retro
    singleton: true
  - status: cleanup
    flow: tech-debt
  - status: terminal
```

```yaml
# types/feature.yaml
type: feature
skeleton: ticket
statuses:
  - status: pending
  - status: generation
  - status: critique               # paired with the generation entry
    depth: 1                       #   directly above it (§15.5)
  - review: product-review
  - status: generation              # a second visit — architecture,
                                    #   after product review
  - review: engineering-review
  - status: checks
  - status: merge
  - environment: staging
    promote_from: dev
  - status: deploy
  - status: terminal
```

```yaml
# types/project.yaml
type: project                    # no skeleton: line — this type has no
                                  #   anchors at all (§15.1)
statuses:
  - status: initialization
    flow: onboarding
  - status: scaffolding
    flow: seed
  - status: build-out
    flow: milestone                # names a declared container (§15.6)
  - review: exec-signoff           # a declared gate (§15.4) — legal here
                                    #   the identical way it's legal on a
                                    #   ticket- or container-skeleton type
  - status: iteration
    flow: milestone
  - status: maintenance
    flow: maintenance
  - status: deprecating
    flow: deprecation
  - status: sunsetting
    flow: sunset
```

**What's real and what was three file formats talking to itself.**
Author review found most of the apparent differences between the
draft's `types/`, `queues/containers/` and `queues/project.yaml`
shapes were artifacts of the split, not facts about queues or
generations. What survives, now expressed as `skeleton:` rather than
as a choice of file:

- **has a queue vs. has a generation** — the governing rule itself,
  and the reason `container` and `ticket` are different `skeleton:`
  values rather than one.
- **the skeleton's own shape** (§15.1) — `pending → generation →
  checks → merge → deploy → terminal` against `setup → prep → main →
  retro → cleanup → terminal` against no fixed shape at all, for a type
  with no `skeleton:`.
- **can source a nesting edge** — only a `container`-skeleton type or a
  type with no `skeleton:` at all has a queue-shaped anchor carrying
  `flow:` (§15.7), so only those can point at another container
  (§15.6); a `ticket`-skeleton type has no queue-shaped anchor at all
  and is always a leaf in the declaration graph.
- **critique's admission** — the one place a `generation` anchor
  (present only on a `ticket`-skeleton type) gates what may be
  declared (§15.5), because critique's depth selects which tiers a
  generation fanned into, and only a `generation` anchor gives it
  something to select within.

Everything else — which file a declaration lived in, and whether its
array was a registered set or a fixed sequence — was the three-shape
split talking to itself, and none of it survives as a rule to check.

**Gates and environments widen onto every type, whatever `skeleton:`
it declares or omits — a fifth-pass reversal of the fourth pass's own
restriction.** The fourth pass's reasoning — "all review happens at
lower levels" (§15.1) is true of the outermost scope, so a project's
array should carry `status:` entries only — mistook an argument for
why a project needs no *re-resolution anchor* for an argument about
what its array may *contain*; those are different claims, and the
governing rule at the top of this section is stated only in terms of
ticket versus container and never mentions the project either way. A
human sign-off between `build-out` and `iteration` (the milestone
example above) is not a strange thing for a project to want, so it is
admitted rather than refused on a premise that was never actually
argued. Critique alone stays refused past this widening, and for a
reason unrelated to the one above: a `generation` anchor is what gives
its depth something to select within, and neither a `container`-
skeleton type nor a skeleton-less one has one (§15.5).

**One registry, one namespace, whatever `skeleton:` a declaration
picks or omits.** `container`- and `ticket`-skeleton types and
skeleton-less types share the identical declaration shape and the
identical registry `flow:` resolves against (§15.7); a `type:` name
may not collide with another, regardless of which skeleton, if any,
either one declares (§13). **Rootness is derived, not declared, and
there is no "at most one" check standing in for it** (a fifth-pass
correction: an earlier draft required exactly one loaded skeleton-less
declaration, a bundle-wide fact a value had to police — "is this the
one" — that the declaration graph already answers structurally). A
root is simply a node nothing else's `flow:` targets (§15.6), derived
the identical way a queue is a query instead of a stored bucket and
ordering is the array index instead of a second field. Nothing stops
a bundle from declaring a second skeleton-less type for some other
outermost-shaped thing, and nothing needs to — a bundle with two roots
is well-formed. **Which root the plane actually dispatches a fresh
project from is a separate fact, named explicitly by `entry:` in
`bundle.yaml` (§2), not derived from rootness at all** (a sixth-pass
correction: an earlier draft of this section called the project "a
project by convention," which named nothing the loader could check —
rootness answers "is this a root," never "which root do I start
from," and those are different questions with a bundle that has more
than one root).

**"Ticket", "container" and "milestone" are what a declaration
contains, not what the grammar calls it.** Nothing in the loader
branches on any of the three words. A type's own former job of naming
the platform-fixed skeleton is now `skeleton:`'s alone, which leaves
"ticket", "container" and "milestone" as descriptions a reader reaches
for because a `ticket`-skeleton type usually holds one generation and
a `container`-skeleton type usually holds queues — never a kind the
grammar itself checks, and never a registry key.

### 15.3 Ordering: the array is the only mechanism

**`after:` is retired, reaching past containers into gates and
environments as they exist today — that is intended.** A gate used to
name its own predecessor (`after: product-review`), and a workflow
bundle's gates formed one chain that a type's `statuses:` filtered by
name (this ticket's third pass); a container's five anchors were
already the one place `after:` was absent, because their order was
fixed and there was nothing left for it to say. Extending the fixed-
array shape to gates and environments removes the field everywhere,
rather than leaving it standing beside a mechanism that has made it
redundant: `after: product-review` and "this entry's position in the
citing type's own `statuses:` array" said the same thing, and a
grammar that lets both say it is a grammar with two ways to disagree
with itself.

**This is a real change in what "the same gate" can mean across
types, not a wash.** The retired model required one order for the
whole bundle — "two review statuses declaring the same `after:` is a
load error" was a check *over the bundle*, because a gate's position
had to hold regardless of which type's `statuses:` cited it in. With
order living on the citing type's own array instead, two types may
cite `product-review` and `engineering-review` in opposite relative
order without either declaration being wrong, because neither one's
array answers to the other's. `gates/<gate>.yaml` and `environments/
<env>.yaml` (§15.4) still declare a gate or an environment once —
role, throwback, escalation, depth, or promotion and lifetime — and
any number of types may cite the same one by name; what moved out of
those files is only the field that used to fix a single global
position, not the fields that describe the review or the deployment
itself.

**Chain-axis position is unaffected — there was never an `after:`
there to retire.** §3's tier declarations position tiers by edges and
context walks, not by a predecessor field; `after:` was workflow-axis
vocabulary from the day it was introduced, and retiring it touches
only the files this section and §15.4 describe.

### 15.4 `gates/<gate>.yaml` and `environments/<env>.yaml`

Named, directory-shaped declarations — a bundle holds several of
each — cited from a type's `statuses:` array (§15.2) wherever the
author wants them to run:

```yaml
# gates/ux-review.yaml
review: ux-review               # status name; unique in the loaded union
role: design                    # who signs off; identity holds the
                                #   holders, bindings the reviewers: map
depth: 1                        # fan-out depth (v5 §7.19); omitted = 0,
                                #   top level only. A maximum, never
                                #   validated against the chain. Also
                                #   accepts [first, rest] — the
                                #   project's first traversal of this
                                #   gate vs. every later one.
escalation: author              # policy; human gates are author-owned
```

```yaml
# environments/staging.yaml
environment: staging
promote_from: dev               # previous environment; omitted = first
depth: 0                        # top level only, the usual case. Also
                                #   accepts [first, rest].
lifetime: persistent            # persistent | per_ticket (per-PR envs,
                                #   which are simply depth 0 + per_ticket)
```

Neither carries `after:` (§15.3): a gate or an environment's position
is wherever a citing type's `statuses:` array places its `review:` or
`environment:` entry, and one declaration may be cited, at different
positions, by more than one type.

Approval is the transition itself (v5 §7.16) — there is no approval
object, and no `approvers:` list. Who approved is answerable from the
log because the plane records the command with its actor.

**No `ticket_types:` field, and none is missing.** A gate used to
carry `ticket_types: [feature]`; that fact is now which types' own
`statuses:` arrays cite it, and there is exactly one place it lives —
the citing type, not the gate.

**`throwback:` survives, narrowed to a single target (ORC-115, third
design review).**

```yaml
# gates/ux-review.yaml
review: ux-review
role: design
depth: 1
escalation: author
throwback: pending               # optional: an explicit landing point,
                                  #   overriding §15.10's derived default
```

A declared *list* of legal decline exits was necessary only while
decline targets were bounded to a per-gate allow-list;
`docs/v5-design-decisions.md` §7.19 and §15.10 below make a gate's
decline and a Blocked-return the same rule regardless of declaration —
any earlier status in the citing type's own effective sequence — so a
list has nothing left to bound, and a bare list also stops meaning
anything once it no longer bounds: naming several targets said "any of
these is legal," and a landing point cannot be several things at once.

What survives is narrower and singular. §15.10's sub-array grouping
gives every gate a *default* landing point — its citing sub-array's own
non-critique agent step — for the ordinary case a decline names no
further choice. `throwback:` is the escape hatch beside that default,
one explicit status, for the gate that wants a different one-click
landing point than the derivation would pick. It names no legality of
its own: whatever it names must already be earlier in the citing type's
own effective sequence, the identical bound §15.10 states for every
decline, declared or not.

**Depth 0 is the rule for a gate, not merely its default** (v5 §7.19,
ORC-92). A gate is a human sign-off, and a human reads the top level;
setting a gate's depth by reasoning about how far the chain fans out
is arguing the auto-reviewer's case inside the human reviewer's own
declaration — that argument belongs to critique's own depth (§15.5),
a separate declaration for exactly this reason, not to a field on a
gate. Declare a gate at a nonzero depth only when the review genuinely
wants a human at every fanned-out node, which is unusual enough that
the file's own comment should say why.

**Endpoints, credentials and hostnames are not on an environment
declaration.** They change only how the plane connects and operates,
so they are bindings — plane entities, queried and picked, never repo
content (v5 §7.10's store test, and §8's BYO constraint: an endpoint
in a bundle breaks hosted onboarding). What lives here is which
environments exist and what promotion into one requires; that changes
what is enforced, so it is graph state, versioned, changed by PR.

### 15.5 `critique` — paired with a peer generation entry

**The one carve-out, and the reason is worth stating rather than
asserting.** A gate is depth 0 on a container the identical way it is
on a ticket — a human reads the top level, whatever the top level
contains — and an environment is the same: neither needs a generation
to mean something, which is why the fifth pass widened both onto
every type regardless of skeleton (§15.2). Critique is different in
kind: its depth *selects which tiers' review runs*, which needs a
generation to select within. **The rule is simply that a `critique`
entry must sit immediately after a `generation` entry** — no skeleton
named, because none needs to be: a `container`-skeleton type and a
skeleton-less type both lack a `generation` anchor to sit after, so
this one positional rule already excludes both, structurally, without
a second check saying so a different way (a fifth-pass
simplification — naming the excluded skeletons explicitly, as an
earlier draft did, said the identical thing twice).

```yaml
  - status: generation
  - status: critique              # must sit immediately after a
    depth: 1                      #   generation entry in the same array
```

**Configures a fixed kind; declares nothing.** `critique` is a system
status (§15.1), not a named, reusable declaration the way a gate or
an environment is — there is exactly one `critique`, and citing it
more than once in a type's array (once per `generation` entry it
should pair with) is the ordinary way to give two generation phases
different depths, not two declarations of the same thing.

**Presence is participation — there is no `enabled:` field.** A
`generation` entry with no adjacent `critique` entry runs no critique
tier at that phase, whatever the chain declares. One that does runs
every review tier the chain declares at that phase, filtered to
`depth:`'s levels, exactly as a gate's own depth filters which levels
see it.

**This is the opt-in reading of v5 §7.19's "a workflow disabling the
critique slot," unchanged by the move from a singular `critique.yaml`
file to an inline array entry.** The file existed because critique's
participation used to be bundle-wide, with nowhere per-type to put
it; now that every type has its own array, per-type participation is
the more precise expression of the same opt-in default, not a new
one. A type whose author wants no critique anywhere simply writes no
`critique` entries — no `enabled:` field, here or anywhere else in
this grammar.

**One spelling wherever a depth appears.** `[first, rest]` means the
same thing on a gate, an environment or here: "first" is the
project's first traversal of the status this depth attaches to —
never the first time a given *ticket* visits it, and never the pass
right after a throwback sends the status back for a repeat visit,
both of which are ordinary later traversals of a status the project
has already been through once (v5 §7.19). A bare integer still means
both positions at once, so no declaration written before this pair
form existed changes meaning.

**Two pairings, two directions — both stated rather than left for a
reader to reconcile.** `critique` sits immediately *after* the
`generation` entry it reviews (above): it reviews a draft that has to
exist first. An environment sits *before* the `deploy` entry it is a
promotion target for (§15.2's `feature` example: `environment: staging`
precedes `status: deploy`): a promotion target has to be configured
before anything can deploy into it. Both are "paired with" a
neighboring anchor in the loose sense that the array puts them next to
each other; neither pairing is a general rule the other one follows —
critique looks backward at what was just produced, deployment looks
forward at what it is about to promote into, and the array records
each exactly where its own direction points.

### 15.6 Nesting, and the declaration graph that bounds it

**Nesting composes, and it is bounded without being counted.** Any
`container`-skeleton or skeleton-less type's queue-shaped anchor may
name another `container`-skeleton or skeleton-less type in its
`flow:` (§15.7) — declaring `epic` gets epics-and-milestones for free
the moment an `epic` type's own `main` entry's `flow:` names
`milestone`, no second mechanism, because there is only the one
shared registry and one field. What varies per declared container is
its **name** and what each of its anchor entries' `flow:` points at —
never the anchor names, their count, or their order (§15.1).

**What is barred, and barred at load rather than left to a live chain
to discover, is a type reaching itself through its own declarations.**
The declaration graph — **nodes are every type with a queue-shaped
anchor, edges are `flow:` references between them** — must be acyclic,
and a type naming itself is the degenerate one-node case of the same
rule (§13). `milestone` cannot open `milestone`. A `flow:` edge whose
target resolves to a `ticket`-skeleton type takes no part in this
graph: a `ticket`-skeleton type has no queue-shaped anchor of its own,
so it is always a leaf.

**The node set has to include skeleton-less types, not only
`container`-skeleton ones — an earlier draft's narrower definition had
a hole.** Restricting nodes to `container`-skeleton types excludes
every edge *into* a skeleton-less type by construction, because such a
type was never a node the graph could contain — which is exactly the
edge a cycle through the project can run on: `milestone`'s `main`
entry naming `flow: project` and `project`'s `build-out` entry naming
`flow: milestone` is a genuine two-node cycle, and the narrower
definition would have let it load, catching it only if some live chain
of instances happened to close the loop. A skeleton-less type's array
is entirely queue-shaped — the identical property that makes a
`container`-skeleton type nestable — so the honest definition of "can
participate in nesting" has to include it, and does.

**This is a load-time check over declarations, not a runtime check
over instances — getting the altitude right took two passes on this
ticket.** The tempting version is "no container may be its own
ancestor," checked as instances mint; it is the wrong tool, because it
leaves unbounded depth *declarable*, caught only when some live chain
of instances happens to close the loop — trading a load-time failure
for a mid-flight one, the identical trade this project has already
made the other way (v5 §2.4: failing at config load beats failing
mid-flight). The declaration-graph check is also what bars same-name
nesting and bounds depth without counting it: an acyclic graph has a
finite longest path, so a bundle's maximum nesting depth is knowable
from the bundle alone, even though the number of distinct named
levels an author declares is unbounded. No further instance-level
check is needed — it falls out of the declaration graph's acyclicity
for free.

**Rootness is derived, not declared, and acyclicity already guarantees
at least one.** A root is simply a node nothing else's `flow:`
targets — there is no load check requiring exactly one, because a
finite acyclic graph always has at least one node with no incoming
edge, so "zero roots" is structurally impossible and there is nothing
for a check to guard against. There can be more than one: a bundle
declaring `epic` without ever nesting it under something else adds a
second root, and that is legal. **Which root is the plane's actual
starting point is a different question from rootness, and this
section does not answer it** — that is `entry:` in `bundle.yaml`
(§2), a declared reference checked against this graph rather than a
fact the graph produces on its own.

**After a container-skeleton instance's `cleanup` resolves, it
reaches a fixed `terminal` kind — not a further queue name** (§15.1).
A skeleton-less instance has no such universal terminal, because it
has no universal sequence to end: it closes when its own last declared
entry resolves with nothing open behind it. This is also the outermost
project's own closing condition when nothing else's `flow:` names it —
closing it means that list's last entry resolving clean, the same
mechanism as any other skeleton-less declaration. A skeleton-less type
that some container's `flow:` *does* nest, unlike the project, closes
this same way from its own array's perspective and is additionally
awaited by its parent's queue the identical way a nested container
is — nesting composes through one completion rule regardless of which
kind of type sources or targets the edge (§15.7).

**No separate "blocked" anchor kind, and none is missing.** A
container or project currently at queue Q with an unresolved blocking
queue (§15.7's `blocks:`) is fully described by "at Q, blocked by
`blocks:`'s target" — derivable from the declared queue graph plus
live ticket state, the identical reasoning that keeps a queue itself
from being stored. Introducing a stored or fixed `blocked` status
here would be exactly the pending-work-on-the-node antipattern v5
§7.11's staleness projection already refuses.

### 15.7 Queues, dispatch, and blocking

A queue-shaped anchor entry — any `status:` entry belonging to a
`container`-skeleton type's array, or any `status:` entry in a
skeleton-less type's array — carries `flow:`, required, naming a
member of the type registry (§15.2):

```yaml
  - status: main
    flow: feature
    blocks: [retro]
  - status: retro
    flow: retro
    singleton: true       # at most one work item, ever (§15.7)
```

**A queue is a query, never stored** (`docs/v5-design-decisions.md`
§7.8): the unresolved work items in this container or project
assigned to this queue. Nothing writes a per-queue bucket; nothing
reads one back. The identical reason `ready_scopes` itself refuses to
materialize (v5 §1.2) and `Catapult.Engine.Scheduler` holds no memory
of what it last broadcast: a stale bucket is worse than an absent
one, because it is the kind of thing a dispatcher acts on.

**`singleton:` bounds assignment over the queue's whole lifetime, not
the query's momentary population — a sixth-pass correction of the
pass that introduced it.** The bound is not "0 or 1 unresolved right
now"; it is **at most one work item ever assigned, and exactly one
once populated.** The distinction is not cosmetic: a queue is a query
over *unresolved* work, so once a singleton queue's one work item
reaches `terminal` the query is empty again — a population-scoped
bound would treat that emptiness as room for a second assignment, and
it is not room, it is closure. `retro` is the motivating case — a
single work item moving through a flow once, not a succession of
them, ever — and `setup` is the same shape; declaring it gives the
plane something to code against, addressing *the* retro work item
directly, and lets it stay closed once that work item is done rather
than reopening to a second one. It is declared per entry, not implied
by an anchor's name: `retro` and `setup` are singleton by nature, but
reading that off the name would make it another platform-fixed fact
about anchors, which is what this section has spent four passes
removing — a bundle declares it, the same way it declares everything
else about what an anchor points at.

**This does not reintroduce stored state.** "Has anything ever been
assigned to this queue" is answerable from the same work-item records
the query itself reads, with the resolution filter dropped — a Done
work item is invisible to the queue-as-query (§15.7 above) but not to
the ticket store it is one of, so the singleton check is one fewer
predicate over the same table, not a new bucket written and read
back. The bound cannot be a load-time check regardless — assignment
history is live ticket state, unknowable at load — so, as with the
query itself, the loader's job stops at accepting the field (§13);
**a second assignment, ever, is a loud error**, not an admitted
dispatch that files `Blocked` the way an unrecognized `flow:` label
does. A silent-refusal concern was the reason an earlier draft chose
admit-and-`Blocked`, and it is real, but the answer is a scoping line
rather than a protocol concession: what happens to the rejected
work's own content is business logic outside the loader's remit, the
identical line this section already draws for `initialization`
(below) — not something the grammar needs to decide by widening what
"singleton" means.

**One property is the point of the field, not an edge case to
special-case around: once a singleton queue's sole work item is
`terminal`, that queue is permanently closed to new work.** A pass
reading "loud error on a second assignment" without this stated might
be tempted to add an escape hatch for it later; there is none to add,
because a closed singleton queue is what the declaration asked for.

**This composes with §15.8's two ways a container's position moves
backward rather than needing a third.** §15.8 already allows a
resolved queue to un-resolve when its population refills, or a cited
gate to throw an entry back. Under a lifetime bound, the only way a
singleton queue can ever un-resolve is **its own one work item going
backward** — reopened, or thrown back through a gate it cites — never
a second item arriving, because there is never a second item. "If you
need to go back through a singleton queue, you move the work item
that is already there" falls out of the two rules together and needs
no separate statement here.

`singleton:` applies uniformly whether `flow:` resolves to a
`ticket`-skeleton type or one with a queue-shaped anchor of its own: a
singleton queue naming a container-shaped type is exactly "this
container has one child instance, ever," no second mechanism.

**`flow:` resolves against the workflow bundle's own type registry,
never against a chain bundle's `flow:` declaration.** No load-time
cross-reference binds the two (§13) — the same non-binding §11
already holds between every other chain/workflow pairing. A chain
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

**Dispatch is uniform: what happens next follows from what the
resolved declaration turns out to be — never from anything the queue
entry itself declares.** A `flow:` resolving to a `ticket`-skeleton
type dispatches an ordinary ticket: opening a ticket of the declared
type opens a flow instance exactly as any other entry does (v5
§7.10's "opening a ticket IS opening a flow instance"), with its own
gates, its own children, its own PR. A `flow:` resolving to a type
with a queue-shaped anchor of its own — a `container`-skeleton type or
a skeleton-less one alike — mints one instance of it (§15.8); the
parent's queue does not complete until the minted instance closes
(reaches its own `terminal`, for a `container`-skeleton instance, or
resolves its own last declared entry with nothing open behind it, for
a skeleton-less one, §15.6) — nesting composes through the same
completion rule any other `flow:` queue already uses, because there
was never a second mechanism to begin with. A milestone's `retro` and
`prep`
(which dispatches ordinary feature work) are no exception: both are
ordinary work items — "a work item, with its own bundles, dispatched
by machinery that already exists" (`docs/v5-design-decisions.md`
§7.8) — not a reserved agent-step slot the way `boundary` used to be
(§15.1). The chain bundle shipping `retro` and `setup` flows, with
tiers carrying ordinary `delivery:` blocks, is what gives each its
actual agent behavior; nothing in this grammar special-cases either
by name.

**One queue may block another, declared, scoped to visible siblings
only.** `blocks:` on a queue names other queues declared in the same
array — a container's other anchor entries, or another entry in the
same skeleton-less project's array — whose completion it holds open
while this queue still carries unresolved work items; §13 rejects a
`blocks:` entry naming a queue in a different declaration, and rejects
one naming a queue nested inside what *this* queue's `flow:` opens.
Reaching into a nested container's own queues would make that
container's internals part of its interface to the level blocking it,
exactly backwards from composability: to block on something nested,
block on the `flow:` entry that opens it, not on what is inside it.
`main` blocking `retro` is the instance that generalizes what used to
be a special case ("the retro can't finish while milestone work is
open") into this one declared relation.

**`initialization` is autopopulated by business logic, not
protocol.** This grammar declares that the queue exists and, once a
workflow bundle declares its `flow:`, what type it dispatches; *what
actually lands in it* on a fresh project is plane business logic
outside the loader's remit — a scoping line this grammar respects
rather than blurs (`docs/v5-design-decisions.md` §7.8).
`deprecating` and `sunsetting` are ordinary declared queues from the
outset — nothing here defers them to dummy status, since a
skeleton-less project has no platform-fixed sequence to promote them
out of later.

### 15.8 Mint vs. activation

**A container instance exists before its `setup` runs, and a
container's own position measures which instance is *active*, not
which instances exist.** Work gets scheduled into a milestone long
before that milestone opens — grooming the next milestone's `prep`
during the current milestone's own `main` is exactly the kind of
thing this design wants to allow — so an instance's existence cannot
hinge on a step internal to it. Two sentences in earlier drafts of
this ticket said otherwise and both are wrong: "dispatch mints one
instance and starts that instance at its own `setup` entry" and
"minted one at a time as the prior one closes" both make existence
and activation the same event; they are not.

**Mint creates an instance; a parent's queue reaching it is what
activates it.** A `flow:` resolving to a type with a queue-shaped
anchor of its own — `container`-skeleton, or skeleton-less (§15.7) —
mints an instance as soon as something creates it — business logic,
or a person — and that instance accepts work into its own future
queues immediately. The parent's own queue position determines
only which minted instance is *current*; `setup`'s own `flow:`
(§15.1, §15.7) dispatches once an instance becomes current, not once
it is minted, which is what makes "runs once, at activation" true
without leaning on mint timing. Minting and constituting were always
necessarily two different declarations — the parent's queue entry
lives in the parent's own file, the newly minted instance's `setup`
entry lives in the child's — so there was never a "before `setup`"
position to invent in the first place.

**There are two ways a container's position moves backward, not one —
an earlier draft claimed the narrower rule on a premise this same
ticket's own fifth pass reversed.** The first, and the one that needs
no gate at all: §15.7's queue is a query — the unresolved work items
assigned to it — so a resolved queue un-resolves the moment its
population refills, with no separate "container went backward" event
to define. An already-active instance re-visiting `prep` after new
prep work appears is this rule in action. The second: a gate a
container-skeleton or skeleton-less type's own array cites can throw
back to an earlier entry in that same array (§15.4's `throwback:`,
resolving within "the citing type's own array" exactly as it does on a
ticket), and a container's array can cite gates now that gates and
environments widen onto it (§15.2) — a milestone sign-off gate between
`main` and `retro` rejecting back to `main` is an ordinary throwback,
not a mechanism the container form lacks. **Neither needs a
throwback-shaped argument for `setup`'s own position**, which the
earlier, narrower draft of this section had reached for: `setup` is
first in the minted instance's own sequence because minting and
constituting are necessarily two different declarations (above), not
because a container has no gates to throw back with — it does, now.

### 15.9 The declarable-protocol narrowing, continued

Work-item types, together with gates, environments and critique's own
participation, are workflow-bundle content (`docs/non-goals.md`'s "No
per-project restructuring of the automation protocol" entry, amended
at this ticket's third pass and unchanged by the unification above):
the automation graph and the anchor statuses underneath it — the
ticket and container skeletons alike (§15.1) — stay platform-fixed,
so the admission rule that entry already states ("a state may be
declared iff no plane logic branches on it") covers this section's
single declaration shape without needing to change again: nothing
here grows what is declarable past what the third pass already
recorded, only how it is spelled.

**The fifth pass grows nothing here either.** Gates and environments
widening onto a skeleton-less type's array, `skeleton:` becoming
optional instead of three-valued, and `singleton:` on a queue-shaped
anchor entry are all changes in *where* an already-declarable fact may
be cited or *how* it is spelled — a gate was already workflow-bundle
content before a project's array could cite one, and `singleton:` is
cardinality metadata a queue-shaped entry carries the same way a gate
carries `depth:`, not a new kind of state. No plane logic branches on
any of the three, so none of them argues with the entry above the way
the third pass's type registry did.

**Nor does the sixth.** `entry:` in `bundle.yaml` (§2) is a reference
to an already-declared type, the identical shape `catapult.yaml`'s own
`chain:`/`workflow:` pins already have — it names which already-
declarable root the plane starts from, adding no new declarable fact
about the automation graph itself. The `singleton:` correction changes
what a lifetime bound means and what the dispatcher does about it, not
what a bundle may declare: the field existed at the fifth pass, and
this pass fixes its semantics rather than widening its surface.

### 15.10 Sub-arrays — grouping a gate around its own agent step

**A `statuses:` array entry may itself be an array — a bare, unnamed
sub-array grouping a contiguous run of the entries §15.2 already
allows anywhere in the array** (ORC-115, design pass; `docs/non-goals
.md`'s "No per-project restructuring of the automation protocol" entry
gains a paragraph recording why this does not extend it further, the
same conclusion the fourth ORC-105 pass reached for array position
itself, §15.9 — see below). Nothing new is declarable inside one: an entry inside a
sub-array is still exactly one of `status:`, `review:` or
`environment:` (§13's existing rule, unchanged), and a sub-array
carries no key of its own — no `name:`, no `id:`, nothing a later
declaration or a cutover could reference. The addition is structural
only: a way to say *these entries resolve together* instead of merely
sitting at adjacent array indices.

```yaml
statuses:
  - status: pending
  - - status: generation
    - status: critique
      depth: 1
    - review: ux-review
    - review: engineering-review
  - status: checks
  - status: merge
  - environment: staging
  - status: deploy
  - status: terminal
```

**Legal wherever a `review:` or `environment:` entry is already legal
— every type's array, whatever `skeleton:` it declares or omits
(§15.2's fifth-pass widening) — but only a `ticket`-skeleton type has
anything worth grouping today.** A queue-shaped anchor entry
(`flow:`, `blocks:`) may not appear inside a sub-array — a load error,
stated separately below — so a `container`-skeleton or skeleton-less
type's array, whose only non-queue-shaped entries are gates and
environments, can form a sub-array holding nothing but those, which
groups nothing a bare array position didn't already say. This is
deliberate rather than an oversight: letting a queue-shaped anchor
sit inside a sub-array is exactly the "singleton flows retire into
sub-arrays of their parent container" direction below, and it is not
decided here (open, see below) — the grammar this section fixes is
narrower than the direction it opens.

**Exactly one non-critique agent-balled entry per sub-array — a
load-time check, and the fact the whole derivation below rests on.**
§15.1's `ball` column already marks `generation`, `critique`, `retro`,
`setup` and `merge` as agent-balled; critique is excluded here because
it reviews a generation rather than standing as one, the identical
exclusion §15.5 already draws for a different purpose. A sub-array
holding zero such entries has nothing for a throwback to fall back to
and nothing worth grouping (a load error); one holding two or more —
a `generation` and a `merge` grouped together, say — has no
unambiguous anchor between them, and rather than inventing a
tie-break rule for a shape the default bundle never needs, it is
refused at load, the same posture `container` and `ticket`-skeleton
mismatches already get (§13). Revisit condition: a real bundle need
for a multi-agent-step group, at which point the tie-break is decided
against that actual shape rather than guessed at now.

**Default throwback falls back to the sub-array's own non-critique
agent step, never to the array position immediately before the
gate.** This is the reading that survives ORC-104's own milestone
shape, `[milestone-signoff, retro, proposals-read]` (§15.2's
`milestone.yaml` example) — a `review:` entry's position in the flat
array is not a reliable proxy for "what it reopens" the moment a gate
sits *after* the group's own agent step rather than before it.
`proposals-read` declining falls back to `retro` (the group's one
non-critique agent step), not to `milestone-signoff` (the array
position immediately before it) — the latter would re-ask the author
a question they already answered instead of re-running the agent that
produced the thing they're declining. A gate declaring no `throwback:`
of its own now resolves to this derivation rather than being an
outstanding declaration gap; §15.4's `throwback:` field is unaffected
in shape and stays legal wherever it already was.

**The worked example is the post-retirement shape, not today's
grammar, and says so here rather than leaving the next reader to
check.** `bundles/default-flow/types/milestone.yaml` cites `retro` as
a `flow:`-carrying, container-skeleton anchor today (`types/retro.yaml`
runs its own singleton flow), and the load-time check above refuses a
queue-shaped anchor inside a sub-array — so `[milestone-signoff, retro,
proposals-read]` cannot legally form a sub-array until "singleton flows
retire into sub-arrays of their parent container" (below) actually
lands. The reasoning holds regardless: it argues from the *shape* ORC-104
already committed to in prose, not from a sub-array the loader accepts
today. One consequence worth naming plainly: no sub-array the default
bundle can legally form *today* distinguishes this rule from a naive
first-element one, since `types/feature.yaml`'s own group
(`generation`, `critique`, `ux-review`, `engineering-review`) has
`generation` as both the sub-array's one non-critique agent step and
its first entry. The rule ships correct but unexercised by the shipped
bundle until the milestone retirement lands.

**Second design review: the declared list never bounded anything.**
The pass this section originally shipped held
`throwback:` unaffected in reach — a declared, non-empty list stays
the only legal decline targets, and the derivation only fills the
*empty*-list gap. That reading rested on a specific factual claim, and
the claim is false: `lib/catapult/engine/commands/decline_gate.ex`'s
own moduledoc states plainly that `gate`/`throwback_to` membership "is
the command edge's to check... not the aggregate's," and the command
edge is dev's unbuilt LiveView (`systems/delivery.md`'s Phase 7). There
is no shipped enforcement of a declared allow-list to preserve, so the
question is an ordinary design decision, not a fact this pass could
get right or wrong by reading code. **The author's decision, recorded
here: a human may move a ticket anywhere that would not break the
pipeline, and the only thing that breaks is tier ordering — a
decline's target is bounded by "an earlier status in this ticket's
effective sequence," the identical rule `docs/v5-design-decisions.md`
§7.19 already gives Blocked-return, and nothing narrower.** This is
not a new check invented for the occasion: `Catapult.Dsl.Workflow
.gate_throwback_problems/2` already computes exactly this — `target in
(type.statuses |> Enum.take(index))` — for a *declared* `throwback:`
value at load time. The decision generalizes the bound already shipped
there to every runtime pick, declared or not: one predicate, in one
place, instead of a load-time check and a separate runtime allow-list
that happened to agree.

**Third design review: `throwback:` keeps its second job — naming a
landing point — and narrows from a list to a single target, rather
than retiring.** The pass immediately above retired the field outright
on the reasoning that a declared list served exactly one purpose
(bounding legality) and that purpose was gone. The premise is right and
the conclusion overreaches: `throwback:` did two jobs, not one.
Bounding legality is the job that is gone, and stays gone — every
target the field could ever name is, by construction, earlier in the
array, which is now legal regardless of declaration. But the field
also *named where a decline lands*, and that job is untouched by the
widening: it is exactly what an escape hatch is for. The derivation
above supplies a *default* landing point — the citing sub-array's own
non-critique agent step — and `throwback:` is what a gate declares
instead of that default, for the gate that wants a different one.

A list stops meaning anything the moment it stops bounding: naming
several targets said "any of these is a legal exit," a claim about
legality. A landing point is not a set — a decline lands on exactly one
status — so the field narrows to a single optional target rather than
disappearing. `Catapult.Dsl.Gate`'s `throwback: [String.t()]` narrows
to `throwback: String.t() | nil`, and `Catapult.Dsl.Workflow
.gate_throwback_problems/2`'s `for target <- gate.throwback` narrows to
one membership check against the same "earlier in the citing type's
own array" bound it already computes — dev's diff against this record,
not this pass's to make. `docs/v5-design-decisions.md` §4.5's
escape-hatch discipline — "an escape hatch that accretes special cases
becomes N more mechanisms" — is why the field stops at *one* override
rather than growing back into per-target routing: a single explicit
status, no per-use kinds, no second derivation rule beside the
sub-array default.

**The day-one test still matters, restated for a default rather than a
bound: if the default bundle needs the field to reach a *different*
landing point than the derivation would pick, that is the field doing
its job; if it needs the field only to restate a target already
reachable, that declaration is redundant and worth dropping.** Under
the widened legality rule, the retro case that motivated this whole
section resolves with no declaration at all — the derivation is right
about the ordinary case. The two real default-bundle gates that
declare `throwback:` today are read against the sharper test, not
waved through:

- `ux-review`'s own declared `throwback: [pending]` (`bundles/
  default-flow/gates/ux-review.yaml`) names a target *outside*
  `ux-review`'s own sub-array, before the group entirely — and a
  *different* landing point than the derivation would pick, which is
  `generation`, the group's own non-critique agent step. This
  declaration is the field earning its keep: `pending` means reject all
  the way back to before generation ever ran, not merely re-run
  generation, and only an explicit declaration can say that. Narrowed
  to a single target, this file is unaffected — it already named one.
- `engineering-review`'s own declared `throwback: [generation,
  ux-review]` (`bundles/default-flow/gates/engineering-review.yaml`)
  sits entirely inside the group the derivation covers. Its first
  element, `generation`, already *is* the derived default, so declaring
  it is redundant. Its second element, `ux-review`, is a genuine second
  landing point a single-valued field can no longer express at once —
  the list-to-scalar narrowing forces this file to keep one and drop
  the other. Both remain legal targets either way (the earlier-prefix
  rule reaches both regardless of declaration); which one stays the
  declared *default* is an ordinary bundle-authoring call against
  `bundles/**`, not a fact this record needs to settle for it.

Narrowing both files' `throwback:` to a single string, and dropping
`engineering-review`'s now-redundant second element, is dev's diff
against this record (`bundles/**`); neither file loses a landing point
a decliner can still reach.

**Throwback reopens the whole sub-array — the all-reopen rule
(`docs/v5-design-decisions.md` §7.19) is now definitional, not
prose.** Falling back to the group's own non-critique agent step *is*
"reopen everything downstream of the regeneration," restated
structurally: there is no entry between the fallback point and any
gate later in the same sub-array that the reopen could leave standing,
because the fallback point is the earliest entry the group has. This
is what closes v5 §7.19's own observation that the all-reopen rule was
written as a description nothing enforced — a passed gate re-checked
against a sub-array whose own agent step regenerated is exactly
§7.11's staleness-is-derived machinery running over a structural
boundary instead of an implied one.

**This also answers `docs/v5-design-decisions.md` §7.16's open item,
"what a passed gate pins."** A gate's citing sub-array has exactly one
non-critique agent step (the check above), so what the gate approves
is that step's own committed content, read at the gate's own declared
`depth:` — the identical node set `critique`'s own depth already
selects among when a critique entry sits in the same group (§15.5),
generalized from "review this generation" to "this gate approves
this generation." Staleness for the gate becomes the same derived
join a review tier's 1:1 pin already uses (§7.16, ORC-84/ORC-6): the
gate is stale exactly when the pinned node's own committed content has
moved past what the gate's approval event recorded, answerable from
the log rather than a stored field. Nothing here builds that join —
declared workflow gates are still `systems/delivery.md`'s Phase 7 to
build at all — this section only gives that future build a structural
node to pin against, where before there was none.

**Backward movement is one rule with one target test, not two.**
`docs/v5-design-decisions.md` §7.19's "a throwback from a review and an
unblock to an earlier status are the same movement" was written about
reopen scope, and that reading is correct and unchanged — "both reopen
everything downstream" is the entire content of "the same movement."
But the two entry points also share what counts as a legal target,
which the section's first pass got wrong by trusting a shipped-
behavior claim that did not hold (above: `DeclineGate` enforces no such
list; the command edge that would does not exist yet). A gate's
decline and a Blocked-return both resolve against the identical
"earlier in the effective sequence" test; they differ only in their
*default* — a throwback's one-click default is the citing sub-array's
own non-critique agent step (this section), a Blocked-return's is the
tracked origin status (§7.19) — and in nothing else, except that a
gate's default may itself be overridden by an explicitly declared
`throwback:` (§15.4, above); Blocked-return has no analogous override,
since nothing groups it the way a sub-array groups a gate.
`docs/ui-spec.md`'s J2, J4 and its `ticket`-screen gate-action bullet
are corrected to match.

**Not decided here, left open:**

- **Nested sub-arrays.** This section's own grammar is flat — a
  sub-array's entries are `status:`/`review:`/`environment:` only,
  never a further array. `container`-skeleton nesting (§15.6) already
  established arbitrary nesting for a different axis, and two nesting
  concepts that look alike and are not is the homonym hazard that
  axis's own open questions already warn about. Throwback would
  compose readably if this were allowed (fall back within the
  innermost), but that is an argument for revisiting, not a decision
  made now.
- **A queue-shaped anchor inside a sub-array**, which is what
  "singleton flows retire into sub-arrays of their parent container"
  (below) would actually require. Refused at load for now (above), not
  because the direction is wrong but because it reaches machinery this
  pass does not touch: whether a container instance can be an agent
  dispatch target at all is `systems/delivery.md`'s open question,
  named there rather than answered here.
- **A throwback from a gate sitting after a sub-array, targeting into
  it.** This section fixes the default for a gate *inside* a group; a
  gate outside every sub-array throwing back into one is a different
  case this section does not address (the general "earlier in the
  effective sequence" legality test covers it regardless — what's
  undecided is only whether such a gate gets a derived default of its
  own, or must always be explicit).
- **Whether a sub-array is a visible grouping or flattens for
  display.** `board`'s lanes read the effective sequence left to right
  (`docs/ui-spec.md` §3.1); this is a real UI decision this section
  creates and does not answer.
- **Whether the `pending`-precedes-`generation`/`deploy` check (§13)
  needs a sub-array of its own head.** Settled, not left open: it does
  not. The check reads the citing type's array flattened one level —
  a `pending` entry anywhere earlier than a `generation`, sub-array
  membership aside, satisfies it exactly as today, because grouping
  changes throwback derivation and reopen scope and nothing else about
  the fixed skeleton's own shape (§15.1's table loses no entry to this
  section, only a second job — see below).

**§15.1's fixed vocabulary loses a job here, not an entry.** Before
this section, a gate's declared `throwback:` bounded legality against
its own declared list, which made a declared list load-bearing rather
than optional. After it, the vocabulary's re-resolution role (§15.1's
own opening paragraph, and §7.19's cutover-survival rule) is untouched
— every anchor this section discusses still exists, still fixed, still
undeclarable — while its *legality-bounding* role retires: what a
decline may target is now "earlier in the citing type's own effective
sequence," full stop, never a bound stated in terms of a per-gate
declared list. This is a narrower claim than it once was: `throwback:`
itself survives (§15.4, above), narrowed to a single override on the
*default landing point* a decline picks — a different job from
bounding legality, and untouched by this paragraph.

**`docs/v5-design-decisions.md` §7.8's own "Two agents, dispatched as
ordinary work items" passage is amended by this section, in the
document that records it, not only here**: the direction that a
milestone's `setup` and `retro` singleton flows fold into sub-arrays
of `milestone`'s own array rather than remaining separately dispatched
ticket-skeleton types is recorded there, alongside what stays
undecided about it.
