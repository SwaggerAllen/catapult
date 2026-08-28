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
  effort: max                     # effort hint
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

Anatomy: `self`, `self.parent`,
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

Deliberately not Turing-complete. Six
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
grammar is platform-wide and the same
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
- a **`pending` entry precedes every generation-shaped entry
  (`generation`, `design` or `architecture`, §15.1) and every
  `deploy` entry in the same array**;
- **every generation-shaped entry has at least one blocked exit** — a
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
- **a `critique` entry must sit immediately after a generation-shaped
  entry (`generation`, `design` or `architecture`, §15.1) in the same
  type's `statuses:` array** (§15.5) — no skeleton mentioned, and none
  is needed: whether a given array has a generation-shaped entry for a
  `critique` to pair with is a fact about that array's own contents,
  never about which skeleton, if any, the citing type declares (a
  fifth-pass simplification, corrected again at ORC-148 for the
  identical reason — see below — rather than reintroducing the
  skeleton check either correction retired). A `critique` entry not
  adjacent to a generation-shaped entry is a load error naming the
  declaration and the position. There is deliberately no `enabled:`
  field anywhere in this grammar: a generation-shaped entry's mere
  absence of an adjacent `critique` entry already means "does not run"
  (v5 §7.19, ORC-92). Neither a gate's, an environment's, nor a
  `critique` entry's `depth:` is read by anything today — scheduling
  is a later consumer (v5 §7.19) — so there is no consumer to migrate.
  **The fifth pass's own reasoning here — "a `container`-skeleton type
  and a skeleton-less type have no generation-shaped anchor to sit
  after in the first place" — stopped being true the moment ORC-148
  let any type's array hold one regardless of skeleton (§15.2); the
  rule itself needed no change, since it was never actually keyed to
  skeleton, only the sentence explaining why skeleton needed no
  separate mention did;**
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
  `pending`, closes with `terminal`, and holds at least one
  generation-shaped entry (`generation`, `design` or `architecture`,
  §15.1, in any combination), `checks`, `merge` and `deploy` at least
  once each, in that relative order** (§15.1) — a generation-shaped
  entry and `merge` may recur, in any mix of the three generation-shaped
  names; `pending` and `terminal` may not. A `ticket`-skeleton array
  missing every generation-shaped kind, missing `checks`, `merge` or
  `deploy`, or holding one out of its fixed relative order, is a load
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
whole lifetime rather than its momentary population; amended again at
the seventh, ORC-148 — the `flow:`/`blocks:` restriction below drops
its coupling to the citing type's own `skeleton:` in favor of the
entry's own name, the declaration-graph and `entry:` bullets are
corrected to match, and the `singleton:` bullet named above is retired
outright rather than corrected again, §15.7 having removed the
cardinality it bounded):

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
- **`flow:` and `blocks:` are legal on a population anchor — a
  `status:` entry named `prep`, `main` or `cleanup`, or any `status:`
  entry in a skeleton-less type's array — never on `pending`,
  `generation`, `design`, `architecture`, `critique`, `checks`,
  `merge`, `deploy`, `setup`, `retro` or `terminal`, whatever type's
  array cites them** (a seventh-pass reversal, ORC-148: the fourth
  pass's own coupling to
  the citing type's `skeleton:` is retired along with the sentence it
  read from, §15.2). A population anchor names an open population of
  child work — the query §15.7 describes — so it always needs a
  `flow:` naming what fills it; the other nine kinds each dispatch by
  a fixed mechanism of their own (a chain-side tier, the world, a
  promotion, or nothing further for `terminal`) that a workflow-
  declared `flow:` would only duplicate or contradict, whichever
  type's array they sit in. `flow:` is required on a population anchor
  and absent everywhere else; `blocks:` is optional there and absent
  everywhere else. A `review:` or `environment:` entry carrying either
  is a load error;
- **`flow:` is required on every population anchor and names a member
  of the type registry above.** This replaces the earlier
  `flow:`/`opens:` pair outright, not merely renames one half of it:
  there is no structural difference, on the entry itself, between
  "this queue dispatches a ticket" and "this queue opens a nested
  instance" for the loader to branch on. What the resolved name turns
  out to be — a type with no population anchor of its own (dispatch
  terminates there, an ordinary ticket) or one with at least one
  (dispatch mints a new instance, §15.8) — is visible only from what
  the *resolved declaration's own array* actually contains, never from
  anything the queue entry itself declares, and never from the
  resolved declaration's `skeleton:` alone (a seventh-pass correction,
  ORC-148: a type's skeleton no longer determines which of its own
  entries, if any, are population anchors — see §15.2). **A `flow:`
  naming a skeleton-less type is legal** (a fifth-pass reversal of the
  fourth pass's "nothing nests into a project" load error): a
  skeleton-less type's own array is entirely made of population
  anchors, exactly the property that makes any other type nestable,
  and refusing it as a target was an unstated assumption rather than
  an argued rule — one the declaration graph below needs reversed to
  catch the cycle it would otherwise miss;
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
- **a `blocks:` entry names an entry that is unique within the citing
  type's own `statuses:` array — a bare top-level entry, or one that
  belongs to a sub-array, in which case the reference is to the whole
  sub-array** (an eighth-pass reversal, ORC-148 design review: the
  seventh pass's own "must name a population anchor" is retired along
  with the sentence it read from, §15.7 — a population anchor was
  never what `blocks:` needed to guard, entry into a group is, and a
  group's one non-critique agent-balled entry, §15.10, is ordinarily
  the entry a `blocks:` reference actually names). **Uniqueness is a
  property of the reference, not the declaration it lands on**: a
  `blocks:` value resolving to zero entries, or to two or more (a name
  reused across separate top-level entries, or appearing in more than
  one sub-array), is a load error naming the count found — duplicate
  entries elsewhere in the array that the reference itself doesn't
  reach are otherwise legal, the identical posture every other
  cross-reference check in this section already takes (validate the
  reference, never the shape). §15.6's own scoping rule is unaffected:
  a `blocks:` entry naming a queue in a different declaration, one
  nested inside what *this* queue's own `flow:` opens, or this queue
  itself, is each still a load error;
- **the declaration graph — nodes are every type with at least one
  population anchor in its own array, edges are `flow:` references
  between them** — must be acyclic, and a type naming itself in one of
  its own population entries' `flow:` is rejected outright as the
  degenerate one-node case of the same rule — checked statically, from
  the loaded bundle alone, before any container instance exists. A
  `flow:` edge whose target has no population anchor of its own takes
  no part in this graph and is always a leaf, never on a cycle — a
  fact about what that type's array actually contains (a seventh-pass
  correction, ORC-148: no longer a fact read off its `skeleton:`
  alone, since a `ticket`-skeleton type may now declare a population
  anchor too, §15.2, and a `container`-skeleton type is no longer
  guaranteed one just by declaring that skeleton). **The node set was
  first corrected at the fifth pass** — the fourth pass's version
  admitted only `container`-skeleton types as nodes, which excluded
  every edge *into* a skeleton-less type by construction (the previous
  bullet's own load error, now reversed) and left a genuine cycle
  undetected: `milestone`'s `main` entry naming `flow: project` and
  `project`'s `build-out` entry naming `flow: milestone` is two nodes
  and two edges under the corrected definition, and a load error;
  under the fourth pass's narrower one, the first edge was never part
  of the graph to begin with, so the cycle went unbuilt and undetected
  until some live chain of instances happened to close it. This is the
  check that actually bars same-name nesting (a `milestone`
  declaration cannot open `milestone`) and bounds nesting depth: an
  acyclic graph has a finite longest path, so the maximum depth a
  bundle permits is knowable from the bundle itself, even though
  nesting composes arbitrarily (as many distinct named levels as the
  bundle declares). There is deliberately **no further, instance-level
  check** ("no container is its own ancestor") — it falls out of the
  declaration graph's acyclicity for free, and building it separately
  would leave unbounded depth *declarable*, caught only when some live
  chain of instances happens to close the loop, trading a load-time
  failure for a mid-flight one (the same trade this project has
  already made the other way: v5 §2.4's "failing at config load beats
  failing mid-flight");
- **`entry:` is required on every workflow bundle's `bundle.yaml`
  (§2), and must name a `type:` that resolves in the loaded union, is
  a node in the declaration graph above (at least one population
  anchor of its own), and is a root in it** — an absent `entry:`, one
  that doesn't resolve, one naming a type with no population anchor at
  all, or one some other declaration's `flow:` targets, is each a load
  error naming the mismatch (a seventh-pass simplification, ORC-148:
  the fourth-pass special case rejecting a `ticket`-skeleton type by
  name is subsumed by the node check once node membership stopped
  being read off `skeleton:` — a `ticket`-skeleton type with no
  population anchor still fails this the same way it always did,
  simply for having no population anchor, not for the skeleton it
  declares). Unlike `role_holders:` and `mirror_mapping:` above, there
  is no later component this field waits on — a bundle author writes
  it the same turn they write the type it names — so it takes no
  opt-in exemption.

Added with sub-arrays (§15.10, ORC-115):

- **a `statuses:` array entry that is itself an array is a sub-array**,
  and every entry inside one is still exactly one of `status:`,
  `review:` or `environment:` — the existing "exactly one of these
  three keys" rule (above) applies unchanged inside a sub-array, and a
  sub-array nested inside a sub-array is a load error naming the
  position (§15.10's own grammar is flat; nesting is explicitly
  undecided, not silently accepted);
- **a sub-array must hold exactly one entry whose `status:` is a
  non-critique agent-balled system status** (`generation`, `design`,
  `architecture`, `retro`, `setup` or `merge` — §15.1's `ball` column
  minus `critique`, which is excluded for the same reason §15.5 already
  excludes it from standing alone; `design` and `architecture` join
  this list at ORC-148's design review as generation-shaped kinds,
  §15.1). Zero such entries or two or more is a load error naming the
  declaration, the sub-array's position, and the count found;
- **Retired, ORC-148: the check refusing a population anchor (one
  carrying `flow:` or `blocks:`) inside a sub-array.** It existed
  solely to hold open the milestone retirement this ticket closes
  (its own error text named exactly that); §15.2's unification means
  a sub-array's one non-critique agent-balled entry no longer needs a
  `flow:` to exist inside a container's array in the first place, so
  the case the check was refusing doesn't arise from the shape this
  grammar now gives `setup` and `retro`. No replacement check is
  added: nothing else in this section makes a population anchor
  inside a sub-array meaningless, so none is invented for a shape no
  bundle has needed yet;
- **`throwback:`'s own load-time check is unaffected by sub-array
  membership**: whether the citing status
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
| `generation` | an agent run producing artifacts, undifferentiated | agent |
| `design` | a generation run producing a product-facing artifact | agent |
| `architecture` | a generation run producing a structural artifact | agent |
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

**`design` and `architecture` are named generation kinds, added at
ORC-148's design review — the fixed table growing, not a new
mechanism.** Both are generation-shaped in every rule this section and
§13 state for `generation` itself — agent-balled, `pending`-preceded,
requiring a blocked exit, recurrable, eligible for critique pairing
(§15.5) and for a sub-array's one non-critique agent-balled entry
(§15.10) — and "a generation-shaped kind" means the three, `generation`
included, wherever this document uses the phrase from here on. Plain
`generation` is unaffected and stays the right choice for a type with
exactly one generation-shaped visit — `setup`, `retro` and `seed` all
declare it and lose nothing here. The two named kinds exist for a type
that wants more than one visit distinguishable from the array itself:
v5 §7.6's own feature lifecycle has always described two —
*Product design* and *Architecting* — and until now both had to be
written as two indistinguishable `generation` entries, relying on
position and the gates around each to say which was which. `design`
and `architecture` let the array say it directly: a type wanting the
two-visit shape writes `status: design` for the first and
`status: architecture` for the second, each grouped with its own
critique and gates into its own sub-array (§15.10) exactly as a bare
`generation` entry already groups — **each generation's own review
steps sit inside that generation's own sub-array**, whichever of the
three kinds anchors it, never spanning two.

**Platform-fixed in the same table `generation` already sits in — not
bundle-authored, and not a second table.** This is what keeps this
section's own cutover re-resolution intact: the anchor set a blocked
work item re-resolves against can only be what it is *because* it is
not declarable (this section's opening paragraph) — a bundle inventing
its own generation-phase label would be exactly the undeclarable
anchor set acquiring a declarable member, breaking the property that
makes it a re-resolution anchor at all. A fixed pair of additional
names does not: `design` and `architecture` are checked the identical
way `generation` already is, everywhere `generation` is checked. Which
of a bundle's own generation-shaped tiers picks `generation`, `design`
or `architecture` — `sysarch`, `impl`, `ref` and the rest of
`bundles/default/tiers/**` among them, today uniformly undifferentiated
— is bundle content, `bundles/**`, dev's diff against this record, not
a mapping this pass assigns. **Two kinds, not one per tier, and none
for a target class this platform doesn't build for — a scope local to
this table's own growth rule, not a `docs/non-goals.md` entry** (design
review: an earlier draft cited that file here; it carries no such
entry, and the nearest two — "No LiveView/React mixing within one
frontend target" and §1's audience line — answer a different question,
so the citation was dropped rather than backfilled). This table grows
by the two names the shipped chain's own lifecycle already needed, not
by a per-tier scheme guessed at against tiers that don't exist yet, and
not by a second table or a per-dialect one held in reserve against a
possibility — if a non-software target ever arrives it brings its own
skeleton and its own status names, the identical posture §15.1 already
takes toward `container`'s own five-anchor sequence. The reason is
local to this table, the way §15.10 below is local to a sub-array's own
reference rule: it spans no other system and every pass need not see
it, so it stays here rather than in the cross-system file.

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

**A `pending` precedes every generation-shaped entry
(`generation`/`design`/`architecture`) and every `deploy`** — a
load-time check (§13), not a convention. **`stubbed` is exempt from
staleness and escalation** (v5 §7.6): nothing is stale about waiting
deliberately.

Mapping onto v5 §7.6's lifecycles, which are this vocabulary with
every review sequence at length one — feature: `Todo`(pending) →
`Product design`(design) → **Product review**(review) →
`Architecting`(architecture) → **Architecture review**(review) →
`Building`(fanout) → `Reconciling`(merge) → `Merged`(merge) →
`Validating`(validating) → `Shipped`(terminal). Child: `Ready for
dev`(pending) → `In progress`(generation) → `Checks`(checks) →
`Reconciling`(merge) → `Merged`(merge) → `Done`(terminal), with
`Ready for rework`(pending) / `Reworking`(generation) as the repair
loop. The two bolded statuses are the platform workflow layer's
default review declarations, not system statuses — which is what
makes them replaceable. **`Product design` and `Architecting` name
the `design` and `architecture` kinds directly, at ORC-148's design
review** — before it, both were italicized prose labels standing in
for two indistinguishable `generation` visits, told apart only by
position and by which review followed each; the child lifecycle's own
single visit (`In progress`) has nothing to distinguish and stays
plain `generation`, the still-correct choice for one visit.

**Two fixed skeletons, and `skeleton:` is optional — there is no
third value standing for "neither."** A declared work-item type
(§15.2) may select a `skeleton:` of `ticket` or `container`, which
fixes which of the anchors above its `statuses:` array must contain,
each at least once, in the relative order given here — never their
names, their presence, or (bar the exceptions §15.4 and §15.5 name)
how many times each may appear:

- **`ticket`** — `pending`, then any interleaving of a generation-shaped
  entry (`generation`, `design` or `architecture`, each optionally
  paired with a `critique` entry, §15.5) and declared gates (§15.4),
  then `checks`, `merge`, `deploy` (optionally paired with declared
  environments, §15.4), then `terminal`. A generation-shaped kind and
  `merge` may recur — v5 §7.6's own feature lifecycle above already
  visits one twice, once as `design` (`Product design`) and once as
  `architecture` (`Architecting`), and `merge` twice (`Reconciling`,
  `Merged`) — `pending` and `terminal` may not: first and last, exactly
  once.
- **`container`** — the five names fixed at this ticket's first pass:
  `setup`, `prep`, `main`, `retro`, `cleanup`, each at least once, in
  that relative order, then `terminal`, exactly once, last. This is
  the container analogue of the ticket skeleton, for the identical
  re-resolution reason: the anchor a container parked mid-sequence
  falls back to when a workflow cutover changes what a queue
  dispatches underneath it. A container currently at `main` stays at
  `main` across the cutover; only which type `main` now dispatches
  changes.

**A skeleton fixes a required backbone, never an exclusive
membership — a seventh-pass reversal, ORC-148, of the sentence §15.2
opened with.** "There is no practical reason a container cannot
contain a generation" (the author's own words for this ticket): the
five names above are what `container` *requires*, not the whole of
what its array may hold, and the ticket skeleton's own list above is
read the identical way, symmetrically. A type's array may additionally
interleave any other entry this closed vocabulary allows — a bare
`generation` (paired with `critique` exactly as §15.5 already allows
anywhere), a `checks`/`merge`/`deploy` run, or a population anchor
(`prep`/`main`/`cleanup`) opening a nested queue of its own — around
its required backbone, whatever skeleton it declares or omits, subject
only to the positional rules those kinds already carry elsewhere in
this section (critique immediately after its generation, §15.5; a
`pending` earlier in the same array than every generation or deploy it
licenses, above). What a bundle actually needs is unaffected: today's
default bundle has no ticket-skeleton type wanting a population anchor
of its own, so nothing here is exercised in that direction yet, the
same posture §15.10 already takes toward a shape no bundle has needed
(the fixed anchors' own "each at least once", "each exactly once" and
ordering rules are otherwise unchanged by this — see §15.2 for what
this does and does not mean for nesting).

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

**The project's special case is rootness, not skeleton — worth
stating now that container/ticket is a backbone choice rather than a
functional split (ORC-148), so a later pass does not re-derive
"project" as a property of `skeleton: container`.** Omitting
`skeleton:` buys a type exactly the two things above: no re-resolution
anchor to preserve and no fixed relative order to check, because
nothing forces a workflow cutover mid-project the way one forces a
container's own parked position to resolve against a fixed anchor
set. Both hold regardless of which other entries that type's array
happens to hold — a skeleton-less type was already free to interleave
gates, environments and population anchors in any order it wanted
(§15.2's fifth-pass widening), which the backbone-not-membership
reversal above does not change. What actually makes the outermost
project the project — that nothing else's `flow:` targets it — is
§15.6's rootness, a fact about the declaration graph, not about
`skeleton:` at all: a bundle can and does declare other skeleton-less
or `container`-skeleton roots (`epic`, say) without either being "the
project." Rootness, not the absence of a skeleton and certainly not
the presence of queues, is the one thing that generalizes.

**Agent steps**, the other half of what a chain's `delivery:` block
may name (§3): `design` (produces a design-graph artifact for a
tier), `dev` (implements a child scope), `critique` (the review pass
over a freshly produced draft), `reconcile`, `validate` (§7.11's
repair loop). Adding one is a platform change, reviewed as one. **This
list is unaffected by `design`/`architecture` joining the kinds table
above.** The two axes answer different questions — `agent_step` says
what broad category of run a tier is, `phase` (checked against this
table's own `kinds/0`, not `agent_steps/0`) says which position in a
workflow's array dispatches it — and a tier producing an architecture
artifact is still, categorically, a `design`-agent-step run; only its
`phase:` picks `architecture` over the older, undifferentiated
`generation`.

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

**A container is a work item whose skeleton fixes queue anchors. A
ticket is one whose skeleton fixes a generation anchor. Neither fact
bounds what else either one's array may hold, and the grammar gives
them one declaration shape, not three** (author review, superseding
this ticket's own second draft, which had already collapsed
`flow:`/`opens:` into one field but still split `queues/project.yaml`,
`queues/containers/<name>.yaml` and `types/<name>.yaml` into three
file locations; the first sentence itself superseded at ORC-148,
which found the "has queues" / "has a generation" framing was read as
an exclusive membership rule rather than the backbone-only one it
argued for, §15.1). A milestone with a `main` queue, then a human
sign-off gate, then a staging deployment, then `retro` is an ordinary
sentence this grammar can say; there is no reason a container should
be unable to carry a gate, a deployment, or — ORC-148's own case — a
generation, merely because earlier drafts gave each shape its own
file and its own rules. **There is no practical reason a container
cannot contain a generation** (ORC-148, author decision): the
`setup`/`retro` fold below is the motivating case, but the rule is
general — the container/ticket split was never meant to be a
functional one, only a naming convenience for which backbone a
declaration's array is required to carry.

```yaml
# types/milestone.yaml
type: milestone                  # this declaration's name — what a
                                  #   flow: value (§15.7) and a chain
                                  #   bundle's own ticket: labels:
                                  #   reference (never a load-time
                                  #   cross-check — see §15.7)
skeleton: container              # ticket | container | omit for none (§15.1)
statuses:                        # the skeleton's own required backbone,
                                  #   plus whatever else is declared,
                                  #   in array order (§15.3)
  - status: pending
  - status: setup                # the container's own agent step,
                                  #   inline (ORC-148) — dispatches by
                                  #   chain-side tier, not by flow:
  - status: checks
  - status: merge
  - status: deploy
  - status: prep
    flow: feature
  - status: main
    flow: feature
    blocks: [retro]
  - review: ux-review             # a declared gate (§15.4), positioned here
  - status: retro                 # the container's other agent step,
                                  #   inline the identical way
  - status: checks
  - status: merge
  - status: deploy
  - status: cleanup
    flow: tech-debt
  - status: terminal
```

**`setup` and `retro` above carry no `flow:`** — ORC-148's fold of
`types/setup.yaml` and `types/retro.yaml` into this declaration
(§15.10 works the full shape, grouped with the gates around `retro`
in the real bundle). `pending` is not part of `container`'s own fixed
backbone (§15.1) and is not exactly-once the way it is for `ticket` —
it is ordinary interleaved vocabulary here, licensing the `deploy`
(and, transitively, the `checks`/`merge` between) each of the two
agent steps needs (§15.1's "a `pending` precedes every `generation`
and every `deploy`" reads as "somewhere earlier in this array," not
"immediately before" — `feature.yaml`'s own single `pending` below
already licenses two separate `deploy`-bound runs the identical way).

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

- **the skeleton's own required backbone** (§15.1) — `pending →
  generation → checks → merge → deploy → terminal`, each at least
  once and pending/terminal exactly once, against `setup → prep →
  main → retro → cleanup → terminal`, each at least once, against no
  fixed shape at all for a type with no `skeleton:`. This is the
  reason `container` and `ticket` are different `skeleton:` values
  rather than one — it is the only thing left that they are.
- **can source a nesting edge** — any type whose array holds at least
  one population anchor (a `status:` entry carrying `flow:`, §15.7)
  can point at another container; a type with none is always a leaf in
  the declaration graph (§15.6). This is now a fact about a
  declaration's own entries, not about which `skeleton:` it names — a
  fourth-pass-through-sixth-pass reading tied it to `skeleton:`
  because a `ticket`-skeleton type's array had no room for a
  population anchor at all; ORC-148 removes that room's own ceiling
  (below), so the fact it used to stand in for has to be checked
  directly. Nothing in the default bundle exercises a `ticket`-
  skeleton type nesting another container today; the grammar no longer
  refuses one the way it refused a container holding a generation.
- **critique's admission** — a `critique` entry must sit immediately
  after an actual `generation` entry in the same array (§15.5),
  whichever type declares it. This was effectively a `ticket`-only
  rule while a `generation` anchor was `ticket`-only; it stays exactly
  the positional rule it always was, now simply checked against
  whatever a type's array actually contains rather than against what
  its skeleton implied that array could contain.

Everything else — which file a declaration lived in, and whether its
array was a registered set or a fixed sequence — was the three-shape
split talking to itself, and none of it survives as a rule to check.

**Gates and environments are legal on every type, whatever
`skeleton:` it declares or omits.** The argument for restricting a
project's array to `status:` entries — "all review happens at lower
levels" (§15.1) — is true of the outermost scope, but it is an
argument for why a project needs no *re-resolution anchor*, not one
about what its array may *contain*. Those are different claims, and
the governing rule at the top of this section is stated only in terms
of ticket versus container, never mentioning the project either way. A
human sign-off between `build-out` and `iteration` (the milestone
example above) is not a strange thing for a project to want, so it is
admitted rather than refused on a premise that was never actually
argued. Critique alone stays gated past this widening, and for a
reason unrelated to the one above: a `generation` anchor is what gives
its depth something to select within, so a `critique` entry is only
ever legal immediately after an actual `generation` entry in the same
array (§15.5) — a positional fact about that array's own contents,
not a `skeleton:`-keyed refusal (ORC-148 makes this the same rule
regardless of which type declares the pairing).

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

**`throwback:` is a single optional target (ORC-115).**

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

### 15.5 `critique` — paired with a peer generation-shaped entry

**The one carve-out, and the reason is worth stating rather than
asserting.** A gate is depth 0 on a container the identical way it is
on a ticket — a human reads the top level, whatever the top level
contains — and an environment is the same: neither needs a generation
to mean something, which is why the fifth pass widened both onto
every type regardless of skeleton (§15.2). Critique is different in
kind: its depth *selects which tiers' review runs*, which needs a
generation to select within. **The rule is simply that a `critique`
entry must sit immediately after a generation-shaped entry**
(`generation`, `design` or `architecture`, §15.1, added at ORC-148's
design review — every rule in this section reads "a generation entry"
as any one of the three from here on) — no skeleton named, because
none needs to be: whether a given array has a generation-shaped entry
for a `critique` to pair with is a fact about that array's own
contents, not about which skeleton, if any, the citing type declares
(a fifth-pass simplification — naming the excluded skeletons
explicitly, as an earlier draft did, said the identical thing twice; a
`container`-skeleton or skeleton-less type happened to never have one
to pair with at the fifth pass only because nothing let it declare a
bare generation-shaped entry at all, a restriction ORC-148 retires,
§15.2). The positional rule itself needs no update: it was never
actually about skeletons, only about what sits where.

```yaml
  - status: generation
  - status: critique              # must sit immediately after a
    depth: 1                      #   generation entry in the same array
```

**Configures a fixed kind; declares nothing.** `critique` is a system
status (§15.1), not a named, reusable declaration the way a gate or
an environment is — there is exactly one `critique`, and citing it
more than once in a type's array (once per generation-shaped entry it
should pair with) is the ordinary way to give two generation phases
different depths, not two declarations of the same thing.

**Presence is participation — there is no `enabled:` field.** A
generation-shaped entry with no adjacent `critique` entry runs no
critique tier at that phase, whatever the chain declares. One that does runs
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
generation-shaped entry it reviews (above): it reviews a draft that has
to exist first. An environment sits *before* the `deploy` entry it is a
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
type's population anchor may name another type that itself has a
population anchor, in its own `flow:` (§15.7) — declaring `epic` gets
epics-and-milestones for free the moment an `epic` type's own `main`
entry's `flow:` names `milestone`, no second mechanism, because there
is only the one shared registry and one field. What a nesting edge
depends on is what the source and target types' arrays actually
contain, never which `skeleton:`, if any, either one declares (a
seventh-pass reversal, ORC-148, of the `container`-or-skeleton-less
framing below — see §15.2). What varies per declared container is its
**name** and what each of its anchor entries' `flow:` points at —
never the anchor names, their count, or their order (§15.1).

**What is barred, and barred at load rather than left to a live chain
to discover, is a type reaching itself through its own declarations.**
The declaration graph — **nodes are every type with a population
anchor of its own, edges are `flow:` references between them** — must
be acyclic, and a type naming itself is the degenerate one-node case
of the same rule (§13). `milestone` cannot open `milestone`. A `flow:`
edge whose target has no population anchor of its own takes no part in
this graph and is always a leaf — today, that is every `ticket`-
skeleton type the default bundle declares, because none of them
happens to add one, not because a `ticket`-skeleton type is
structurally barred from having one (ORC-148 removes that bar, §15.2).

**The node set has to be read from each type's own declared entries,
not from its `skeleton:` — an earlier draft's definition, first
narrowed to `container`-skeleton types only and then widened to
include skeleton-less ones, had the right shape but the wrong
handle.** Restricting nodes to `container`-skeleton types excluded
every edge *into* a skeleton-less type by construction, because such a
type was never a node the graph could contain — which is exactly the
edge a cycle through the project can run on: `milestone`'s `main`
entry naming `flow: project` and `project`'s `build-out` entry naming
`flow: milestone` is a genuine two-node cycle, and the narrower
definition would have let it load, catching it only if some live chain
of instances happened to close the loop. Fixing this at the fifth pass
by widening the *skeleton* condition to `nil` as well as `"container"`
was correct as far as it went, but it was still asking the wrong
question — the actual property a node needs is "has a population
anchor," which a `container`-skeleton or skeleton-less type happened
to always have and a `ticket`-skeleton type happened to never have,
while `skeleton:` itself stayed silent on the question the moment
ORC-148 let any type's array hold a population anchor regardless of
which backbone it declares. The node set is unaffected by this in
today's default bundle — nothing there gives a `ticket`-skeleton type
a population anchor — but the *definition* has to be the direct one
now that the two facts can come apart.

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
container or project unable to advance into an entry `Q` because `Q`'s
own `blocks:` target still carries unresolved work (§15.7) is fully
described by "at [whatever precedes `Q`], guarded from `Q` by
`blocks:`'s target" — an entry guard, checked at the transition into
`Q`, never a state `Q` itself is ever *in* (§15.7's ORC-148 correction:
the container is never "at `Q`, blocked," since `Q` cannot become
current while its guard holds) — derivable from the declared queue
graph plus live ticket state, the identical reasoning that keeps a
queue itself from being stored. Introducing a stored or fixed
`blocked` status here would be exactly the pending-work-on-the-node
antipattern v5 §7.11's staleness projection already refuses.

### 15.7 Queues, dispatch, and blocking

A **population anchor** is any `status:` entry named `prep`, `main` or
`cleanup`, or any `status:` entry at all in a skeleton-less type's
array (§13). It carries `flow:`, required, naming a member of the
type registry (§15.2). This is a fact about the entry's own name and
the array it sits in, never about which `skeleton:`, if any, that
array's own type declares as a whole (ORC-148 — see §15.2 for what
was true before and why it changed): `generation`, `design`,
`architecture`, `critique`, `pending`, `checks`, `merge`, `deploy`,
`setup`, `retro` and `terminal` are never population anchors and never
carry `flow:`, whichever type's array they sit in.

```yaml
  - status: main
    flow: feature
    blocks: [retro]
  - status: retro
  - status: checks
  - status: merge
  - status: deploy
```

**A queue is a query, never stored** (`docs/v5-design-decisions.md`
§7.8): the unresolved work items in this container or project
assigned to this queue. Nothing writes a per-queue bucket; nothing
reads one back. The identical reason `ready_scopes` itself refuses to
materialize (v5 §1.2) and `Catapult.Engine.Scheduler` holds no memory
of what it last broadcast: a stale bucket is worse than an absent
one, because it is the kind of thing a dispatcher acts on.

**`singleton:` is retired (ORC-148), and nothing replaces it.** It
bounded a *queue* to at most one work item ever assigned — the
mechanism `milestone`'s `setup` and `retro` anchors needed while each
was implemented as `flow:` naming a separately minted, ticket-skeleton
child (`types/setup.yaml`, `types/retro.yaml`): a queue is otherwise
open-ended, so declaring it closed after one assignment was the only
way to say "this container has exactly one setup, ever" without a
second mechanism. §15.2's unification removes the reason: `setup` and
`retro` no longer name a queue at all once they can sit inline as
ordinary agent-balled entries (`generation`'s own kind of anchor, not
a population one, §15.1) directly in the container's own array. An
inline entry runs once per pass through it, exactly like `main` runs
once per container instance and `generation` runs once per ticket
pass — the "at most one, ever" property `singleton:` used to declare
falls out of the container having exactly one instance and the entry
sitting at one array position, with nothing left to bound. There is no
gap this leaves open: the field existed only because a queue could
otherwise admit more than one child, and an inline entry was never a
queue to begin with.

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
entry itself declares.** A `flow:` resolving to a type with no
population anchor of its own dispatches an ordinary ticket: opening a
ticket of the declared type opens a flow instance exactly as any other
entry does (v5 §7.10's "opening a ticket IS opening a flow instance"),
with its own gates, its own children, its own PR. A `flow:` resolving
to a type with a population anchor of its own mints one instance of it
(§15.8); the parent's queue does not complete until the minted
instance closes (reaches its own `terminal`, for a `container`-
skeleton instance, or resolves its own last declared entry with
nothing open behind it, for a skeleton-less one, §15.6) — nesting
composes through the same completion rule any other `flow:` queue
already uses, because there was never a second mechanism to begin
with. `main`'s `flow: feature` (which dispatches ordinary feature
work) is this rule in its plainest form; `prep`'s is identical.
`setup` and `retro`, by contrast, carry no `flow:` at all under
ORC-148's fold (§15.2) — each is an ordinary agent-balled entry, "a
work item, with its own bundles, dispatched by machinery that already
exists" (`docs/v5-design-decisions.md` §7.8), the identical mechanism
a `generation` entry already uses: the chain bundle backing `milestone`
itself carries the tiers with the `delivery:` blocks that give `setup`
and `retro` their actual agent behavior, exactly as a ticket-skeleton
type's own chain gives its `generation` entries theirs. Neither is a
reserved agent-step slot the way `boundary` used to be (§15.1), and
neither needs a nested type or a queue of its own to exist.

**`blocks:` is an entry guard, checked once at the transition it
guards — never a standing hold a projection recomputes** (an
eighth-pass reversal, ORC-148 design review). An entry `E` declaring
`blocks: [Q]` gates entry *into* `Q` (a bare entry, or a sub-array,
named through the one entry a reference reaches inside it, above): `Q`
cannot be *entered* while `E` itself still carries unresolved work; the
check runs exactly once, at the moment something attempts the
transition into `Q`, and never again against the same occupancy.
**This is what removes the eject.** Under the retired
standing-hold reading, a queue refilling while the guarded entry was
already mid-run pulled the container back out of it — indistinguishable
from the guard never having cleared. A reassignment to a new status
must never interrupt an already-dispatched flow instance, and `retro`
is the case that makes the distinction load-bearing rather than
academic: `retro`'s own output lands back in `main` (adjudicated
findings, filed debt), so a completion-hold form of `blocks:` would
have `retro` interrupting itself the moment its own run produced the
work `main`'s queue was watching for. Checked once, at entry, `main`
having emptied is a precondition for *starting* `retro`, never a
condition `retro` has to keep satisfying while it runs.
`main blocks: [retro]` is the instance that generalizes what used to
be a special case ("the retro can't finish while milestone work is
open") into this one declared relation — restated precisely, now that
completion-holding isn't the mechanism: `retro` cannot be entered while
`main`'s own queue carries unresolved work. §13 rejects a `blocks:`
entry naming a queue in a different declaration, and rejects one naming
a queue nested inside what *this* queue's `flow:` opens. Reaching into
a nested container's own queues would make that container's internals
part of its interface to the level blocking it, exactly backwards from
composability: to block on something nested, block on the `flow:`
entry that opens it, not on what is inside it.

**Reaching `terminal` is guarded by every one of the container's own
queues holding no unresolved work — a platform rule, not a `blocks:`
declaration a bundle writes or can opt out of.** This is a different
guard from the one above, not a second spelling of it: an authored
`blocks:` names one entry guarding one other, declared where an author
chose to write it; the terminal guard is unconditional and reaches
every queue-shaped anchor the container's own array declares, whether
or not any of them is also named in some other entry's `blocks:`. A
bundle author cannot narrow it, because narrowing it is exactly the
shape of bug an author-declared `blocks:` graph could reintroduce by
omission — a queue nobody thought to name in a `blocks:` list quietly
closed over on the way to `terminal`. `cleanup`'s own resolution stays
an ordinary entry, guarded only by whatever `blocks:` a bundle declares
on it, if any; it is `terminal` specifically, the fixed kind every
container-skeleton instance reaches (§15.6), that carries this
undeclarable guard.

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
activates it.** A `flow:` resolving to a type with a population anchor
of its own mints an instance as soon as something creates it —
business logic, or a person — and that instance accepts work into its
own future queues immediately. The parent's own queue position
determines only which minted instance is *current*; `setup`'s own
entry (§15.1, §15.7 — inline under ORC-148's fold, dispatched by
`milestone`'s own chain-side tiers exactly as a `generation` entry
would be) dispatches once an instance becomes current, not once it is
minted, which is what makes "runs once, at activation" true without
leaning on mint timing. Minting and constituting were always
necessarily two different declarations — the parent's queue entry
lives in the parent's own file, the newly minted instance's `setup`
entry lives in the child's — so there was never a "before `setup`"
position to invent in the first place.

**There are two ways a container's position moves backward, not
one.** The first, and the one that needs
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
widening onto a skeleton-less type's array and `skeleton:` becoming
optional instead of three-valued are both changes in *where* an
already-declarable fact may be cited or *how* it is spelled — a gate
was already workflow-bundle content before a project's array could
cite one. No plane logic branches on either, so neither argues with
the entry above the way the third pass's type registry did.

**Nor does the sixth.** `entry:` in `bundle.yaml` (§2) is a reference
to an already-declared type, the identical shape `catapult.yaml`'s own
`chain:`/`workflow:` pins already have — it names which already-
declarable root the plane starts from, adding no new declarable fact
about the automation graph itself.

**Nor does ORC-148's own reversal.** Removing the coupling between a
type's `skeleton:` and which of its entries may be population anchors
or agent-balled ones (§15.2, §13) changes which combinations a bundle
may write, not whether the plane branches on any of them — dispatch
still follows entirely from what an entry *is* (a population anchor
with its `flow:`, or one of the fixed agent/world kinds with its own
mechanism), never from which skeleton the citing type happens to
declare. Retiring `singleton:` outright is smaller than a spelling
change: the field bounded a queue's own cardinality, and once `setup`
and `retro` stop being queues at all (§15.7), there is no cardinality
left for a field to bound — not a fact moved elsewhere, a fact that
stopped existing.

### 15.10 Sub-arrays — grouping a gate around its own agent step

**A `statuses:` array entry may itself be an array — a bare, unnamed
sub-array grouping a contiguous run of the entries §15.2 already
allows anywhere in the array** (ORC-115, design pass). Grouping is
admissible under `docs/non-goals.md`'s "No per-project restructuring
of the automation protocol" for that entry's own stated rule — no
plane logic branches on whether entries are grouped, any more than it
branches on where in the array one sits (§15.9). Nothing new is
declarable inside one: an entry inside a
sub-array is still exactly one of `status:`, `review:` or
`environment:` (§13's existing rule, unchanged), and a sub-array
carries no key of its own — no `name:`, no `id:`. **A sub-array stays
anonymous, and is referenced through an entry it contains, never by a
name of its own** (a name/id-based handle was considered and rejected
at this ticket's design review, `docs/non-goals.md` carries no entry
for it because the reason is local to this section, not a refusal
worth a cross-system entry: a sub-array is a grouping of entries that
already have names, so a second name naming the group would be a
second way to say what the first entry inside it already says). §13's
`blocks:` reference (above) is exactly this: `blocks: [retro]` names
`retro`, and if `retro` sits inside a sub-array the reference reaches
the whole group through it — resolved by containment, not by a handle
the sub-array itself carries. The addition is structural
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
(§15.2's fifth-pass widening).** A population anchor (one carrying
`flow:` or `blocks:`) may not appear inside a sub-array — the check
retired at ORC-148 (§13) existed only to hold that line for `setup`
and `retro` specifically, and its retirement doesn't relax anything
here, because a population anchor was never one of the entries this
section groups in the first place. What ORC-148 actually widens is
which *type* has something worth grouping: `setup` and `retro`, now
ordinary agent-balled entries, are legal directly in a `container`-
skeleton type's array (§15.2), and the fold below groups `retro` with
the gates around it the identical way `feature.yaml`'s own sub-array
groups `generation` with its gates. A `container`-skeleton or
skeleton-less type whose array still holds nothing but its required
backbone plus gates and environments has nothing worth grouping — but
that is a fact about what a given bundle chose to declare, not a
ceiling this grammar imposes.

**Exactly one non-critique agent-balled entry per sub-array — a
load-time check, and the fact the whole derivation below rests on.**
§15.1's `ball` column already marks `generation`, `design`,
`architecture`, `critique`, `retro`, `setup` and `merge` as
agent-balled; critique is excluded here because it reviews a
generation-shaped entry rather than standing as one, the identical
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
shape, `[milestone-signoff, retro, proposals-read]` (the real
`bundles/default-flow/types/milestone.yaml`, not §15.2's own
simplified `ux-review` illustration) — a `review:` entry's position in
the flat
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

**The worked example is now the grammar, not a shape argued from
prose ahead of it.** Before ORC-148, `bundles/default-flow/types
/milestone.yaml` cited `retro` as a `flow:`-carrying, container-
skeleton anchor (`types/retro.yaml` ran its own singleton flow), and
the (now-retired) load-time check refusing a population anchor inside
a sub-array meant `[milestone-signoff, retro, proposals-read]` could
not legally form a sub-array at all — the derivation below was argued
from the shape ORC-104 had committed to in prose, not from a sub-array
the loader accepted at the time. §15.2's unification and `singleton:`'s
retirement (§13, §15.7) close that gap: `retro` carries no `flow:`
once it folds inline, so nothing bars it from sitting inside this
group, and `types/setup.yaml`/`types/retro.yaml` are deleted rather
than dispatched to (`bundles/**` is dev's diff against this record).
One consequence worth naming plainly: this sub-array is also the
first shape the default bundle can legally form that actually
distinguishes the derivation from a naive first-element one —
`types/feature.yaml`'s own group (`generation`, `critique`,
`ux-review`, `engineering-review`) has `generation` as both the
sub-array's one non-critique agent step and its first entry, so it
never exercised the difference; `[milestone-signoff, retro,
proposals-read]` has its one non-critique agent step *second*, which
only the derivation this section states gets right.

**A decline's legal targets are "earlier in this ticket's effective
sequence", never a per-gate declared list.** This is §7.19's rule for
Blocked-return, and the two entry points share it: a throwback from a
review and an unblock to an earlier status differ only in their
*default*, not in what is reachable.

A declared list never bounded anything, and that is a fact about the
tree rather than a decision taken here.
`lib/catapult/engine/commands/decline_gate.ex`'s own moduledoc states
that `gate`/`throwback_to` membership "is the command edge's to
check... not the aggregate's", and that command edge is unbuilt
(`systems/delivery.md`'s Phase 7). There was never any shipped
enforcement of a declared allow-list to preserve. Nor is the
replacement bound invented for the occasion:
`Catapult.Dsl.Workflow.gate_throwback_problems/2` already computes
exactly it — `target in (type.statuses |> Enum.take(index))` — for a
declared value at load time. One predicate, in one place, instead of a
load-time check and a runtime allow-list that happened to agree.

**`throwback:` survives as a single-target override on the default
landing point.** Bounding legality is the job it no longer has;
naming *where a decline lands* is the job it keeps, and that is what
an escape hatch is for. The derivation above supplies the default —
the citing sub-array's own non-critique agent step — and `throwback:`
is what a gate declares instead of it.

A list stops meaning anything the moment it stops bounding: naming
several targets said "any of these is a legal exit", a claim about
legality. A landing point is not a set, since a decline lands on
exactly one status, so the field is a single optional target rather
than a list. `docs/v5-design-decisions.md` §4.5's escape-hatch
discipline — "an escape hatch that accretes special cases becomes N
more mechanisms" — is why it stops at one override: a single explicit
status, no per-use kinds, no second derivation rule beside the
sub-array default.

**The day-one test still matters, restated for a default rather than a
bound: if the default bundle needs the field to reach a *different*
landing point than the derivation would pick, that is the field doing
its job; if it needs the field only to restate a target already
reachable, that declaration is redundant and worth dropping.** Under
the widened legality rule, the retro case that motivated this whole
section resolves with no declaration at all — the derivation is right
about the ordinary case. Four default-bundle gates declare
`throwback:` today. Two sit inside `feature.yaml`'s own sub-array and
are read against the sharper test, not waved through:

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

The other two sit in `milestone.yaml`, which declares no sub-array at
all — nothing in the file is ever grouped, whatever its own entries
are. The sharper test doesn't apply to a gate with no citing
sub-array to derive a default from; both are single-element lists
narrowing to their one element with nothing to weigh:

- `milestone-signoff`'s own declared `throwback: [main]` (`bundles/
  default-flow/gates/milestone-signoff.yaml`) narrows to `main`, still
  earlier than `milestone-signoff` in `milestone.yaml`'s own array.
- `proposals-read`'s own declared `throwback: [retro]` (`bundles/
  default-flow/gates/proposals-read.yaml`) narrows to `retro`, still
  earlier than `proposals-read` in the same array.

Narrowing all four files' `throwback:` to a single string, and
dropping `engineering-review`'s now-redundant second element, is
dev's diff against this record (`bundles/**`); no file loses a landing
point a decliner can still reach.

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
The two entry points also share what counts as a legal target, for
the reason given above: `DeclineGate` enforces no declared list, and
the command edge that would is unbuilt. A gate's
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
ordinary work items" passage is superseded by this ticket, in the
document that records it, not only here**: `milestone`'s `setup` and
`retro` fold into `milestone`'s own array — `retro` inside the
sub-array above, `setup` needing no sub-array of its own (§15.2) —
rather than remaining separately dispatched ticket-skeleton types, and
`types/setup.yaml`/`types/retro.yaml` are deleted rather than kept as
dispatch targets. This was ORC-115's own recorded direction, not yet a
decision; ORC-148 settles it, including the question ORC-115 left
open — a container instance is a legal agent dispatch target, on the
identical footing as a ticket instance (`docs/v5-design-decisions.md`
§7.8, `systems/delivery.md`).
