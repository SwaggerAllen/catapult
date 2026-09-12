# Catapult DSL — syntax reference (v0)

**Status:** the normative syntax for the DSL core, consolidating the
v4 spec's §A.2 with every v5 delta (v5 §6, §9). Where this document
and the v4 spec disagree, this document wins. The loader implements
exactly these productions, and reconciliation verifies it against
this file. Grammar changes are reviewed edits here first, code second.

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
bundles/<name>/                # kind: chain — forked from a platform
  bundle.yaml                  #   template, never `extends:`-layered (§11)
  tiers/<tier>.yaml            # one file per tier declaration
  edges/<edge>.yaml            # one file per named edge instance
  predicates.yaml              # optional: named predicates
  prompts/<tier>.md.liquid     # one per LLM-generator tier
  prompts/review/<tier>.md.liquid
  prompts/partials/<name>.md.liquid   # shared fragments ({% render %})
  schemas/<name>.xsd           # body grammars referenced by tiers
  flows/<flow>/flow.yaml       # one directory per flow
  flows/<flow>/<prompt>.md.liquid
bundles/<name>/                # kind: workflow — forked the same way
  bundle.yaml                  #   template, same as the chain axis (§11)
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
kind: chain                       # chain | workflow
tiers: [tiers/*.yaml]             # glob lists; the loaded bundle is the union
edges: [edges/*.yaml]
fragments: [techspec, pubapi, privapi, policies, failure_surface]
flows: [flows/*/flow.yaml]
```

A workflow bundle's manifest carries `kind: workflow` — no `extends:`
field, the same as the chain axis (§11) — `gates:` / `environments:`
/ `types:` globs in place of the chain's lists, and one further key
the chain axis has no counterpart for:

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
starts — a fact rootness alone does not answer.** §15.6's declaration
graph derives which types are *roots* — nodes nothing else's `flow:`
targets — and a bundle declaring `epic` without ever nesting it under
something else has two of them; roots are not projects, and "the
project is a project by convention" is not a rule the loader can check
anything against. `entry:` is a reference, the identical shape
`catapult.yaml` already has pinning one bundle per axis, not a
duplicated fact: it names a `type:` and the loader checks three things
at load — the name resolves in the loaded union, the resolved
declaration carries a queue-shaped anchor (`container`-skeleton or
skeleton-less, §15.6), and it is a root in the declaration graph
(§13). Rootness itself stays derived, for the acyclicity argument
§15.6 makes; only *which* root is the entry point is declared, once,
beside the other bundle-wide facts `bundle.yaml` already carries.

The file-list keys are per-kind: a `tiers:` list in a workflow bundle
is an unknown field and a load error, per §13, and so is `extends:`
on either bundle's manifest — neither axis composes a base layer at
load time.

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
edge's `declared_in:` row carried for this node, read off the minting
instance element itself — the row-local form. The other case this
convention covers — a value inherited from the committing tier rather
than row-local to the minting instance, one hop further than a single
context walk can reach (§7 below) — has its own name and its own
load-time check, below: `mint.parent.<name>`. The row-local form
stays unvalidated at load time: nothing cross-checks a bare
`mint.<name>`'s `<name>` against the minting instance element's own
attributes, the way §13 cross-checks both a `draft.<path>` source
and `mint.parent.<name>` (ORC-236); naming the convention here is so
two bundle authors, or one bundle read twice, agree on what a
join-target tier's `fields:` values mean.

**`mint.parent.<name>` is that second, inherited case, spelled rather
than left for a reader to infer from context** (ORC-236). It never
navigates the minting instance element: `<name>` must instead name one
of the *committing* tier's own `fields:` entries or one of its own
`produces:` fragment kinds, and the value copied onto the newly minted
node is whichever of those two the committing tier's own
`DraftCommitted` already computed for itself at that same commit — a
comp's own `project_techspec` field is declared `project_techspec:
mint.parent.techspec`, naming `sysarch`'s own `techspec` field
(`sysarch.yaml`'s `fields: techspec: draft.techspec`); a subcomp's own
`parent_techspec` field is declared `parent_techspec:
mint.parent.techspec`, naming the `techspec` fragment `comparch.yaml`'s
own `produces:` writes onto its `self.parent` (comp) in the identical
commit that fans subcomp out. Nothing is read from the
node the fragment lands on (comp is not subcomp's own minting parent;
comparch is) and nothing is read from the store — both sources are
already local values the committing tier's own extraction pass holds
before `mints:` is even built, so `mint.parent.<name>` costs no new
navigation, only a second place already-computed values are read from.
A bare `mint.<name>` stays the row-local form above, unchanged.

**`reference.<name>` is the fourth and last field-source form, legal
only on a `scope: reference` tier's `fields:`** (ORC-236). None of
`draft.<path>`, `mint.<name>` or `mint.parent.<name>` apply: a
`reference`-scope node has no committed draft to project a scalar
from, no minting fanout instance to read a row off, and no committing
parent tier, since it is created directly by a write path outside the
chain (§3.1, §3.2). `reference.<name>` names a key the write path's own
payload supplies directly for that node at the moment it is written —
`ref`'s `title: reference.title` and `body: reference.body` name the two
keys its write path is expected to carry. Engine-side resolution,
unvalidated at load time for the same reason a bare `mint.<name>` is:
there is no schema to check `<name>` against, since the payload shape
is the write tool's to define when it is built, not this tier
declaration's. A `reference`-scope tier declares no `produces:` either,
for the identical reason it declares no `draft:`: there is no committed
body for a fragment's `authored:` value to project from.

**`argument` is a reserved `fields:` name on a flow's entry tier — the
human-readable case for the work, v5 §7.2 — read by the work surface,
never enforced at load time.** `docs/ui-spec.md` §3.1's `ticket`
screen opens on "the argument, first"; a tier's own `fields:` already
supports any name the bundle chooses, so `argument` is not new
grammar, only a name the loader knows to expect at exactly one place —
the tier a flow opens at (`FlowOpened.entry_node_id`) — without
checking that it is there. A type whose entry tier declares no
`argument` renders a blank one on `ticket` rather than failing to
load, the same "declared but absent reads as unset" posture `input.
<role>` and `prior_review` already have; requiring it of every entry
tier at load time would be a protocol change.
`systems/platform_content.md` names which tiers in the shipped bundle
declare it.

Per-scope attributes that appear in *body* declarations rather than
tier files (they vary per node, not per tier): `implementation:
stubbed | real` with `swap: transparent | migration | reset` (v5
§2.16), declared in the comparch grammar. Client-locus components are
not a scope attribute on the backend family — they mint as the
client family's own tier chain instead (v5 §5.1, §5.6).

### 3.1 Scope expressions — closed set

- `singleton` — one node per project.
- `per(X)` — one node per node of tier X. `self.parent` is that node.
- `child_of(X)` — nodes minted by X's fanout edge. `X` is one tier,
  checked at load time: a `type: fanout` instance's target may be
  named by only one source tier (`systems/core_dsl.md#45`), so the
  fanout edge that mints this tier's nodes has exactly one source to
  point at.
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
- **`reference`** — a flat, project-scoped pool of nodes created
  directly by a write path outside the chain, each identified by the
  `id` that write path assigns, never minted by a fanout edge and
  bound to no parent tier (ORC-236). The one shape none of the three
  above can express: `singleton` is one node, `per(X)`/`child_of(X)`
  both need a tier whose own instances drive the count, and a ref —
  the sole tier at this scope today — has neither a fixed count nor a
  minting parent, only an indefinite stream of write-path creations
  (`docs/v5-design-decisions.md` §4.5). Legal only paired with
  `generator: reference` (§3.2); the two exist for exactly one tier
  shape and neither makes sense without the other, and the pairing is
  exclusive on purpose: refs are v5 §4.5's one deliberate escape hatch,
  kept general rather than grown a type system of per-use variants, and
  exclusivity is what stops a second bundle-defined escape-hatch shape
  claiming this same pairing beside it. `generator: external` is not
  such a shape — it is v5 §4.5's own sanctioned exception, already its
  own mechanism rather than a ref variant (§3.2 below).

**Delta from v4: the phased variants (`per(X) × phase`) are removed**
with the phase machinery (v5 §6). There is no `phase` dimension.
`cascade_visit` replaces v4's informal `per(scaffold_tier)` +
`scope_filter: in_cascade_visit_set`
(`seed-docs/catapult-default-bundle-v4-examples.md` §2.1-§2.6): v4's
`scaffold_tier` was never a real tier `per(X)` could name — it meant
"whichever tier the cascade is currently touching" — and
`in_cascade_visit_set` was a platform-managed predicate with no
counterpart in this loader's predicate language (§8). One real scope
kind replaces both.

### 3.2 Generator types — closed set, extension-growable

`llm` (default), `git_commit` (+ `code_repo_url`, `path_from_handle`),
`synthesis`, `webhook`, and the v5 additions: **`external`** (content
resolves from the component registry at the pinned version; requires
`package:` and optional `options:` per v5 §3.4), **`template`**
(deterministic scaffold; requires `template:` path; slots filled from
context walks; no LLM call, same grammar validation), and
**`supplied`** (content resolves from a project-supplied raft artifact
pinned at intake; requires `source: input.<role>`; no draft, no
review, no LLM call — the same "extracted, not authored twice" shape
`external` uses for registry content, but sourced from the project's
own frozen raft instead of the component registry, since there is no
registry publishing versions of a user's own design system —
`systems/core_dsl.md`'s entry), and **`reference`** (content is written
directly by a write path outside the chain — no `source:`, no intake
pin, no fixed content at all until the write happens; no `draft:`, no
`prompt:`, no review, the identical "nothing here for an LLM to author
or a human to gate a second time" shape `supplied` has, for a different
reason: `supplied`'s content is already final at intake, `reference`'s
content is final at the moment its own write lands, and neither has a
draft anywhere in between — ORC-236, ref's new shape,
`docs/v5-design-decisions.md` §4.5). `reference` differs from `supplied`
precisely where `design_system` and `ref` differ: one pinned document,
frozen at intake, versus an indefinite, ongoing stream of write-path
creations with no intake tie at all — sourced differently, gated
differently, and legal only paired with `scope: reference` (§3.1). Its
`fields:` source is `reference.<name>` (§3), not `draft.<path>` — the
same "no committed body to project a scalar from" gap `mint.<name>`
closes for a join-target tier, closed here by naming the write path's
own payload instead.

**The word `reference` names five distinct slots in this grammar, and
none is a variant of another** (ORC-236), the identical
disambiguation §7 below draws for `.synthesis`: `type: reference` is a
member of the edge-type closed set (§4); `edge: reference`
(`bundles/default/edges/reference.yaml`) is a bundle-authored edge
name, no more tied to the word than any other edge is to its own name;
`scope: reference` (§3.1, above) is a tier's node-creation scope;
`generator: reference` (just above) is a tier's content-generation
kind; and `reference.<name>` (§3) is a field source. A tier can combine
several — `ref` itself is `scope: reference`, `generator: reference`,
with `fields:` sourced from `reference.<name>` — but the five are
independent grammar positions, checked and read separately, and
renaming or retiring one leaves the other four untouched.

### 3.3 Review tiers — `reviews: <tier>`

A review is a tier, not a nested block on the tier it reviews (v5
§7.19). Declared like any other tier, with one addition and several
omissions:

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
generation tiers. Critique is off by default, and a workflow bundle's
silence about it means "off," never "on and undeclared": absent a
`critique` entry next to a given `generation` entry, no critique tier
runs there; declaring one is what turns it on, at the depth it names
(§15.5).

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
engine computes, not where it reads — for the same reason a bare
`mint.<name>`'s `<name>` needs none either (§3): there is no body and
no minting instance element for a load-time check to walk against,
since the engine computes the value itself rather than reading it
from either. Unvalidated at load time, but not therefore meaningless.

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

### 4.2 Locating a source or target that isn't `self` — `source_ref:`/`target_ref:`

An instance's `declared_in` names where the *committing* tier's draft
carries the relationship; every example so far has that tier naming
itself as `source` (or, for a fanout, as the tier whose draft names the
`target` it mints). Not every instance is that shape (ORC-236): a
`fulfills` instance can name `comp` as `source` while the relationship
is declared in `sysarch`'s own draft, because `comp` never drafts under
its own name at all (§3's join-target tiers) — the fanout that mints it
already reads the exact element the relationship is declared beside.
Two optional instance-level fields, `source_ref:`/`target_ref:`, name
how to locate whichever endpoint isn't the committing tier itself, from
a closed vocabulary:

- **`self`** — the endpoint is the committing tier's own node. The
  default for `source_ref:` when omitted, unchanged from every
  `<arch> → ref` instance today.
- **`self.parent`** — the endpoint is the committing node's own
  `per(X)`/`child_of(X)` parent, the identical vocabulary `produces:`
  already uses for a fragment's `owner:` (§4). Instance: `fulfills`'s
  `screen_coll → screen` counterpart in `reference.yaml`,
  `screen_collarch.draft.journeys.journey[].@ref`'s `screen_coll` end —
  `screen_collarch` is `per(screen_coll)`, so its own parent is exactly
  the source this instance needs, with no path to navigate for it.
- **`fanout(<edge>)`** — the endpoint is the node minted by `<edge>`'s
  own fanout instance whose `declared_in` is a path-prefix of this
  instance's own `declared_in`. Instance: `fulfills`'s `comp → resp`,
  `declared_in: sysarch.draft.components.component[].responsibilities
  .resp[].@id` — `decomposition`'s own `sysarch → comp` instance has
  `declared_in: sysarch.draft.components.component[]`, a strict prefix,
  so `source_ref: fanout(decomposition)` names `comp` as "whichever
  node this same `<component>` element already minted," read off the
  identical element the trailing path segment is about to navigate
  further from — no second walk, the fanout's own instance element *is*
  the anchor.
- **a `scope: singleton` endpoint** — when the tier named by `source`
  or `target` is itself `scope: singleton` (§3.1), that side needs no
  locator at all, structural or explicit: a `scope: singleton` tier
  holds at most one node project-wide (`scope_key: %{}`), so which node
  the edge means is never in question, the same way `Store
  .get_node_by_scope/3` already resolves every other `scope: singleton`
  read. Instance: `dependency`'s `ui_coll → design_system`,
  `declared_in: ui_collarch.draft.primitives.design-system[]` —
  `design_system` is `scope: singleton` (§3.1, `systems/core_dsl.md`'s
  ORC-110 entry), so `target_ref:` resolves with no path to navigate,
  the identical "there is only one, so naming it is moot" shape
  `self.parent` has for a fixed parent, applied here to a fixed pool
  size instead of a fixed relationship.
- **an explicit path** (`@<attr>`, naming an attribute on
  `declared_in`'s own terminal element — the closed form; the resolver
  implements exactly this and nothing wider) — the endpoint's id is
  read off that attribute. For the six same-tier `dependency` instances
  this form exists for, both endpoints are explicit and both read off
  that same terminal element's own attributes — there is no other
  endpoint's locator to be relative to, since neither side resolves
  structurally. The id is then looked up by identity the same way a
  `reference` edge's trailing `@attr` already is. This is the only form
  that needs a bundle-declared path rather than resolving structurally,
  and it is required whenever neither `self`, `self.parent`,
  `fanout(<edge>)` nor a `scope: singleton` endpoint applies — every
  same-tier `dependency` instance (`comp ↔ comp`, `subcomp ↔ subcomp`,
  and the rest): `sysarch.draft.dependencies.dep[]` shares no prefix with
  `decomposition`'s own `comp` fanout locus, `sysarch`'s own parent is
  `requirements` (`per(requirements)`) rather than either endpoint, and
  neither `comp` nor `comp` again is `scope: singleton`, so both
  `source_ref: "@from"` and `target_ref: "@to"` must be declared
  explicitly, naming the two attributes one `<dep>` element carries. A
  `source_ref:`/`target_ref:` that isn't `self`, `self.parent`,
  `fanout(<edge>)` or this `@<attr>` form — a dotted element path
  included — is a load error naming the instance and the offending
  value, not a silently-unresolved locator.

The side not otherwise resolved defaults to the trailing `.@attr`
segment of `declared_in`, when the instance has one, provided the
*other* side resolves structurally — via `self`, `self.parent`,
`fanout(<edge>)`, or a `scope: singleton` endpoint — widening the
implicit shape every `<arch> → ref` instance already relied on (which
happened to have `source_ref: self`) to every structural case, not
only that one: `fulfills`'s `comp → resp` resolves `source_ref:
fanout(decomposition)` and defaults `target_ref:` to the trailing
`.@id`, the identical default a bare `self` source already got. An
instance whose `source`/`target` isn't `self`, doesn't structurally
match `self.parent`, `fanout(<edge>)` or a `scope: singleton` endpoint,
and declares no explicit locator is a load error naming the instance
and the unresolved side (§13) — a silent `[]` is no longer a legal
outcome of an edge the bundle declared with a non-zero `cardinality`
minimum.

Not every instance of every edge uses this mechanism: `type:
policy_application`'s mint-time-marker instances are not it. Their
`declared_in` (`policy.structural`, `policy.required`) names a marker
on the *minting* instance element itself, not a location in a
committed draft body — `fields:`'s and `mint.parent.<name>`'s own
engine-side resolution (§3) is the precedent, not a `source_ref:`
locator: all of them are read at the same moment and off the same
element a fanout mint already walks, never extracted from a committed
draft under `references/5`'s own mechanism at all. An edge is free to
mix the two: `policy_application`'s citation instances, ordinary
citations of an already-minted policy, name a real `declared_in` path
and resolve exactly the way every instance above does
(`systems/platform_content.md#64`, `systems/generation.md#52`).

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
types the target and names what to read — `.handle` or
`.handle.fragments[<kind>]`. A `context:` entry is ordinarily the bare
walk string; it may instead be a single-key mapping, `{<walk>:
<name>}`, giving the walk its own `as: <name>` prompt variable rather
than inheriting its target tier's name (§9, `systems/core_dsl.md#47`)
— the walk string is unchanged either way, only which YAML shape
carries it. Cardinality-many walks
yield collections; readiness requires **all** targets ready.
Context is the only readiness signal.

**`.synthesis` retires from the projection vocabulary** (ORC-236): no
tier in `bundles/default` ever declared a walk targeting it, and
building a projection with no consumer to design it against would be
exactly the half-finished implementation this grammar otherwise
avoids. `-> <tier>.synthesis` is a load error now (§13), the same shape
any other retired form takes (§11's `extends:`). Two other vocabulary
words share the spelling and are both unaffected, for different
reasons: this is a projection, the target of a `-> <tier>.<kind>` walk,
so the *edge* type `type: synthesis` (§4, an edge an engine-computed
cascade-planning correspondence rides on) is a different slot in the
grammar entirely, not a variant of this one; and `generator: synthesis`
(§3.2, declared by twelve tiers in `bundles/default`: `comp`,
`comparch_policy`, `journey`, `non_goals_policy`, `resp`, `screen`,
`screen_coll`, `screen_subcomp`, `subcomp`, `sysarch_policy`,
`ui_coll`, `ui_subcomp` — `systems/platform_content.md#15`'s split of
the former single `policy` tier into three) names how a
tier's own draft is produced, a third slot again — a tier declaring
`generator: synthesis` says nothing about what any walk *targeting*
that tier may project, and none of the twelve is affected by this
retirement.

### 7.1 Hop chains and reversal

**A walk may name more than one edge, and a hop may be reversed.** A
grammar capping a walk at exactly one `.<edge_name>` before `->`
cannot express a policy scoped **through a responsibility** — comp →
resp (`.fulfills`) → sysarch_policy (inbound `policy_application`) —
since reaching it needs two hops and the second one runs against the
edge's declared direction:

```
self.parent.fulfills.policy_application~ -> sysarch_policy.handle
```

Reads as: `self.parent` (the comp), `.fulfills` (forward — comp is
`fulfills`'s declared `source`, land on the resp it names), then
`.policy_application~` (**reversed** — the trailing `~` means the
walker matches the edge's `target`, not its `source`, and the walk
continues from whichever `source` instance matches: every
sysarch-level policy whose `policy_application` instance targets this
resp). Each hop is
checked independently against the declared edge (or, for a
multi-instance edge, against whichever instance actually matches —
§4.1); a hop naming an edge with no instance on the required side is
a load error, exactly as an unmatched single hop is. A reversed hop
never turns a `navigation: true` edge readiness-bearing — that check
runs on every hop, not just a forward one.

This is engine-side resolution the same way a forward hop is:
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
parent (`vocab`; a project-global policy row, minted into
`sysarch_policy` or `non_goals_policy` — v5 §4.5's first grain,
`systems/core_dsl.md#45` — which by construction has no
`policy_application` edge for a graph walk to follow at all), and a
`cascade_visit`-scoped planning
tier that needs to see the whole component graph rather than one
scoped slice of it (a `refactor` plan reasoning about which
components a structural change touches). The tier named after `all.`
must be declared, and it must not be a tier the *reading* tier itself
drives, directly or transitively (`systems/core_dsl.md#46`) — a tier
can never treat its own pool's readiness as prior to its own, so that
shape is a load error rather than a permanent stall with no
diagnostic. Both are the entire cross-reference (§13) — unlike a
self-hop's target, there is no walker to check either against.

v5 additions:

- **`input.<role>`** — reads the intake documents tagged with a
  declared role. **Four roles are platform vocabulary**: `project_doc`
  (`feature_expansion` and the flow-planning tiers,
  `bundles/default/tiers/*.yaml`), `mocks` (v5 §4.1 —
  `feature_expansion` and `screens` both carry `input.mocks` in their
  own `context:` list, `systems/platform_content.md`'s ORC-110 entry),
  `non_goals` (the negative-space intake distillation reads it as
  strong signal alongside the whole raft, v5 §1.1), and
  `design_system` (v5 §5.4 — read through a `supplied` generator's
  `source:` field rather than a `context:` walk, since the tier it
  feeds has no prompt for `ContextAssembly` to render a variable into;
  `systems/core_dsl.md`'s entry). A project may tag its own raft with
  any other role name for its own bundle content to read — the
  mechanism has no closed registry to violate, and an unread role name
  is simply never walked — but nothing beyond these four is platform
  vocabulary: a project's own role name is that project's declaration,
  not a default every project gets. A role joins the platform set when,
  and only when, a shipped tier is designed to read it — nothing joins
  the set on the strength of a document arguing for it.
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
`completion:` predicate over its own planning tier, which mints one
node per visited scaffold node (§3.1) rather than one singleton:
completion is every visited node's plan resolved, not one node's.
This is engine-side resolution exactly like every other path root in
this language (`has_edge`'s edge name, `count`'s edge name): the
loader checks the predicate parses (§13), not what "refactor_plan"
resolves to at runtime.

## 9. Prompts

Liquid (Solid). Variables: one per named context walk
(cardinality-many walks iterate; an `input.*` walk's is the reserved
word `raft`, below), `self`, `feedback`, `prior_review`, and — review
prompts only — `draft`. `feedback` and `prior_review` render on every
prompt a tier has, generation and review alike; `draft` alone is
withheld from generation prompts (`systems/delivery.md`'s ORC-34
entry pins this against the ambiguity §3.3 leaves). `feedback` is an
ordered list of maps, one per harvested comment — `body`, `locator`
(nullable; `docs/ui-spec.md` §5's v2 per-sentence anchoring is what
supplies it), `author_id`, `posted_at` (`systems/engine.md`'s
`CommentPosted`/`CommentFeedback`) — never a string beside `draft`,
the same representational choice `prior_review` makes below.
`prior_review` is a map — `score`, `findings`, `kind`, `body_sha` —
the node's own most recent review regardless of which draft it landed
against (`systems/engine.md`'s `reviews_for_node/2`); `body_sha` names
which committed body the review applies to, since reading across
drafts on purpose means a prompt can no longer assume it is the
current one. Both render blank via Solid's own unset-is-empty behavior
where nothing has been posted or reviewed yet. A variable's name is
its own `as:` value where the entry declares one, its target tier's
name otherwise (`resp`, `sysarch_policy`, `comp`,
`systems/core_dsl.md#47`); an `all.<tier>` entry (§7.2) gets the same
default name as a self-hop entry landing on that tier, unless either
carries its own `as:`.

**`input.<role>` and `input.*` are the one exception to that rule,
because neither resolves against the graph at all**
(`systems/generation.md`'s intake entry carries the mechanism).
`input.<role>`'s variable is the role name itself — `project_doc`,
exactly as `feature_expansion.md.liquid`'s `{{ project_doc }}` reads
it; `input.*`'s is the reserved word `raft`, joining
`self`/`feedback`/`prior_review`/`draft` in the set of Liquid variable
names a rendered prompt supplies outside a tier's own `context:` — not
load-time-checked against a tier's own target-tier names any more than
those are (§9's `draft` entry above). Both render as a **plain
string**, the pinned document(s) in scope concatenated — never a list
of maps like every other context-walk variable — because an input
document carries no `fields:`/`fragments:` handle to project; it is
free-form prose, rendered as intake pinned it. A role with no pinned
documents renders blank, Solid's own unset-is-empty behavior (the same
convention `feedback`/`prior_review` use above) — never an error,
which is §7's "a role with no documents... never blocks readiness"
carried one layer further, into rendering.

**Two or more context entries sharing a variable name combine into
one collection for that variable** rather than colliding — a tier can
be reached more than one way (`comparch` reads its own already-minted
`comparch_policy` rows through both a direct `policy_application~` hop
and a `fulfills.policy_application~` hop — the same two-hop-reversed
shape §7.1 walks through for `sysarch_policy`, landing here on the
tier `comparch` itself mints into), and the prompt wants every policy
already bound to this comp in one collection, not one variable per
path that produced it — the two entries share no `as:`, so they share
the default name and merge. Two entries merge because they **share a
name**, never merely because they land on the same tier
(`systems/core_dsl.md#47`): giving either its own `as:` keeps them
apart, which is how a tier reads the same target tier for two
different questions without the answers mixing (`comparch`'s own
citable-policy-pool read and its already-applied-policy read both
land on `sysarch_policy`, kept apart by `as:` —
`systems/platform_content.md#64`). Where two merged entries can name
the identical node under different projections (`comparch`'s own
handle-plus-two-dependency-fragment reads before `as:` gave the
handle its own name — `systems/core_dsl.reasons.md#47`), the merge
folds by node id — one rendered entry per node, carrying every
contributing walk's own projected fields — rather than one entry per
contributing walk. Shared
content via `{% render "partials/<name>" %}` (v5 §6: one source for
shared framing across each family's authored tiers). Generation and
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

## 11. Bundle content — fork, tailor, merge upstream

**No bundle carries an `extends:` field, on either axis.** A bundle's
content is exactly what it declares; there is no base layer a loader
composes underneath it at load time. Naming `extends:` in a chain or
a workflow manifest is an unknown field, rejected at load like any
other (§13).

**Fork, tailor, and merge upstream later is the lifecycle bundle
content is shaped for** (v5 §3.1) — git has a merge story hex does
not, and that is what content actually needs: a project wanting one
paragraph changed in a shipped prompt forks the file and pulls later
platform revisions into it by ordinary git merge, with a conflict
when both sides touch the same lines. A load-time layer can only give
whole-file replacement keyed on path, and divergence is invisible
under it — a forked file shows in `git log`; an overridden one shows
nowhere, because a layering loader simply picks the more specific
path. `bundles/`'s platform content, on both axes, is a
**template** a project's own bundle forks from and tailors; nothing
composes it back in underneath at runtime (v5 §6, §7.18). Declarable
review states, deployment environments and work-item types (§15), and
a chain bundle's tiers, edges and prompts alike, are the forked
bundle's own content from the start.

**Chain bundles cannot be split by language: `catapult.yaml` names
exactly one chain.** `Catapult.Dsl.Loader.load_axes/5` builds exactly
one chain from `catapult.yaml`'s `chain:` field — no list — so a
project can never load two independently authored chain bundles side
by side. A polyglot project still has one document graph (components
in different languages depend on each other across the boundary), so
two chain bundles, one per language, would have no composition path
to merge into it (v5 §5.5). Per-platform variation lives inside the
one bundle's own tiers and prompts, never as a second bundle merged
in.

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
follows. Forking composes *content*; it never adds vocabulary — that
is §12's job, and the two mechanisms are deliberately distinct (v5
§9).

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
edge-instance graph; a `type: fanout` instance's target tier named by
at most one source tier across the whole edge set
(`systems/core_dsl.md#45`); cardinality shapes well-formed;
`delivery:` values validated against the protocol vocabulary;
navigation edges absent from readiness walks. A bundle that loads is a
bundle the engine can run; only instance-level constraints (dependency
cycles, cardinality counts) wait for projection time.

Review tiers (§3.3, `docs/v5-design-decisions.md` §7.19):

- `reviews:` names a tier declared in the same loaded union — the
  same cross-reference rule as an edge endpoint or a fragment kind;
- a review tier's `context:` is the same set of walks as the tier it
  reviews — the triad invariant, checked rather than trusted; a
  review tier declaring a walk its reviewed tier doesn't (or missing
  one it does) is a load error naming the mismatch;
- a review tier carries no `scope:`, `draft:` or `produces:` — a
  review tier declaring any of them is a load error, since a review's
  cardinality is `reviews:`'s and it commits nothing (§3.3).

The two axes and the declarable protocol surface (v5 §7.16, §7.18):

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
- **a `pending` entry immediately precedes every generation-shaped
  entry (`generation`, `design`, `architecture` or `implementation`,
  §15.1) — as the first entry of that entry's own sub-array, when it
  sits in one (§15.10); anywhere earlier in the same array, when it
  doesn't — and one `pending` per generation-shaped entry, never one
  shared across several.** A single leading `pending` licensing every
  later generation-shaped entry in the same array would satisfy a
  "somewhere earlier" check while leaving a second or third such
  entry nowhere to wait for dispatch capacity: `pending` is the only
  plane-balled wait position in a ticket's array (§15.1 — there is no
  `fanout` status for a ticket to sit in meanwhile). A `pending` entry
  precedes every `deploy` entry the looser "somewhere earlier in the
  same array" way — `deploy` is never grouped inside a sub-array
  (§15.10's own anchor rule admits only a generation-shaped or
  review-shaped entry, never `deploy`), so there is no sub-array head
  for a `deploy`-licensing `pending` to occupy;
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
  gate, an environment or a `critique` entry (§15.5) alike, one
  grammar checked the same way at all three sites; any other spelling
  is a load error naming the offending value and the declaration it
  came from (v5 §7.19). The never-validated-against-the-chain rule
  above is unaffected: a pair's two positions are still ceilings,
  never claims checked against the chain's actual fan-out.
  **`reconcile` is deliberately not a fourth site** (§15.11): whether
  a given ticket instance runs its own join is derived from that
  instance's position in the doc-graph tree — does it have children
  whose work needs joining — never from a declared ceiling, so a
  `depth:` field on `reconcile` would only ever restate a fact the
  tree already settles, never narrow it the way a gate's or
  `critique`'s own ceiling genuinely can;
- **a `critique` entry must sit immediately after a generation-shaped
  entry (`generation`, `design`, `architecture` or `implementation`,
  §15.1) — immediately after that entry's own `checks`, when the same
  sub-array declares one, and never before it (`checks` runs first,
  so neither an agent's `critique` nor a human gate reads a draft CI
  has not yet validated) — in the same type's `statuses:` array**
  (§15.5) — no skeleton mentioned, and none is needed: whether a
  given array has a generation-shaped entry for a `critique` to pair
  with is a fact about that array's own contents, never about which
  skeleton, if any, the citing type declares, since any type's array
  may hold one regardless of skeleton (§15.2). A `critique` entry not
  adjacent to a generation-shaped entry, or to that entry's own
  `checks` when one is declared, is a load error naming the
  declaration and the position. There is deliberately no `enabled:`
  field anywhere in this grammar: a generation-shaped entry's mere
  absence of an adjacent `critique` entry already means "does not run"
  (v5 §7.19). Neither a gate's, an environment's, nor a `critique`
  entry's `depth:` is read by anything today — scheduling is a later
  consumer (v5 §7.19);
- a gate's forward exit (the next entry in the citing type's own
  array) and its declared escalation policy are well-formed. **A
  gate's own `throwback:`, if declared, must be earlier in the citing
  type's own array** (§15.4, §15.10) — the one load-time check the
  field needs, since it names a single landing point rather than an
  allow-list. An *undeclared* decline's target is a runtime pick,
  checked at the command edge against the same "earlier in the
  effective sequence" bound, never load-time bundle content;
- **a `type:` name is unique in the loaded union, whatever `skeleton:`
  it declares or omits** — `container`- and `ticket`-skeleton types
  and skeleton-less types share one namespace (§15.2);
- **every `container`-skeleton type's `statuses:` array holds the five
  platform-fixed anchor names each at least once, in that relative
  order — `setup`, `prep`, `main`, `retro`, `cleanup` — followed by
  `terminal` exactly once, last** (§15.1: a skeleton fixes a required
  backbone, never an exclusive membership, so a type's array may
  additionally hold anything else the closed vocabulary allows around
  that backbone — a bare generation-shaped entry, a second population
  anchor, gates, environments) — the container analogue of a ticket's
  system statuses, declarable by neither axis for the identical
  re-resolution reason. A missing name, a `terminal` that recurs or
  does not close the array, or the five out of their required relative
  order is a load error naming the declaration and the mismatch;
- **every `ticket`-skeleton type's `statuses:` array opens with
  `pending`, closes with `terminal`, and holds at least one
  generation-shaped entry (`generation`, `design`, `architecture` or
  `implementation`, §15.1, in any combination), `checks`, `merge` and
  `deploy` at least once each, in that relative order** (§15.1) — a
  generation-shaped entry, `checks`, `merge`, `reconcile` and, per the
  pending-precedes rule above, `pending` itself may all recur
  (§15.11); `terminal` alone may not: last, exactly once. **"Opens
  with `pending`" reads the citing array flattened one level** — the
  identical flattening the pending-precedes check above already uses —
  so a first entry that is itself a sub-array whose own first member is
  `pending` satisfies this the same way a bare leading `pending` does;
  a `pending`-first sub-array is in fact the only shape a
  `ticket`-skeleton array's opening entry can take once its own first
  generation-shaped entry is grouped, which is the ordinary case
  (§15.10).
  **`reconcile` is not named in this bullet's own required list, and
  needs no separate ticket-skeleton rule to require it** — §15.11's
  positional check (a `merge` entry must be preceded, earlier in the
  same array, by a `reconcile` entry) already forces one to exist
  wherever `merge` does, for every `merge`, `ticket`-skeleton or
  `container`-skeleton alike, a fact about that array's own contents
  rather than a rule keyed to which skeleton declares it — the same
  shape §15.5's `critique` rule takes. `reconcile` recurring is
  exercised, not hypothetical: §15.11's own worked example carries
  two, one closing the architecture phase's own join and one closing
  implementation, each ordered relative to the phase it closes rather
  than pinned to one array position, and each present in a given
  instance's own effective sequence or not by tree shape rather than
  by a declared ceiling (§15.11). (`deploy` carries no stated bound
  either way — one required occurrence.) A `ticket`-skeleton array
  missing every generation-shaped kind, missing `checks`, `merge` or
  `deploy`, or holding one out of its fixed relative order, is a load
  error naming the declaration and the mismatch; a `merge` entry with
  no earlier `reconcile` entry in the same array is a load error
  naming the declaration and the position (§15.11). **This is a
  load-time check over the declared array, and it is unaffected by
  `merge` being top-level-only at dispatch time** (§15.11): every
  `ticket`-skeleton type still declares its own `merge`,
  reconcile-preceded, exactly as above, whether or not a given
  instance of it ever spawns as something other than the tree's root
  — which instances actually reach that entry is a dispatcher fact
  §15.11 states;
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
- **a bundle carrying an `extends:` field is a load error, on either
  axis** (§11) — there is no base layer left to name.

The unified work-item declaration (§15.2-§15.9):

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
  whatever `skeleton:` it declares or omits** — "all review happens at
  lower levels" is a claim about why a skeleton-less array needs no
  re-resolution anchor, never about what it may contain (§15.2).
  Critique alone stays restricted — see the `critique` adjacency rule
  above;
- **`flow:` and `blocks:` are legal on a population anchor — a
  `status:` entry named `prep`, `main` or `cleanup`, or any `status:`
  entry in a skeleton-less type's array — never on `pending`,
  `generation`, `design`, `architecture`, `implementation`, `critique`,
  `reconcile`, `checks`, `merge`, `deploy`, `setup`, `retro` or
  `terminal`, whatever type's array cites them** (§15.2 — the rule is
  keyed to the entry's own name, never to the citing type's
  `skeleton:`). A population anchor names an open population of
  child work — the query §15.7 describes — so it always needs a
  `flow:` naming what fills it; each of the other kinds named above
  dispatches by a fixed mechanism of its own (a chain-side tier, the
  world, a promotion, or nothing further for `terminal`) that a
  workflow-declared `flow:` would only duplicate or contradict,
  whichever type's array they sit in. `flow:` is required on a
  population anchor and absent everywhere else; `blocks:` is optional
  there and absent everywhere else. A `review:` or `environment:`
  entry carrying either is a load error;
- **`flow:` is required on every population anchor and names a member
  of the type registry above.** There is no second field beside it
  (no `opens:`) telling dispatch from nesting: there is no structural
  difference, on the entry itself, between "this queue dispatches a
  ticket" and "this queue opens a nested instance" for the loader to
  branch on. What the resolved name turns out to be — a type with no
  population anchor of its own (dispatch terminates there, an ordinary
  ticket) or one with at least one (dispatch mints a new instance,
  §15.8) — is visible only from what the *resolved declaration's own
  array* actually contains, never from anything the queue entry itself
  declares, and never from the resolved declaration's `skeleton:`
  alone (a type's skeleton does not determine which of its own
  entries, if any, are population anchors — see §15.2). **A `flow:`
  naming a skeleton-less type is legal**: a skeleton-less type's own
  array is entirely made of population anchors, exactly the property
  that makes any other type nestable, and the declaration graph below
  needs such an edge to catch the cycle it would otherwise miss;
- **no cross-axis load-time check binds a queue's `flow:` value to a
  chain bundle's `flow:` declaration of the same name.** The identical
  non-binding §11 already holds between every other chain/workflow
  pairing, unaffected by the registry existing: a chain bundle
  shipping a flow whose `ticket:` face uses a matching label is what
  makes work actually dispatch there once a type opens, but that
  pairing is convention checked at ticket-open time (an unrecognized
  label opens no flow instance and files `Blocked`/`needs-setup`,
  `docs/v5-design-decisions.md` §7.4), never a loader cross-reference.
  The registry guarantees one thing this pairing does not: `flow:`
  itself always resolves, on the workflow axis alone — there is no
  unresolvable reference left inside the workflow bundle's own graph,
  only the (unaffected, unchecked) question of whether the chain axis
  ever claims the name;
- **a `blocks:` entry names an entry that is unique within the citing
  type's own `statuses:` array — a bare top-level entry, or one that
  belongs to a sub-array, in which case the reference is to the whole
  sub-array** (§15.7: what `blocks:` guards is entry into a group, not
  a population anchor as such, and a group's one non-review-shaped
  agent-balled entry, §15.10, is ordinarily the entry a `blocks:`
  reference names). **Uniqueness is a property of the reference, not
  the declaration it lands on**: a `blocks:` value resolving to zero
  entries, or to two or more (a name reused across separate top-level
  entries, or appearing in more than one sub-array), is a load error
  naming the count found — duplicate entries elsewhere in the array
  that the reference itself doesn't reach are otherwise legal, the
  identical posture every other cross-reference check in this section
  already takes (validate the reference, never the shape). §15.6's own
  scoping rule is unaffected: a `blocks:` entry naming a queue in a
  different declaration, one nested inside what *this* queue's own
  `flow:` opens, or this queue itself, is each still a load error;
- **the declaration graph — nodes are every type with at least one
  population anchor in its own array, edges are `flow:` references
  between them** — must be acyclic, and a type naming itself in one of
  its own population entries' `flow:` is rejected outright as the
  degenerate one-node case of the same rule — checked statically, from
  the loaded bundle alone, before any container instance exists. A
  `flow:` edge whose target has no population anchor of its own takes
  no part in this graph and is always a leaf, never on a cycle — a
  fact about what that type's array actually contains, never read off
  its `skeleton:` alone: a `ticket`-skeleton type may declare a
  population anchor too, and a `container`-skeleton type is not
  guaranteed one just by declaring that skeleton (§15.2). **The node
  set is read from declared entries rather than from skeleton because
  any narrower definition leaves a genuine cycle undetected**: with
  only `container`-skeleton types as nodes, every edge *into* a
  skeleton-less type is excluded by construction, so `milestone`'s
  `main` entry naming `flow: project` and `project`'s `build-out`
  entry naming `flow: milestone` — two nodes and two edges, and a load
  error — would go unbuilt and undetected until some live chain of
  instances happened to close it. This is the check that actually
  bars same-name nesting (a `milestone` declaration cannot open
  `milestone`) and bounds nesting depth: an acyclic graph has a finite
  longest path, so the maximum depth a bundle permits is knowable from
  the bundle itself, even though nesting composes arbitrarily (as many
  distinct named levels as the bundle declares). There is deliberately
  **no further, instance-level check** ("no container is its own
  ancestor") — it falls out of the declaration graph's acyclicity for
  free, and building it separately would leave unbounded depth
  *declarable*, caught only when some live chain of instances happens
  to close the loop, trading a load-time failure for a mid-flight one
  (the same trade this project has already made the other way: v5
  §2.4's "failing at config load beats failing mid-flight");
- **`entry:` is required on every workflow bundle's `bundle.yaml`
  (§2), and must name a `type:` that resolves in the loaded union, is
  a node in the declaration graph above (at least one population
  anchor of its own), and is a root in it** — an absent `entry:`, one
  that doesn't resolve, one naming a type with no population anchor at
  all, or one some other declaration's `flow:` targets, is each a load
  error naming the mismatch (there is no skeleton-keyed special case:
  a `ticket`-skeleton type with no population anchor fails this for
  having no population anchor, not for the skeleton it declares).
  Unlike `role_holders:` and `mirror_mapping:` above, there is no
  later component this field waits on — a bundle author writes it the
  same turn they write the type it names — so it takes no opt-in
  exemption.

Sub-arrays (§15.10):

- **a `statuses:` array entry that is itself an array is a sub-array**,
  and every entry inside one is still exactly one of `status:`,
  `review:` or `environment:` — the existing "exactly one of these
  three keys" rule (above) applies unchanged inside a sub-array, and a
  sub-array nested inside a sub-array is a load error naming the
  position (§15.10's own grammar is flat; nesting is explicitly
  undecided, not silently accepted);
- **a sub-array must hold exactly one entry whose `status:` is a
  non-review-shaped agent-balled system status** (`generation`,
  `design`, `architecture`, `implementation`, `retro` or `setup` —
  §15.1's `ball` column minus `critique` and `reconcile`, both
  review-shaped and excluded for the reason §15.5 already excludes
  `critique` from standing alone: each reviews an entry rather than
  standing as one. `merge` is plane-balled (§15.1, §15.11), so it is
  never a candidate for this count — not a second exclusion beside
  `critique`'s). Any number of review-shaped entries (`critique`,
  `reconcile`) may sit in the same sub-array alongside the one anchor
  — unbounded for the identical reason `critique`'s own count is
  unbounded here. **A leading `pending` does not compete for this
  count either** — plane-balled, not agent-balled (§15.1), so a
  generation-shaped sub-array's own required `pending` head (the
  pending-precedes check above) sits in the same sub-array as its one
  anchor without becoming a second candidate for it. Zero
  non-review-shaped agent-balled entries, or two or more, is a load
  error naming the declaration, the sub-array's position, and the
  count found;
- **No check refuses a population anchor (one carrying `flow:` or
  `blocks:`) inside a sub-array.** A sub-array's one non-review-shaped
  agent-balled entry needs no `flow:` to exist inside a container's
  array (§15.2's unification), so the case such a check would refuse
  does not arise from the shape this grammar gives `setup` and
  `retro`; and nothing else in this section makes a population anchor
  inside a sub-array meaningless, so none is invented for a shape no
  bundle has needed yet;
- **`throwback:`'s own load-time check is unaffected by sub-array
  membership**: whether the citing status
  sits inside a sub-array or not, a declared `throwback:` need only be
  earlier in the citing type's own array — sub-array membership is not
  itself a bound, only a source of the derived default the field may
  override;
- **a `review:` entry inside a sub-array resolves its one-click
  default to that sub-array's own earliest entry** — its own leading
  `pending`, when the sub-array has one (every generation-shaped
  sub-array does, per the pending-precedes check above); otherwise its
  own non-review-shaped agent-balled entry directly (`retro`, `setup`,
  or a generation-shaped entry with no `pending` grouped inside it).
  Computed, never stored, the identical "derive, never hold" posture
  `ready_scopes` and staleness already take. This is a default action,
  not a bound on legality: the full set of legal targets is
  `docs/v5-design-decisions.md` §7.19's own earlier-prefix rule, the
  same one Blocked-return uses, and the check above only guarantees
  the default itself is unambiguous. **A `review:` entry outside every
  sub-array has no such default to resolve to and must declare
  `throwback:` explicitly** (§15.10). **Nor does one sitting inside a
  sub-array but before that sub-array's own earliest entry** — the
  derivation would name a target later than the gate, illegal under
  the earlier-prefix rule this same bullet already defers to, so there
  is no one-click default here either, and the gate must declare
  `throwback:` explicitly the same way (§15.10).

Named positions (§15.12):

- **a `status:` entry's optional `name:` defaults to its `status:`
  (kind) value when omitted** — a plain string, never atomized
  (`Catapult.Dsl.Fields`'s no-`to_atom`-on-bundle-content
  discipline);
- **every name is unique within its own namespace — the top-level
  array, or a given sub-array — whether authored or defaulted.** A
  sub-array's own anchor counts as a member of its own namespace for
  this check; two entries in the same sub-array (or two bare top-level
  entries, or a bare entry and another sub-array's anchor) resolving to
  the same name, one or both by default, is a load error naming the
  declaration, the namespace, and the name found more than once
  (§15.12);
- **a bare reference (`blocks:`, `throwback:`, or any other citation
  into a `statuses:` array) that resolves inside more than one
  namespace is a load error naming the reference and every namespace it
  matched** — never resolved to whichever occurrence comes first.
  Qualifying it `<anchor>.<name>` (§15.12) is what a bundle author
  writes to disambiguate;
- **no declared gate's own name collides with any addressable status
  name, bare or namespace-qualified, in the loaded union** — a load
  error naming both declarations and, when the status name is
  namespace-qualified, the namespace it collided from (§15.12).

Added with `declared_in`/schema cross-validation (ORC-232,
`systems/core_dsl.md`'s ORC-232 entry):

- every `declared_in` path's element and attribute segments are
  checked against the schema of the tier its own **leading segment**
  names, not necessarily the citing edge instance's `source` — a
  join-target tier with no `draft:` of its own (§3) has its
  relationships declared inside whichever tier's draft mints or names
  it, and the path's leading segment names that tier instead. The walk
  follows a `type="Name"` reference into a complexType declared
  elsewhere **in that same schema file** exactly as it follows an
  inline content model — this bundle factors nearly every element into
  a named complexType rather than inlining it, so a same-file `type=`
  reference is the ordinary way a path's second segment and beyond are
  reached, not an exotic one. A segment naming no element or attribute
  the schema declares, under that exact spelling, is a load error
  naming the edge, the instance and the offending segment;
- a segment the check cannot resolve at all — because the schema
  reaches it through a construct the check does not model (`xs:group`,
  `xs:extension`, a type defined in a schema the tier's own file
  imports rather than declares) — is not a load error: an unresolvable
  segment and a wrong one are different failure modes, and refusing to
  load over the first would make the check's own coverage gap the
  bundle author's problem. Only a segment the check positively resolves
  and finds wrong is this check's to catch;
- attribute segments (a trailing `.@attr`) are checked the same way as
  element segments, off the same schema walk — never modeled as
  elements-only with attributes left unchecked.

Added with `source_ref:`/`target_ref:`, `mint.parent.<name>`,
`reference.<name>` and the `reference` scope/generator pair (ORC-236,
`systems/core_dsl.md`'s ORC-236 entry):

- an edge instance whose `source` or `target` differs from the
  committing tier's own name, and does not structurally resolve as
  `self.parent`, `fanout(<edge>)`, or a `scope: singleton` endpoint
  (§4.2), must declare that side's locator explicitly —
  `source_ref:`/`target_ref:` left implicit where none applies is a
  load error naming the instance and the unresolved side, not a
  silently-empty walk;
- a `fanout(<edge>)` locator names an edge in the loaded union whose
  own `declared_in` is a path-prefix of the citing instance's
  `declared_in` — an unknown edge name, or one whose `declared_in`
  isn't a prefix, is a load error naming both instances;
- a `source_ref:`/`target_ref:` naming anything other than `self`,
  `self.parent`, `fanout(<edge>)` or the `@<attr>` explicit form (§4.2)
  is a load error naming the instance and the offending value, not a
  form the resolver silently fails to recognize at runtime;
- an explicit `source_ref:`/`target_ref:` `@<attr>` path gets the
  identical declared_in/schema cross-validation the ORC-232 block
  above runs, against the schema of whichever tier's draft it resolves
  against;
- **a `fields:` or `produces:` entry's `draft.<path>` source gets the
  identical declared_in/schema cross-validation, against the tier's
  own draft schema** — the same walk the ORC-232 block above runs
  against a `declared_in` path, now also run against this second class
  of `draft.<path>` value. A segment spelled wrong against the schema
  that owns it is a load error naming the tier, the field or fragment
  kind, and the offending segment, the identical two-outcome shape
  (resolved-and-wrong vs. unresolvable) the ORC-232 block already uses;
- a `mint.parent.<name>` field source's `<name>` must name one of the
  committing tier's own `fields:` entries or one of its own `produces:`
  fragment kinds — the same cross-reference discipline a context walk's
  target tier already gets, applied to this second, engine-side-
  resolved source form (§3);
- `scope: reference` and `generator: reference` (§3.1, §3.2) are legal
  only paired with each other — a tier declaring one without the other
  is a load error naming the mismatch, since neither shape exists on
  its own;
- a `fields:` entry naming a `reference.<name>` source (§3) is a load
  error on any tier not `scope: reference` — the form exists because
  that scope has no committed draft and no minting instance to read
  from, so it means nothing anywhere else. `<name>` itself is not
  cross-checked against anything, the identical unvalidated posture a
  bare `mint.<name>` has, since the write path's payload shape has no
  schema this loader holds;
- a `reference`-scope tier declaring `produces:` (§3) is a load error —
  the scope has no committed draft, the identical reason it declares no
  `draft:`, so a fragment's `authored:` value would have nothing to
  project from;
- an `all.<tier>` walk (§7.2) may not target a `reference`-scope tier —
  an indefinite, write-path-created pool has no point at which "no
  further node will ever appear" becomes true, so there is no answer
  §7.2's own readiness reading could give; a load error naming the walk
  and the tier, rather than a readiness check with no correct result to
  return;
- an `all.<tier>` walk (§7.2) may not be declared on a tier that is,
  directly or transitively, one of the target tier's own drivers
  (`systems/core_dsl.md#46`) — the reading tier can never make its own
  pool `drained?` prior to its own settlement, so the same deadlock
  `#45`'s driver-uniqueness check exists to prevent recurs one level
  down; a load error naming the reading tier, the target tier, and the
  driver path between them;
- an edge instance's `cardinality` may not declare a non-zero `min` on
  the side naming a `reference`-scope tier, for the identical reason as
  the bullet above: `systems/engine.md`'s own ORC-236 entry evaluates a
  `min` bound only once that side's tier is `drained?/1`, and a
  `reference`-scope tier is never drained — a non-zero minimum there
  could never be honestly evaluated as satisfied or violated, only
  permanently pending. A load error naming the edge instance, the side,
  and the tier;
- a walk whose projection is `.synthesis` is a load error (§7) — the
  form retired with no shipped consumer and no implementation on either
  side of it;
- two context entries on one tier sharing a variable name — whether by
  a shared default or a shared `as:` — but naming different target
  tiers is a load error naming the tier and the two conflicting
  entries (`systems/core_dsl.md#47`): a merge only ever makes sense
  across entries landing on the same tier, never across two;
- an `as:` value matching a reserved prompt variable (`self`,
  `feedback`, `prior_review`, `draft`, `raft`, §9) is a load error
  naming the tier and the entry (`systems/core_dsl.md#47`) — those five
  are supplied outside `context:` entirely, and a same-named entry
  would collide with one silently rather than merge with anything.

## 14. Deliberately absent

Recorded so nobody re-adds them: **phases** (v5 §6 — dropped
entirely); **spawn declarations** (a plane rule keyed to the plan
naming its own children, not bundle content, and not a status
transition — `docs/v5-design-decisions.md` §7.10, §7.15); **derived
fragments** (context
walks at read time); **bundle-side code or open predicates**; **per-
project restructuring of the *automation* protocol** (v5 §7.10,
§7.16, §7.18) — review gates and deployment environments are
declarable in a workflow bundle, while the automation graph, and the
agent and queue states composing it, stay platform-fixed. Also
absent: **any cross-axis reference** — a `gate:` on a
tier, a tier name in a gate, a `requires_gates:` manifest key. All
three assume the chain and workflow bundles are a matched pair; they
are not, and composability with no shared vocabulary is the property
being protected (v5 §7.18). And a **second bundle system** for
delivery configuration (v5 §9, §7.18 — one language, two document
kinds). On a review tier specifically (§3.3): **`review_path:`**
(v4's paired `body_path:`/`review_path:`, `docs/v5-design-decisions.md`
§7.19 — a review projects to comments, never a committed file) and
**a per-tier `required:` gating flag** (threshold-based gating is a
parked scheduler item, §7.19, not bundle content).

**A milestone boundary ticket** (`docs/v5-design-decisions.md`
§7.8): what is absent is the *pause-proxy* — a ticket standing in for
container state a borrowed tracker had nowhere else to hold, because
orchestration has no tracker of its own. Catapult owns its tracker
(v5 §7.17), so a container's progress is state on the container
entity itself (§15.2), and there is nothing for a proxy ticket to do.
**This is not the same absence as "no retro."** The retro pass is
present, as an ordinary work item dispatched through a milestone's
`retro` queue (§15.7) like any other flow instance: the
ticket-as-state-proxy is absent; the ticket-as-work-item is not.

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

**An `archive`-precedes-every-declared-queue load check.** Such a
check would guard, for the reason above, against a scan reading
ticket data an unarchived-first sequence hadn't yet made durable.
With archiving policy rather than protocol, and containers never
losing their references to archived work, the failure it would catch
cannot occur — keeping a check without its reason is the mistake
`docs/v5-design-decisions.md` §7.8 already argues against elsewhere.

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
| `implementation` | a generation run producing code against an approved architecture | agent |
| `critique` | an agent run reviewing a freshly produced draft | agent |
| `checks` | CI running against produced work | world |
| `reconcile` | reads the produced PR against its own argument, before merge | agent |
| `merge` | mechanical join into the parent branch, once reconcile approves | plane |
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

**`design` and `architecture` are named generation kinds — members
of the fixed table, not a new mechanism.** Both are generation-shaped
in every rule this section and §13 state for `generation` itself —
agent-balled, `pending`-preceded, requiring a blocked exit,
recurrable, eligible for critique pairing (§15.5) and for a
sub-array's one non-review-shaped agent-balled entry (§15.10) — and
"a generation-shaped kind" means these, `generation` included,
wherever this document uses the phrase. Plain `generation` stays the
right choice for a type with exactly one generation-shaped visit —
`setup`, `retro` and `seed` all declare it. The two named kinds exist
for a type that wants more than one visit distinguishable from the
array itself: v5 §7.6's own feature lifecycle describes two —
*Product design* and *Architecting* — and two indistinguishable
`generation` entries can only say which is which by position and by
the gates around each. `design` and `architecture` let the array say
it directly: a type wanting the two-visit shape writes
`status: design` for the first and `status: architecture` for the
second, each grouped with its own critique and gates into its own
sub-array (§15.10) exactly as a bare `generation` entry groups —
**each generation's own review steps sit inside that generation's own
sub-array**, whichever kind anchors it, never spanning two.

**`implementation` is a third named generation kind, on the identical
footing.** `checks` is world-balled CI against produced work (this
table, above): a type that dispatches a tier's own code through a
bare `checks` entry has nothing in its array that ever writes the
code `checks` then runs against. `implementation` names the
generation run that actually produces it, generation-shaped
everywhere the phrase means (agent-balled, `pending`-preceded —
inside its own sub-array, §13 — recurrable, eligible for critique
pairing and for a sub-array's own anchor), the identical footing
`design` and `architecture` stand on. **It is deliberately gateless
in the default bundle, and the reason is recorded rather than left as
a bare omission**: v5 §7.10's touchpoint budget calibrates a feature
to two author gates, product and architecture — a third, keyed to
implementation, is the "restricted scopes carry a third touchpoint"
exception (v5 §7.10), not the ordinary case, because architecture and
policy are what constrain intention narrowly enough that no ordinary
scope needs a human reading the code it produces. A workflow bundle
wanting a gate after `implementation` anyway simply declares one — the
grammar refuses nothing here — but the shipped default earns its
gatelessness from that budget rather than assuming it.

**`reconcile` is a named review-shaped kind.** Every kind this table
names is either **generation-shaped** (`generation`, `design`,
`architecture`, `implementation`) — an agent run originating an
artifact — or **review-shaped** (`critique`, `reconcile`) — an agent
run judging one that already exists. Both are agent-balled; what
tells them apart is which side of "does this run produce the
artifact or read it" each one sits on, and "a review-shaped kind"
means these two, wherever this document uses the phrase. `reconcile`
is what §7.5's own "reads the child PR against the child's argument…
reads the feature PR… against the feature's argument"
(`docs/v5-design-decisions.md`) describes, and
`Catapult.Dsl.SystemStatus.agent_steps/0`'s `:reconcile` is its agent
step. Without a status kind of its own, a chain tier could declare
`agent_step: reconcile` but had nowhere legal to put
`phase: reconcile`, so the only kind available to pair it with was
`merge`, the same kind the *mechanical* join into the parent branch
also used. One kind carrying both a judgment and a mechanical effect
is exactly the seam that had
`Catapult.Delivery.ContainerLifecycle.inline_dispatch_point?/1`
excluding `merge` **by name** rather than by anything declared, in a
module whose own moduledoc asserts it branches on no status name at
all. Splitting the kind removes the exception rather than documenting
it: `merge`'s own `ball` is `plane` in the table above — mechanical,
effected by the plane itself the moment `reconcile` approves, barring
a conflict (which routes to `Blocked` the ordinary way any
agent-balled entry's failure does) — so a non-review-shaped
agent-balled filter excludes `merge` because it is not agent-balled
at all, never because its name is checked. **Unlike `critique`,
`reconcile` is not opt-in — and the fact is stated positionally, not
as a ticket-skeleton requirement.** A generation-shaped entry with no
adjacent `critique` runs no auto-review at that phase (§15.5);
nothing merges, `ticket`-skeleton or `container`-skeleton alike,
without first having been read against its own argument (v5 §7.5),
the same unconditional way every ticket's diff runs CI before it
merges. §15.11 states the mechanism: **a `merge` entry must be
preceded, earlier in the same array, by a `reconcile` entry** — a
fact about that array's own contents, checked the identical way
regardless of which `skeleton:`, if any, the citing type declares,
rather than a rule bolted onto the ticket skeleton's own
required-backbone list (§13). `reconcile` may recur the same way a
generation-shaped entry and `merge` can, each occurrence ordered
relative to the `merge` (or the deeper phase) it closes rather than
pinned to one array position — §15.11's own worked example carries
two. `reconcile` carries no `depth:` of its own, unlike `critique`
and a gate (§15.11 states the reason: whether a given ticket instance
runs its own join is a fact about that instance's position in the
doc-graph tree, not a fact a declared ceiling would do anything but
restate). Presence itself is not the field that turns `reconcile` on;
there is no entry to omit, only a `merge` left with nothing to pair
it with. Not a `docs/non-goals.md` entry, for the identical reason
`design`/`architecture` are not one: growing this closed table is
covered by that file's own admission rule ("a state may be declared
iff no plane logic branches on it") without needing a new line,
because the table itself, not what's declarable *from* it, is what
grows.

**`fanout` is not a member of this table.** It named a status the
feature ticket sat in "while children in flight, progress rolls up,"
but nothing ever dispatched from it: the shipped default bundle's own
`types/feature.yaml` carries no such anchor
(`lib/catapult/delivery/feature_lifecycle/sequence.ex` records
`checks` as the phase's own trailing sentinel, the role `:fanout`
played before the bundle migration removed it). §15.11 states why a
wait-status has nothing left to do once architecture's own fan-out
dispatches through the child-ticket tree rather than through
scope-runs inside one ticket: a parent that cannot yet enter its own
`reconcile` (§15.11) is a load-bearing *precondition* on a real
status, not a status of its own to sit in meanwhile. **This is an
absence of the status kind alone.** The edge type of the identical
name — `Catapult.Dsl.Edge`'s `@types` list, `edge_type: :fanout` on a
draft-committed event, node-id minting "at fanout time" — is the
mechanism architecture's own generation tier uses to mint the
doc-graph nodes a chain fans into, and nothing about it names, or is
named by, the status. `docs/v5-design-decisions.md` §7.9's "no
phases" list and §14's "deliberately absent" entries name neither:
`fanout`-the-status is a struck member of this table, not an absence.

**Platform-fixed in the same table `generation` already sits in — not
bundle-authored, and not a second table.** This is what keeps this
section's own cutover re-resolution intact: the anchor set a blocked
work item re-resolves against can only be what it is *because* it is
not declarable (this section's opening paragraph) — a bundle inventing
its own generation-phase label would be exactly the undeclarable
anchor set acquiring a declarable member, breaking the property that
makes it a re-resolution anchor at all. A fixed set of additional
names does not: `design`, `architecture` and `implementation` are
checked the identical way `generation` already is, everywhere
`generation` is checked. Which of a bundle's own generation-shaped
tiers picks `generation`, `design`, `architecture` or `implementation`
— `sysarch`, `impl`, `ref` and the rest of `bundles/default/tiers/**`
among them — is bundle content, `bundles/**`, not a mapping this
table assigns. **Named kinds, not one per tier, and none for a target
class this platform doesn't build for — a scope local to this table's
own growth rule, not a `docs/non-goals.md` entry.** That file carries
no such entry, and the nearest two — "No LiveView/React mixing within
one frontend target" and §1's audience line — answer a different
question, so it is not cited here. This table grows by the names the
shipped chain's own lifecycle already needed, never by a per-tier
scheme guessed at against tiers that don't exist yet, and not by a
second table or a per-dialect one held in reserve against a
possibility — if a non-software target ever arrives it brings its own
skeleton and its own status names, the identical posture §15.1
already takes toward `container`'s own five-anchor sequence. The
reason is local to this table, the way §15.10 below is local to a
sub-array's own reference rule: it spans no other system and every
pass need not see it, so it stays here rather than in the
cross-system file.

**`pending`, not `queue`.** A single work item's own wait-for-dispatch
status and a container's own named queue position (§15.2) can appear
in the same declared array, so they cannot share one word. `pending`
carries the fixed-vocabulary meaning exactly — "committed, awaiting
dispatch capacity" — and "queue" is reserved for the sense the rest
of this section needs it in. This is Catapult-local DSL vocabulary
rather than orchestration's protocol
(`internal/protocol/protocol.go`'s `AllStates` has no `queue`
member), so the name lives in this file and
`lib/catapult/dsl/system_status.ex` and nowhere in the two-repo
protocol.

**A `pending` immediately precedes every generation-shaped entry
(`generation`/`design`/`architecture`/`implementation`), as that
entry's own sub-array head, and precedes every `deploy` entry
somewhere earlier in the same array** — a load-time check (§13's own
bullet states the tightened, per-sub-array form in full), not a
convention. **`stubbed` is exempt from staleness and escalation** (v5
§7.6): nothing is stale about waiting deliberately.

Mapping onto v5 §7.6's lifecycles, which are this vocabulary with
every review sequence at length one and `critique` left out of the
picture — an internal agent step every generation-shaped visit may or
may not pair with (§15.5's opt-in), never a tracker-facing state this
simplified view distinguishes — feature: `Todo`(pending) →
`Product design`(design) → `Checks`(checks) →
**Product review**(review) → `Todo`(pending) →
`Architecting`(architecture) → `Checks`(checks) →
**Architecture review**(review) → `Reconciling`(reconcile) →
**Architecture synthesis review**(review) → `Todo`(pending) →
`Implementation`(implementation) → `Checks`(checks) →
`Reconciling`(reconcile) → `Merged`(merge) → `Validating`(validating)
→ `Shipped`(terminal). Child (the ordinary case — a generic child
entering directly at implementation, §7.3's entry-tier taxonomy;
architecture's own recursive fan-out runs a second, richer type this
one-line mapping does not inline, §15.11 below): `Ready for
dev`(pending) → `In progress`(generation) → `Checks`(checks) →
`Reconciling`(reconcile) → `Merged`(merge) → `Done`(terminal), with
`Ready for rework`(pending) / `Reworking`(generation) as the repair
loop. The bolded gate names are the platform workflow layer's default
review declarations, not system statuses — which is what makes them
replaceable. **`Architecture review` and `Architecture synthesis
review` are two distinct declared gates**: they review two different
things (a tier's own artifact, then what its `reconcile` has joined,
§15.11), one gate cited both before and after a `reconcile` reads as
the same review running twice, a gate needs a name of its own to be
addressed at all once a bundle can author a status entry's own name
the identical way (§15.12), and a position told apart only by which
side of `reconcile` it sits on is exactly the second level of
qualification that section refuses. **`Product design` and
`Architecting` name the `design` and `architecture` kinds directly**;
the child lifecycle's own single visit (`In progress`) has nothing to
distinguish and stays plain `generation`, the correct choice for one
visit. **`Reconciling` and `Merged` name the `reconcile` and `merge`
kinds directly**, each with its own name, and neither recurs to say
what the other already says. **`Implementation` names the
`implementation` kind directly** — the state between architecture
review and `Checks` is dispatched work, not a bare `checks` entry.

**This mapping and §15.2's `types/feature.yaml` describe the same
type, and are edited together.** Each is one fact in two forms rather
than two facts that happen to agree today — a change to either one is
incomplete until the other reads the same way. The practice exists
because the two disagreed across five consecutive design-review
rounds, each round correcting one statement and leaving the other
stale: about `merge`, then the reconcile count, then `checks`'s own
position, then the child lifecycle's own shape, then `pending`, where
this mapping showed one `Todo` against `feature.yaml`'s three, one per
generation-shaped sub-array's own required head (§13's tightened
pending-precedes check) — a load-error shape stated as a tracker
lifecycle. The mapping above carries a `Todo` and a `Checks` for each
of the three generation-shaped visits, matching the array exactly;
`checks` sits before its review the same way it sits before
`critique` in the array itself, above.

**There is no `Building` state in this mapping.** The feature's own
implementation is real dispatched work, `status: implementation`,
not a wait: it runs on the identical ticket, immediately after
architecture review passes, the same way the feature's own
architecture phase already ran on it. What a `Building` state would
signal — that children are still in flight — is never a period the
feature itself needs to *do* anything in; it is `reconcile`'s own
entry precondition (§15.11's two interlocking rules), not a status of
its own to sit out. Once the feature's own `implementation` entry
completes and its `checks` passes, the ticket sits at `Checks` for as
long as its children take to finish their own subflows — visibly, by
name, requiring no separate status to do it in.

**Two fixed skeletons, and `skeleton:` is optional — there is no
third value standing for "neither."** A declared work-item type
(§15.2) may select a `skeleton:` of `ticket` or `container`, which
fixes which of the anchors above its `statuses:` array must contain,
each at least once, in the relative order given here — never their
names, their presence, or (bar the exceptions §15.4 and §15.5 name)
how many times each may appear:

- **`ticket`** — `pending`, then any interleaving of a generation-shaped
  entry (`generation`, `design`, `architecture` or `implementation`,
  each optionally paired with a `critique` entry, §15.5) and declared
  gates (§15.4), then `checks`, `reconcile`, `merge`, `deploy`
  (optionally paired with declared environments, §15.4), then
  `terminal`. A generation-shaped kind, `checks`, `reconcile` and
  `merge` may all recur — v5 §7.6's own feature lifecycle above
  already visits a generation-shaped kind three times, as `design`
  (`Product design`), `architecture` (`Architecting`) and
  `implementation` (`Implementation`), and §15.11's own worked example
  visits `reconcile` twice across the type, once per phase it closes —
  architecture's own join, then implementation's own, never twice
  within either phase alone — `terminal` may not recur: last, exactly
  once.
  **`pending` may recur, once per generation-shaped entry's own
  sub-array** (§13's own tightened check, below): the array still
  *opens* with `pending` (flattened one level, the identical reading
  §13's other sub-array checks already give a leading entry), but a
  second or third generation-shaped sub-array carries its own leading
  `pending`, not a shared one earlier in the array standing in for all
  of them.
  **`reconcile` is required wherever `merge` is, unlike `critique`,
  which is opt-in** — not a fact this bullet states as a
  ticket-skeleton rule, but §15.11's positional one: a `merge` entry
  needs an earlier `reconcile` in the same array whether or not a
  bundle also wants critique or a human gate anywhere upstream of it.
- **`container`** — five fixed names: `setup`, `prep`, `main`,
  `retro`, `cleanup`, each at least once, in that relative order, then
  `terminal`, exactly once, last. This is the container analogue of
  the ticket skeleton, for the identical re-resolution reason: the
  anchor a container parked mid-sequence falls back to when a
  workflow cutover changes what a queue dispatches underneath it. A
  container currently at `main` stays at `main` across the cutover;
  only which type `main` now dispatches changes.

**A skeleton fixes a required backbone, never an exclusive
membership.** There is no practical reason a container cannot contain
a generation: the five names above are what `container` *requires*,
not the whole of what its array may hold, and the ticket skeleton's
own list above is read the identical way, symmetrically. A type's
array may additionally interleave any other entry this closed
vocabulary allows — a bare `generation` (paired with `critique`
exactly as §15.5 already allows anywhere), a `checks`/`merge`/`deploy`
run, or a population anchor (`prep`/`main`/`cleanup`) opening a
nested queue of its own — around its required backbone, whatever
skeleton it declares or omits, subject only to the positional rules
those kinds already carry elsewhere in this section (critique
immediately after its generation, or after that generation's own
`checks` when the same sub-array declares one, never before it,
§15.5; a `pending` earlier in the same array than every generation or
deploy it licenses, above). The fixed anchors' own "each at least
once", "each exactly once" and ordering rules are unaffected by this
— see §15.2 for what this does and does not mean for nesting.

**A type with no `skeleton:` has no anchors at all.** There is no
`skeleton: none` value: it would spend a value on exactly the fact
the field's own absence already states, and make "is this the one
`none`-skeleton declaration" a bundle-wide fact a value had to police
rather than a structural one the loader can see for itself (§15.6).
Its `statuses:` array is entirely author-declared queue positions, in
whatever order and count the bundle wants, with no re-resolution
anchor to preserve and no fixed relative order to check. This is the
project's shape (§15.2): a project needs no anchor because all review
happens at lower levels and a project changes shape rarely enough
that a workflow cutover mid-project is not the hazard a cutover
mid-container is.

**The project's special case is rootness, not skeleton.** Omitting
`skeleton:` buys a type exactly the two things above: no re-resolution
anchor to preserve and no fixed relative order to check, because
nothing forces a workflow cutover mid-project the way one forces a
container's own parked position to resolve against a fixed anchor
set. Both hold regardless of which other entries that type's array
happens to hold — a skeleton-less type is free to interleave gates,
environments and population anchors in any order it wants (§15.2).
What actually makes the outermost project the project — that nothing
else's `flow:` targets it — is §15.6's rootness, a fact about the
declaration graph, not about `skeleton:` at all: a bundle can and
does declare other skeleton-less or `container`-skeleton roots
(`epic`, say) without either being "the project." Rootness, not the
absence of a skeleton and certainly not the presence of queues, is
the one thing that generalizes.

**Agent steps**, the other half of what a chain's `delivery:` block
may name (§3): `design` (produces a design-graph artifact for a
tier), `dev` (implements a child scope), `critique` (the review pass
over a freshly produced draft), `reconcile` (reads a produced PR
against its own argument), `validate` (§7.11's repair loop). Adding
one is a platform change, reviewed as one. **This list is independent
of the kinds table above.** The two axes answer different questions —
`agent_step` says what broad category of run a tier is, `phase`
(checked against this table's own `kinds/0`, not `agent_steps/0`)
says which position in a workflow's array dispatches it — and a tier
producing an architecture artifact is still, categorically, a
`design`-agent-step run; only its `phase:` picks `architecture` over
the undifferentiated `generation`. **`reconcile` is the one agent
step with a matching `phase:` of the same name, symmetric with
`critique`'s `phase: critique, agent_step: critique` pairing**:
`phase: reconcile, agent_step: reconcile` is the direct spelling, and
`merge` is not a phase any chain tier's `delivery:` names, since
nothing is agent-dispatched at it (§15.1 above).

**There is no `boundary` agent step, and nothing stands in its
place.** "The milestone pass" as a single static agent step is one no
tier's `delivery:` has reason to name — a milestone close is not a
chain tier's business — and the staticness is the underlying problem.
A container's progress is a declared sequence of queues
(§15.2-§15.8), not one fixed pass; the work a `boundary` step would
hide — the retro backward-looking pass and, at a container's own
fanout into a nested one, the forward-looking setup pass
(`docs/v5-design-decisions.md` §7.8) — dispatches as an ordinary flow
instance through a queue's declared `flow:`, the same mechanism as any
other ticket, needing no reserved slot in this closed set.

### 15.2 One work-item declaration: `types/<name>.yaml`

**A container is a work item whose skeleton fixes queue anchors. A
ticket is one whose skeleton fixes a generation anchor. Neither fact
bounds what else either one's array may hold, and the grammar gives
them one declaration shape, not three.** A milestone with a `main`
queue, then a human sign-off gate, then a staging deployment, then
`retro` is an ordinary sentence this grammar can say; there is no
reason a container should be unable to carry a gate, a deployment, or
a generation merely because each shape could be given its own file
and its own rules. **There is no practical reason a container cannot
contain a generation**: the `setup`/`retro` fold below is the
motivating case, but the rule is general — the container/ticket split
is not a functional one, only a naming convenience for which backbone
a declaration's array is required to carry.

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
  - - status: pending            # setup's own leading entry (ORC-155) —
                                  #   not a grammar requirement, since
                                  #   setup is not generation-shaped
                                  #   (§13), but the identical
                                  #   dispatch-wait convention, authored
                                  #   for the identical reason
    - status: setup               # the container's own agent step,
                                  #   inline (ORC-148) — dispatches by
                                  #   chain-side tier, not by flow:
    - review: kickoff-review      # a human reads the milestone's own
                                  #   plan before prep/main ever open
                                  #   (ORC-155) — named for what it
                                  #   reviews, never for the anchor it
                                  #   sits beside (§11)
  - status: prep
    flow: feature
  - status: main
    flow: feature
    blocks: [retro]
  - - review: milestone-signoff   # a declared gate (§15.4), positioned
                                  #   here
    - status: pending             # retro's own leading entry, the
                                  #   identical dispatch-wait convention
                                  #   setup's group takes above (ORC-155)
    - status: retro                 # the container's other agent step,
                                  #   inline the identical way
    - review: proposals-read
  - status: cleanup
    flow: feature
  - environment: prod             # a citation, not a declaration — a
                                  #   citing entry carries the name
                                  #   alone (§15.4); `promote_from:`
                                  #   lives on environments/prod.yaml's
                                  #   own declaration (bundle content,
                                  #   dev's). A new declared environment
                                  #   (§15.4, ORC-155): every feature
                                  #   already deploys itself to staging
                                  #   on its own account (below); this
                                  #   is the milestone's own promotion
                                  #   of the whole, once retro's
                                  #   findings are adjudicated and
                                  #   cleanup is done
  - status: deploy
  - status: terminal
```

**`setup` and `retro` above carry no `flow:`** — each is the
container's own inline agent step, not a `flow:` naming a separately
minted child type (§15.10 works the full shape, grouped with the
gates around `retro` in the real bundle). `pending` is not part of
`container`'s own fixed backbone (§15.1); **both `setup` and `retro`
lead their own sub-array with a `pending` of their own — an authored
choice, not a grammar requirement**: neither `setup` nor `retro` is
generation-shaped (§13's tightened pending-precedes bullet reaches
only `generation`, `design`, `architecture` and `implementation`), so
nothing here forces it, but the identical dispatch-wait convention
every generation-shaped sub-array already carries is worth giving
each agent step too, since each is a named, addressable entry in its
own right (§15.12) rather than a bare, unnamed kind occurrence.

`setup.pending` and `retro.pending` share a bare name and nothing
else. §15.12's namespace-qualified identity is what a position *is*,
not only what the loader's own cross-reference resolution checks at
load time: `Catapult.Delivery.ContainerLifecycle.Sequence`'s lookups
resolve that same qualified `<anchor>.<name>` identity
(`systems/delivery.md`'s ORC-116 entry), and `container.current_queue`
— the value every dispatcher comparison reads — carries it end to end
too (`systems/delivery.md`'s ORC-171 entry). A container resting at
`retro`'s own `pending` is never resolved as `setup`'s.

**Neither `setup` nor `retro` carries `checks`, `merge` or
`reconcile`, because neither produces code.** `setup` pushes the
milestone's own kickoff work to `prep`; `retro`'s findings push to
`cleanup`, and the docs-pruning pass is an ordinary `cleanup` ticket
rather than something `retro` runs and merges directly. The
merge-preceded-by-reconcile rule (§15.1, §15.11) reaches this
declaration the moment it holds a `merge` — an agent step merging
through a bare `checks → merge → deploy`, read by nothing first, is
exactly the unread-merge gap it refuses — but with nothing either
agent step itself produces left to check or join, this declaration's
own array holds no `merge` at all: **feature flows (`prep`, `main`)
are the only things that merge**, each through its own `feature.yaml`
instance, never through `milestone`'s. `setup` has a review gate of
its own instead — `kickoff-review`, named for what it reviews rather
than for the anchor it sits beside (§11) — the same kind of human
checkpoint `milestone-signoff` gives the other side of the
container's own working period, before `retro`.

**`deploy` sits after `cleanup`, with the `environment:` entry §15.5
requires.** With `setup` and `retro` promoting nothing of their own,
the milestone's single `deploy` promotes the milestone as a whole — to
`prod`, a declared environment (§15.4, its own `promote_from: staging`
on `environments/prod.yaml`'s declaration, not on the citation above)
— once every feature nested under `prep`/`main` has already deployed
itself individually to `staging` through its own `feature.yaml`
(above) and `retro`'s own findings are adjudicated and closed out
through `cleanup`.

```yaml
# types/feature.yaml. §15.11 works the separate type a component/
# subcomponent instance runs, which this declaration does not
# depth-fan into (below)
type: feature
skeleton: ticket
statuses:
  - - status: pending           # the design sub-array's own head,
                                 #   required (§13's tightened check)
    - status: design
    - status: checks            # this instance's own CI on its own
                                 #   produced draft — docs-phase, so
                                 #   ci:docs rather than ci:code (v5
                                 #   §7.10), the identical CI-selection
                                 #   rule applied here that already
                                 #   applies to any other checks entry.
                                 #   Runs before critique, not after
                                 #   (§15.5): neither an agent nor a
                                 #   human should read a draft CI has
                                 #   not yet validated
    - status: critique
    - review: product-review

  - - status: pending           # a second, independent pending —
                                 #   this sub-array's own, not the
                                 #   design group's shared with it
    - status: architecture      # this instance's own artifact — the
                                 #   feature-level sketch (sysarch);
                                 #   comparch/subcomparch are a
                                 #   separate type's own instances,
                                 #   spawned as children (§15.11)
    - status: checks            # before critique, the identical
                                 #   ordering the design group above
                                 #   uses (§15.5) — and, incidentally,
                                 #   the state reconcile below reads:
                                 #   nothing modifies the draft between
                                 #   here and there
    - status: critique
    - review: architecture-review     # before reconcile: this
                                       #   instance's own artifact

  - status: reconcile               # joins this feature's own
                                     #   children's merged
                                     #   architecture docs, bottom-up
                                     #   already complete by the time
                                     #   this entry runs (§15.11) — the
                                     #   flat backbone, not the group
                                     #   above (§15.11's "not a
                                     #   sub-array" paragraph)
  - review: architecture-synthesis-review  # after reconcile: the
                                     #   joined set — a separate
                                     #   declared gate (§15.4), not
                                     #   the same one cited twice
                                     #   (ORC-155, §15.12): the two
                                     #   review different things and
                                     #   now say so by name

  - - status: pending
    - status: implementation    # this instance's own code — no gate:
                                 #   architecture and policy already
                                 #   set intention narrowly enough that
                                 #   no ordinary scope needs a human
                                 #   reading it (v5 §7.10's touchpoint
                                 #   budget; §15.1)
    - status: checks            # before critique (§15.5)
    - status: critique

  - status: reconcile         # joins the feature's own children's
                               #   merged implementation — flat, the
                               #   identical reason as above

  - status: merge                # fires here because the feature is
                                  #   always the tree's own root — a
                                  #   non-root instance's identical
                                  #   declaration merges when *its*
                                  #   parent enters reconcile instead,
                                  #   never by reaching this entry
                                  #   itself (§15.11)
  - environment: staging          # a citation, not a declaration — the
                                   #   name alone; `promote_from: dev`
                                   #   lives on environments/staging.yaml's
                                   #   own declaration (§15.4), not here
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

**What `skeleton:` actually selects.** Giving a container, a project
and a ticket each its own file format would manufacture differences
that are artifacts of the split, not facts about queues or
generations. What is real, expressed as `skeleton:` rather than as a
choice of file:

- **the skeleton's own required backbone** (§15.1) — `pending →
  generation → checks → reconcile → merge → deploy → terminal`, each
  at least once and `terminal` exactly once, last (`pending` recurs
  once per generation-shaped entry's own sub-array, §13's tightened
  check; `reconcile` itself named by position, not by this bullet —
  §15.11's rule that a `merge` entry needs an earlier `reconcile` is
  what actually requires it),
  against `setup → prep → main → retro → cleanup → terminal`, each at
  least once, against no fixed shape at all for a type with no
  `skeleton:`. This is the reason `container` and `ticket` are
  different `skeleton:` values rather than one — it is the only thing
  left that they are. **`reconcile`'s own requirement is not one of
  those things**: it reaches the `container` column too, the moment
  that array holds a `merge` — a conditional, not a standing fact
  about every `container`-skeleton array, and the shipped `milestone`
  declaration above does not exercise it, holding no `merge` since
  `setup` and `retro` produce nothing to merge. `feature.yaml`'s own
  `merge`, above, is the record's live example of the rule this bullet
  states.
- **can source a nesting edge** — any type whose array holds at least
  one population anchor (a `status:` entry carrying `flow:`, §15.7)
  can point at another container; a type with none is always a leaf in
  the declaration graph (§15.6). This is a fact about a declaration's
  own entries, not about which `skeleton:` it names: a
  `ticket`-skeleton type's array may hold a population anchor, so the
  fact has to be checked directly rather than read off the skeleton.
  The grammar does not refuse a `ticket`-skeleton type nesting another
  container, any more than it refuses a container holding a
  generation.
- **critique's admission** — a `critique` entry must sit immediately
  after an actual `generation` entry — or that entry's own `checks`,
  when the same sub-array declares one, never before it — in the same
  array (§15.5), whichever type declares it. A positional rule,
  checked against whatever a type's array actually contains rather
  than against what its skeleton implies that array could contain.

Nothing else — which file a declaration lives in, or whether its
array is a registered set or a fixed sequence — is a rule to check.

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
admitted rather than refused on a premise that does not reach it.
Critique alone stays gated, and for a reason unrelated to the one
above: a `generation` anchor is what gives its depth something to
select within, so a `critique` entry is only ever legal immediately
after an actual `generation` entry — or that entry's own `checks`,
when the same sub-array declares one, never before it — in the same
array (§15.5) — a positional fact about that array's own contents,
not a `skeleton:`-keyed refusal, the same rule regardless of which
type declares the pairing.

**One registry, one namespace, whatever `skeleton:` a declaration
picks or omits.** `container`- and `ticket`-skeleton types and
skeleton-less types share the identical declaration shape and the
identical registry `flow:` resolves against (§15.7); a `type:` name
may not collide with another, regardless of which skeleton, if any,
either one declares (§13). **Rootness is derived, not declared, and
there is no "at most one" check standing in for it**: requiring
exactly one loaded skeleton-less declaration would be a bundle-wide
fact a value had to police — "is this the one" — that the
declaration graph already answers structurally. A root is simply a
node nothing else's `flow:` targets (§15.6), derived the identical
way a queue is a query instead of a stored bucket and ordering is
the array index instead of a second field. Nothing stops a bundle
from declaring a second skeleton-less type for some other
outermost-shaped thing, and nothing needs to — a bundle with two
roots is well-formed. **Which root the plane actually dispatches a
fresh project from is a separate fact, named explicitly by `entry:`
in `bundle.yaml` (§2), not derived from rootness at all**: "a project
by convention" names nothing the loader can check — rootness answers
"is this a root," never "which root do I start from," and those are
different questions with a bundle that has more than one root.

**"Ticket", "container" and "milestone" are what a declaration
contains, not what the grammar calls it.** Nothing in the loader
branches on any of the three words. Naming the platform-fixed
skeleton is `skeleton:`'s job alone, which leaves "ticket",
"container" and "milestone" as descriptions a reader reaches for
because a `ticket`-skeleton type usually holds one generation and a
`container`-skeleton type usually holds queues — never a kind the
grammar itself checks, and never a registry key.

### 15.3 Ordering: the array is the only mechanism

**There is no `after:` field — on a gate, an environment, or a
container anchor — and that is intended.** A gate naming its own
predecessor (`after: product-review`) would make a workflow bundle's
gates one chain that a type's `statuses:` filtered by name; a
container's five anchors have a fixed order and nothing for such a
field to say. The fixed-array shape reaches gates and environments
too, and the field exists nowhere, rather than standing beside a
mechanism that makes it redundant: `after: product-review` and "this
entry's position in the citing type's own `statuses:` array" say the
same thing, and a grammar that lets both say it is a grammar with two
ways to disagree with itself.

**This changes what "the same gate" can mean across types.** A
predecessor field requires one order for the whole bundle — "two
review statuses declaring the same `after:`" has to be a load error
*over the bundle*, because a gate's position has to hold regardless
of which type's `statuses:` cites it. With order living on the citing
type's own array instead, two types may cite `product-review` and
`engineering-review` in opposite relative order without either
declaration being wrong, because neither one's array answers to the
other's. `gates/<gate>.yaml` and `environments/<env>.yaml` (§15.4)
declare a gate or an environment once — role, throwback, escalation,
depth, or promotion and lifetime — and any number of types may cite
the same one by name; what those files never carry is a single global
position, only the fields that describe the review or the deployment
itself.

**Chain-axis position is a different mechanism.** §3's tier
declarations position tiers by edges and context walks, not by a
predecessor field; array position is workflow-axis vocabulary, and
the files this section and §15.4 describe are the only ones it
applies to.

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

**The same declaration may also be cited more than once by the one
type — the gate-and-environment analogue of §15.5's own `critique`
precedent, bounded by §15.12's namespacing once positions carry names
of their own.** `critique` is a system status rather than a named
declaration, so its own "citing it more than once… is the ordinary way
to give two generation phases different depths" reads directly; a gate
or an environment is a named, reusable declaration instead, and a
*type's own array* — as opposed to the loaded union — may name one
twice for the identical reason: two citations of the same gate are
two positions computing two different answers from the identical
declared `role:`, `escalation:` and (absent an override) derived
`throwback:`, each free to carry its own `depth:` — depth and scope
are independent facts about a citation's *position*, not about the
declaration. This is not a second declaration any more than
`critique`'s second citation is: the declared gate file still exists
exactly once, and citing it twice never means an author must write
`role:`/`escalation:` twice.

**The two citations still need to be told apart, though, and §15.12's
namespacing is what does it — one level, derived from whichever
sub-array a citation sits in, never from which side of a `reconcile`
it happens to fall on.** Two citations landing in two different
namespaces (one inside a sub-array, one at the top level; or one in
each of two different sub-arrays) resolve to two distinct
namespace-qualified positions and need nothing further. Two citations
landing in the *same* namespace do not, and this is a load error
(§15.12's own uniqueness-within-a-namespace check) rather than a
tie-break the loader invents. The case that draws the line: one gate,
`architecture-review`, cited twice inside the identical sub-array —
once before its `reconcile`, once after — is refused, and the second
citation is a gate of its own, `architecture-synthesis-review`
(§15.2's `feature.yaml`): the two review different things (a tier's
own artifact, versus what a `reconcile` has since joined), and a
citation told apart from its sibling only by which side of a
`reconcile` it sits on is exactly the second level of qualification
§15.12 refuses. No worked example in this record cites one gate twice
within a single type; the general capability stated above holds
wherever the two citations land in distinguishable namespaces.

Approval is the transition itself (v5 §7.16) — there is no approval
object, and no `approvers:` list. Who approved is answerable from the
log because the plane records the command with its actor.

**No `ticket_types:` field, and none is missing.** The fact a gate's
`ticket_types: [feature]` would carry is which types' own `statuses:`
arrays cite it, and there is exactly one place it lives — the citing
type, not the gate.

**`throwback:` is a single optional target.**

```yaml
# gates/ux-review.yaml
review: ux-review
role: design
depth: 1
escalation: author
throwback: pending               # optional: an explicit landing point,
                                  #   overriding §15.10's derived default
```

A declared *list* of legal decline exits bounds something only while
decline targets are a per-gate allow-list;
`docs/v5-design-decisions.md` §7.19 and §15.10 below make a gate's
decline and a Blocked-return the same rule regardless of declaration —
any earlier status in the citing type's own effective sequence — so a
list has nothing to bound, and a bare list also stops meaning anything
once it no longer bounds: naming several targets says "any of these
is legal," and a landing point cannot be several things at once.

The field is narrower and singular. §15.10's sub-array grouping
gives most gates a *default* landing point — its citing sub-array's own
earliest entry, its own leading `pending` for a generation-shaped
group (§13) — for the ordinary case a decline names no further choice.
A gate sitting first in its own sub-array, or in no sub-array at all,
has no earlier entry there to fall back to, so this derivation gives it
no default. `throwback:` is the escape hatch beside that default, one
explicit status, for the gate that wants a different one-click landing
point than the derivation would pick, or that has no derived default to
begin with. It names no legality of its own: whatever it names must
already be earlier in the citing type's own effective sequence, the
identical bound §15.10 states for every decline, declared or not.

**Depth 0 is the rule for a gate, not merely its default** (v5 §7.19).
A gate is a human sign-off, and a human reads the top level; setting
a gate's depth by reasoning about how far the chain fans out is
arguing the auto-reviewer's case inside the human reviewer's own
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

**`critique` and `reconcile` (§15.11) are the two review-shaped kinds
(§15.1) — this section states `critique`'s own pairing rule;
`reconcile`'s is stated at §15.11, since it pairs with a `merge`
entry's own position rather than with one generation-shaped peer, may
recur the way `merge` itself can, and is required — never opt-in —
wherever a `merge` entry appears.**

**The one carve-out, and the reason is worth stating rather than
asserting.** A gate is depth 0 on a container the identical way it is
on a ticket — a human reads the top level, whatever the top level
contains — and an environment is the same: neither needs a generation
to mean something, which is why both are legal on every type
regardless of skeleton (§15.2). Critique is different in kind: its
depth *selects which tiers' review runs*, which needs a generation to
select within. **The rule is that a `critique` entry must sit
immediately after a generation-shaped entry — or immediately after
that entry's own `checks`, when the same sub-array declares one, and
never before it** (`generation`, `design`, `architecture` or
`implementation`, §15.1 — every rule in this section reads "a
generation entry" as any one of these). `checks` runs first when both
are present: machine validation is meant to happen before either an
agent's `critique` or a human gate spends a read on a draft CI has
not yet validated. No skeleton named, because none needs to be:
whether a given array has a generation-shaped entry for a `critique`
to pair with is a fact about that array's own contents, not about
which skeleton, if any, the citing type declares — naming excluded
skeletons would say the identical thing twice, and any type's array
may hold a bare generation-shaped entry (§15.2). The rule is about
what sits where, never about skeletons.

```yaml
  - status: generation
  - status: checks                 # optional; when present, critique
  - status: critique               #   must follow it, never precede it
    depth: 1                       #   — otherwise, critique follows
                                    #   the generation entry directly
```

A sub-array declaring both reads `generation-shaped entry → checks →
critique`; one declaring no `checks` of its own still pairs `critique`
directly with the generation-shaped entry, unchanged.

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
critique slot."** A singular `critique.yaml` file would make
critique's participation bundle-wide, with nowhere per-type to put
it; with every type having its own array, per-type participation is
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
contain, never which `skeleton:`, if any, either one declares
(§15.2). What varies per declared container is its **name** and what
each of its anchor entries' `flow:` points at — never the anchor
names, their count, or their order (§15.1).

**What is barred, and barred at load rather than left to a live chain
to discover, is a type reaching itself through its own declarations.**
The declaration graph — **nodes are every type with a population
anchor of its own, edges are `flow:` references between them** — must
be acyclic, and a type naming itself is the degenerate one-node case
of the same rule (§13). `milestone` cannot open `milestone`. A `flow:`
edge whose target has no population anchor of its own takes no part in
this graph and is always a leaf — a type is a leaf because its own
array declares no population anchor, never because of its skeleton: a
`ticket`-skeleton type is not structurally barred from having one
(§15.2).

**The node set is read from each type's own declared entries, never
from its `skeleton:`.** Restricting nodes to `container`-skeleton
types excludes every edge *into* a skeleton-less type by
construction, because such a type is never a node the graph can
contain — which is exactly the edge a cycle through the project runs
on: `milestone`'s `main` entry naming `flow: project` and `project`'s
`build-out` entry naming `flow: milestone` is a genuine two-node
cycle, and the narrower definition lets it load, catching it only if
some live chain of instances happens to close the loop. Widening the
*skeleton* condition to skeleton-less types as well as
`container`-skeleton ones is still asking the wrong question — the
property a node needs is "has a population anchor," which a
`container`-skeleton or skeleton-less type usually has and a
`ticket`-skeleton type usually lacks, while `skeleton:` itself is
silent on the question once any type's array may hold a population
anchor regardless of which backbone it declares. The definition is
the direct one because the two facts can come apart.

**This is a load-time check over declarations, not a runtime check
over instances.** The tempting version is "no container may be its
own ancestor," checked as instances mint; it is the wrong tool,
because it leaves unbounded depth *declarable*, caught only when some
live chain of instances happens to close the loop — trading a
load-time failure for a mid-flight one, the identical trade this
project has already made the other way (v5 §2.4: failing at config
load beats failing mid-flight). The declaration-graph check is also
what bars same-name nesting and bounds depth without counting it: an
acyclic graph has a finite longest path, so a bundle's maximum
nesting depth is knowable from the bundle alone, even though the
number of distinct named levels an author declares is unbounded. No
further instance-level check is needed — it falls out of the
declaration graph's acyclicity for free.

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
`Q`, never a state `Q` itself is ever *in* (§15.7: the container is
never "at `Q`, blocked," since `Q` cannot become current while its
guard holds) — derivable from the declared queue graph plus live
ticket state, the identical reasoning that keeps a queue itself from
being stored. Introducing a stored or fixed `blocked` status here
would be exactly the pending-work-on-the-node antipattern v5 §7.11's
staleness projection already refuses.

### 15.7 Queues, dispatch, and blocking

A **population anchor** is any `status:` entry named `prep`, `main` or
`cleanup`, or any `status:` entry at all in a skeleton-less type's
array (§13). It carries `flow:`, required, naming a member of the
type registry (§15.2). This is a fact about the entry's own name and
the array it sits in, never about which `skeleton:`, if any, that
array's own type declares as a whole (§15.2): `generation`, `design`,
`architecture`, `critique`, `reconcile`, `pending`, `checks`, `merge`,
`deploy`, `setup`, `retro` and `terminal` are never population anchors
and never carry `flow:`, whichever type's array they sit in.

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

**There is no `singleton:` field, and nothing is missing.** A field
bounding a *queue* to at most one work item ever assigned is what
`milestone`'s `setup` and `retro` anchors would need if each were a
`flow:` naming a separately minted, ticket-skeleton child
(`types/setup.yaml`, `types/retro.yaml`): a queue is otherwise
open-ended, so declaring it closed after one assignment would be the
only way to say "this container has exactly one setup, ever" without
a second mechanism. §15.2's unification removes the reason: `setup`
and `retro` name no queue at all, each sitting inline as an ordinary
agent-balled entry (`generation`'s own kind of anchor, not a
population one, §15.1) directly in the container's own array. An
inline entry runs once per pass through it, exactly like `main` runs
once per container instance and `generation` runs once per ticket
pass — the "at most one, ever" property falls out of the container
having exactly one instance and the entry sitting at one array
position, with nothing left to bound. There is no gap this leaves
open: such a field would exist only because a queue could otherwise
admit more than one child, and an inline entry is never a queue to
begin with.

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
`setup` and `retro`, by contrast, carry no `flow:` at all (§15.2) —
each is an ordinary agent-balled entry, "a work item, with its own
bundles, dispatched by machinery that already exists"
(`docs/v5-design-decisions.md` §7.8), the identical mechanism a
`generation` entry already uses: the chain bundle backing `milestone`
itself carries the tiers with the `delivery:` blocks that give `setup`
and `retro` their actual agent behavior, exactly as a ticket-skeleton
type's own chain gives its `generation` entries theirs. Neither is a
reserved agent-step slot the way a `boundary` step would be (§15.1),
and neither needs a nested type or a queue of its own to exist.

**`blocks:` is an entry guard, checked once at the transition it
guards — never a standing hold a projection recomputes.** An entry
`E` declaring `blocks: [Q]` gates entry *into* `Q` (a bare entry, or
a sub-array, named through the one entry a reference reaches inside
it, above): `Q` cannot be *entered* while `E` itself still carries
unresolved work; the check runs exactly once, at the moment something
attempts the transition into `Q`, and never again against the same
occupancy. **This is what rules out the eject.** Under a standing-hold
reading, a queue refilling while the guarded entry is already mid-run
pulls the container back out of it — indistinguishable from the guard
never having cleared. A reassignment to a new status must never
interrupt an already-dispatched flow instance, and `retro` is the
case that makes the distinction load-bearing rather than academic:
`retro`'s own output lands back in `main` (adjudicated findings, filed
debt), so a completion-hold form of `blocks:` has `retro` interrupting
itself the moment its own run produces the work `main`'s queue was
watching for. Checked once, at entry, `main` having emptied is a
precondition for *starting* `retro`, never a condition `retro` has to
keep satisfying while it runs. `main blocks: [retro]` is "the retro
can't finish while milestone work is open" stated as one declared
relation, and stated precisely: `retro` cannot be entered while
`main`'s own queue carries unresolved work. §13 rejects a `blocks:`
entry naming a queue in a different declaration, and rejects one
naming a queue nested inside what *this* queue's `flow:` opens.
Reaching into a nested container's own queues would make that
container's internals part of its interface to the level blocking it,
exactly backwards from composability: to block on something nested,
block on the `flow:` entry that opens it, not on what is inside it.

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
hinge on a step internal to it. "Dispatch mints one instance and
starts that instance at its own `setup` entry" and "minted one at a
time as the prior one closes" are both wrong for the same reason:
each makes existence and activation the same event, and they are not.

**Mint creates an instance; a parent's queue reaching it is what
activates it.** A `flow:` resolving to a type with a population anchor
of its own mints an instance as soon as something creates it —
business logic, or a person — and that instance accepts work into its
own future queues immediately. The parent's own queue position
determines only which minted instance is *current*; `setup`'s own
entry (§15.1, §15.7 — inline, dispatched by `milestone`'s own
chain-side tiers exactly as a `generation` entry would be) dispatches
once an instance becomes current, not once it is minted, which is
what makes "runs once, at activation" true without leaning on mint
timing. Minting and constituting are necessarily two different
declarations — the parent's queue entry lives in the parent's own
file, the newly minted instance's `setup` entry lives in the child's —
so there is no "before `setup`" position to invent.

**A container's position moves backward for one of two causes, never a
third.** The discriminator is the cause, not the author: "an authored
transition" reads as *who* moves the position rather than *why*, and
an authored-only rule rules out a `critique` entry's own automatic
decline (§15.5), which `v5-design-decisions.md` §7.19 requires be
structurally identical to a human decline at a gate — one mechanism,
not two.

1. **A step's own outcome moves position backward.** A decline does —
   whether a `critique` entry's own agent run issues it, landing back
   on the generation entry it pairs with (§15.5's fixed pairing, not a
   declared target), or a human issues it at a gate, landing per
   §15.4's `throwback:`. `v5-design-decisions.md` §7.19 requires these
   two be structurally one mechanism for regeneration feedback, not
   two; a critique decline having "no throwback semantics" (§7.19)
   means its reopen scope is trivial — nothing is downstream of it yet
   to reopen — not that it fails to move position at all. Automatic
   backward movement on a critique decline is required, not merely
   tolerated.
2. **An explicit author transition moves position backward.** The
   return from `retro` to `main`, below, is this: nothing declined
   there, an author judged the sub-array complete and moved the
   container themselves.
3. **A queue's population changing never moves it.** What this
   excludes is not automation, and not backward movement in general,
   but position tracking a queue's contents underneath a position the
   container has already left. §15.7's queue remains a query — a
   resolved queue still un-resolves the moment its population refills
   — that fact just does not imply anything about where the
   container's position sits; position is not a function of queue
   population.

"A resolved queue un-resolving the moment its population refills,
with no separate 'container went backward' event to define" is the
same defect statement 3 excludes, restated in terms of position rather
than of a guard — the one that makes §15.7 check `blocks:` once at
entry. A queue refilling while the container has already moved past
it pulling the position back is indistinguishable from the guard
never having cleared, whether the thing said to move is the guard's
occupancy or the container's own position; excluding one and keeping
the other would reopen by a different name exactly what the entry
check closes.

**For a gate, a step's own outcome above means `throwback:`.** A gate
a container-skeleton or skeleton-less type's own array cites can throw
back to an earlier entry in that same array (§15.4's `throwback:`,
resolving within "the citing type's own array"
exactly as it does on a ticket), and a container's array can cite
gates (§15.2) — a milestone sign-off gate between `main` and `retro`
rejecting back to `main` is an ordinary throwback, not a mechanism
the container form lacks. **`setup`'s own position needs no
throwback-shaped argument**: `setup` is first in the minted instance's
own sequence because minting and constituting are necessarily two
different declarations (above), not because a container has no gates
to throw back with — it does.

**Returning from `retro` to `main` is the author's own transition, not
an automatic one.** Forward advance into a guard-cleared entry is
`ContainerLifecycle`'s to make, the moment the guard reads clear
(`docs/v5-design-decisions.md` §7.8); moving back to `main` once
`retro` has produced its findings and filed its debt is not a guard
clearing, so nothing computes it from queue state and no declared gate
performs it either — the only throwback the shipped `milestone` gives
`main` is `milestone-signoff`, and §15.10 places that gate *before*
`retro`, not after it. An author makes the return, once they judge
`retro`'s own sub-array — the agent step and the human gates around it
— to have run to completion, rather than the instant `retro`'s own
output lands in `main` and un-resolves it. This is also what lets
§15.7's unconditional `terminal` guard ever clear at all: absent this
manual return, `retro` filing work into `main` would leave
`cleanup`/`terminal` blocked on a queue with no declared path back to
reopen it.

### 15.9 The declarable-protocol narrowing, continued

Work-item types, together with gates, environments and critique's own
participation, are workflow-bundle content (`docs/non-goals.md`'s "No
per-project restructuring of the automation protocol" entry): the
automation graph and the anchor statuses underneath it — the ticket
and container skeletons alike (§15.1) — stay platform-fixed, so the
admission rule that entry already states ("a state may be declared
iff no plane logic branches on it") covers this section's single
declaration shape without needing to change: nothing here grows what
is declarable past that entry, only how it is spelled.

**Gates and environments on a skeleton-less type's array, and an
optional rather than three-valued `skeleton:`, grow nothing either.**
Both are facts about *where* an already-declarable fact may be cited
or *how* it is spelled — a gate is workflow-bundle content whether or
not a project's array cites one. No plane logic branches on either,
so neither argues with the entry above the way the type registry
itself did.

**Nor does `entry:`.** `entry:` in `bundle.yaml` (§2) is a reference
to an already-declared type, the identical shape `catapult.yaml`'s own
`chain:`/`workflow:` pins already have — it names which already-
declarable root the plane starts from, adding no new declarable fact
about the automation graph itself.

**Nor does decoupling `skeleton:` from what an array may hold.**
Removing the coupling between a type's `skeleton:` and which of its
entries may be population anchors or agent-balled ones (§15.2, §13)
changes which combinations a bundle may write, not whether the plane
branches on any of them — dispatch still follows entirely from what
an entry *is* (a population anchor with its `flow:`, or one of the
fixed agent/world kinds with its own mechanism), never from which
skeleton the citing type happens to declare. The absence of
`singleton:` is smaller than a spelling change: such a field bounds a
queue's own cardinality, and once `setup` and `retro` are not queues
at all (§15.7), there is no cardinality left for a field to bound —
not a fact moved elsewhere, a fact that does not exist.

**Nor does a status entry's `name:` field (§15.12).** A status entry's
authored name is read by nothing plane-side — every predicate and
every branch this document names still reads the entry's `status:`
(kind), never its `name:` — so it is not a state in the admission
rule's sense at all, only a label a human or a screen reads. Namespacing
positions by their sub-array anchor and refusing an ambiguous bare
reference are both checks the loader runs over a bundle's own array,
the identical "no plane logic branches on it" territory §15.10's own
sub-array grouping already occupies (above) — nothing here reaches
further than a fact about which string names which entry.

### 15.10 Sub-arrays — grouping a gate around its own agent step

**A `statuses:` array entry may itself be an array — a bare, unnamed
sub-array grouping a contiguous run of the entries §15.2 already
allows anywhere in the array.** Grouping is admissible under
`docs/non-goals.md`'s "No per-project restructuring of the automation
protocol" for that entry's own stated rule — no plane logic branches
on whether entries are grouped, any more than it branches on where in
the array one sits (§15.9). Nothing new is declarable inside one: an
entry inside a sub-array is still exactly one of `status:`, `review:`
or `environment:` (§13), and a sub-array carries no key of its own —
no `name:`, no `id:`. **A sub-array stays anonymous, and is referenced
through an entry it contains, never by a name of its own**: a
sub-array is a grouping of entries that already have names, so a
second name naming the group would be a second way to say what the
first entry inside it already says (`docs/non-goals.md` carries no
entry for this because the reason is local to this section, not a
refusal worth a cross-system entry). §13's `blocks:` reference is
exactly this: `blocks: [retro]` names `retro`, and if `retro` sits
inside a sub-array the reference reaches the whole group through it —
resolved by containment, not by a handle the sub-array itself carries.
The addition is structural only: a way to say *these entries resolve
together* instead of merely sitting at adjacent array indices.

```yaml
statuses:
  - - status: pending          # the group's own leading entry —
                                #   required here, not merely legal,
                                #   once `generation` sits in a
                                #   sub-array (§13's tightened check)
    - status: generation
    - status: critique
      depth: 1
    - review: ux-review
    - review: engineering-review
  - status: checks
  - status: reconcile           # required wherever merge is, this
                                 #   sub-array's own contents aside
                                 #   (§15.1, §15.11)
  - status: merge
  - environment: staging
  - status: deploy
  - status: terminal
```

**Legal wherever a `review:` or `environment:` entry is already legal
— every type's array, whatever `skeleton:` it declares or omits
(§15.2).** No load-time check refuses a population anchor (one
carrying `flow:` or `blocks:`) inside a sub-array (§13), and none is
needed: a population anchor is not one of the entries this section
groups. What a `container`-skeleton type has worth grouping is its
own agent-balled entries — `setup` and `retro` are ordinary
agent-balled entries, legal directly in a `container`-skeleton type's
array (§15.2), and the fold below groups `retro` with the gates around
it the identical way `feature.yaml`'s own sub-array groups
`generation` with its gates. A `container`-skeleton or skeleton-less
type whose array holds nothing but its required backbone plus gates
and environments has nothing worth grouping — but that is a fact
about what a given bundle chose to declare, not a ceiling this grammar
imposes.

**Exactly one non-review-shaped agent-balled entry per sub-array — a
load-time check, and the fact the whole derivation below rests on.**
§15.1's `ball` column marks `generation`, `design`, `architecture`,
`implementation`, `critique`, `reconcile`, `retro` and `setup` as
agent-balled (`merge`'s own `ball` is `plane`, §15.11); `critique` and
`reconcile` are excluded here because each reviews an entry rather
than standing as one — review-shaped, §15.1 — the identical exclusion
§15.5 draws for `critique` alone, generalized rather than duplicated.
A sub-array holding zero such entries has nothing for a throwback to
fall back to and nothing worth grouping (a load error); one holding
two or more — two generation-shaped entries grouped together, say —
has no unambiguous anchor between them, and rather than inventing a
tie-break rule for a shape the default bundle never needs, it is
refused at load, the same posture `container` and `ticket`-skeleton
mismatches already get (§13). Revisit condition: a real bundle need
for a multi-agent-step group, at which point the tie-break is decided
against that actual shape rather than guessed at now.

**Default throwback falls back to the sub-array's own earliest entry,
never to the array position immediately before the gate.** This is the
reading that survives the milestone shape `[milestone-signoff,
pending, retro, proposals-read]` (the real
`bundles/default-flow/types/milestone.yaml`, not §15.2's own
simplified `ux-review` illustration) — a `review:` entry's position in
the flat array is not a reliable proxy for "what it reopens" the
moment a gate sits *after* the group's own agent step rather than
before it. `proposals-read` declining falls back to `retro`'s own
leading `pending` — the group's earliest entry that is a legal target
at all, read the identical way the next paragraph states for a
generation-shaped sub-array, because `retro`'s own group leads with a
`pending` too (§15.2), even though `retro` isn't one of §13's
generation-shaped kinds and nothing requires it to — not to
`milestone-signoff` (the array position immediately before `retro`) —
the latter would re-ask the author a question they already answered
instead of re-running the agent that produced the thing they're
declining.

**For a generation-shaped sub-array, "earliest entry" is the group's
own leading `pending`, not the generation-shaped entry itself.** §13's
pending-precedes check makes every generation-shaped sub-array's first
member its own `pending`, so the derivation this paragraph states —
"the sub-array's own earliest entry" — already reaches it without a
second rule: `architecture-review` declining falls back to
`architecture`'s own leading `pending`, queueing the repair the same
way any first dispatch queues, not straight to `architecture` itself.
This is what v5 §7.6's own repair-loop mapping shows — `Ready for
rework`(pending) / `Reworking`(generation) — and why a throwback never
lands directly on the generation-shaped entry: that would skip the
wait for dispatch capacity every other entry into that status goes
through.

A gate declaring no `throwback:` of its own resolves to this
derivation; §15.4's `throwback:` field is unaffected in shape and
stays legal wherever it already was. A gate sitting *outside* every
sub-array — `reconcile` itself is never grouped (§15.11), and a
`review:` entry positioned after it inherits that — has no sub-array
to derive an earliest entry from at all, and must declare `throwback:`
explicitly (§15.10's own "not decided here, left open" list, below).

**A gate sitting *inside* a sub-array but *before* that group's own
earliest entry derives nothing either** — the mirror case of the one
above, reached from the opposite direction, and the general statement
§15.4 makes: the moment the gate itself sits before its citing
sub-array's earliest entry, the derivation would name a target *later*
than the gate, which the legality rule already refuses.
`milestone-signoff` is the shipped-bundle instance, worked in full
below where its own `throwback: main` is read against this rule.

**The worked example is the grammar, not a shape argued from prose
ahead of it.** `retro` carries no `flow:` — it folds inline into
`milestone`'s own array (§15.2, §15.7), and `types/setup.yaml`/
`types/retro.yaml` do not exist as dispatch targets — so nothing bars
it from sitting inside this group. One consequence worth naming
plainly: this sub-array is the one shape the default bundle forms that
distinguishes the derivation from a naive first-element reading. Every
generation-shaped sub-array has its own `pending` first (§13), so a
naive first-array-element reading already lands on the right answer
there and never exercises the distinction this section draws;
`[milestone-signoff, pending, retro, proposals-read]` does, because
its own leading entry is a `review:` — `milestone-signoff` — rather
than a legal throwback target at all, which only the derivation this
section states gets right. Naming it rather than `feature.yaml`'s own
groups is deliberate, not an oversight.

**A decline's legal targets are "earlier in this ticket's effective
sequence", never a per-gate declared list.** This is §7.19's rule for
Blocked-return, and the two entry points share it: a throwback from a
review and an unblock to an earlier status differ only in their
*default*, not in what is reachable.

A declared list bounds nothing, and that is a fact about the tree.
`lib/catapult/engine/commands/decline_gate.ex`'s own moduledoc states
that `gate`/`throwback_to` membership "is the command edge's to
check... not the aggregate's", and that command edge is unbuilt
(`systems/delivery.md`'s Phase 7): there is no shipped enforcement of
a declared allow-list. Nor is the bound invented for the occasion:
`Catapult.Dsl.Workflow.gate_throwback_problems/2` already computes
exactly it — `target in (type.statuses |> Enum.take(index))` — for a
declared value at load time. One predicate, in one place, instead of a
load-time check and a runtime allow-list that happened to agree.

**`throwback:` is a single-target override on the default landing
point.** Bounding legality is not its job; naming *where a decline
lands* is, and that is what an escape hatch is for. The derivation
above supplies the default — the citing sub-array's own earliest
entry, which for a generation-shaped group is its own leading
`pending` (§13) — and `throwback:` is what a gate declares instead of
it.

A list stops meaning anything the moment it stops bounding: naming
several targets said "any of these is a legal exit", a claim about
legality. A landing point is not a set, since a decline lands on
exactly one status, so the field is a single optional target rather
than a list. `docs/v5-design-decisions.md` §4.5's escape-hatch
discipline — "an escape hatch that accretes special cases becomes N
more mechanisms" — is why it stops at one override: a single explicit
status, no per-use kinds, no second derivation rule beside the
sub-array default.

**The test for a declaration, stated for a default rather than a
bound: if the default bundle needs the field to reach a landing point
the derivation cannot supply — a *different* one than it would pick, or
one it names no legal target for at all — that is the field doing its
job; if it needs the field only to restate a target already reachable,
that declaration is redundant and worth dropping.** Under the
earlier-prefix legality rule, the retro case that motivates this whole
section resolves with no declaration at all — the derivation is right
about the ordinary case. Five default-bundle gates declare
`throwback:`. Two sit inside `feature.yaml`'s own sub-array and are
read against the sharper test, not waved through:

- `ux-review`'s own declared `throwback: pending` (`bundles/
  default-flow/gates/ux-review.yaml`) names the identical status the
  derivation picks: a generation-shaped sub-array carries its own
  leading `pending` (§13), and the derivation's own earliest-entry
  reading (above) already resolves to it. The declaration is
  redundant, not the field earning its keep.
- `engineering-review`'s own declared `throwback: ux-review`
  (`bundles/default-flow/gates/engineering-review.yaml`) sits entirely
  inside the group the derivation covers, and is a genuine,
  non-default landing point rather than a restatement: the derived
  default is the group's own leading `pending` (§13), and `ux-review`
  is a different status, legal because it sits earlier in the sequence
  than the gate declining it. `generation` remains a legal target too,
  declared or not — the earlier-prefix rule reaches it regardless.

The other three sit in `milestone.yaml`, across its two sub-arrays, so
the sharper test applies to each: whether its own declared
`throwback:` matches that group's derived default, names a legal
target the derivation would not have picked, or sits where the
derivation names no legal target at all. Two are inside
`[milestone-signoff, pending, retro, proposals-read]` (§15.10 above),
whose derived default is `retro`'s own leading `pending`:

- `milestone-signoff`'s own declared `throwback: main` (`bundles/
  default-flow/gates/milestone-signoff.yaml`) names `main`, a target
  *outside* the sub-array, before the group entirely. The derivation
  names no landing point here at all: `milestone-signoff` sits first
  in its own sub-array, so the sub-array's own earliest entry — the
  derivation's fallback — is `milestone-signoff` itself, and nothing
  in the group is earlier in the effective sequence than the gate that
  would decline it. This declaration is mandatory, not an override of
  a derived default — the identical gap the "gate sitting outside
  every sub-array... must declare `throwback:` explicitly" rule above
  closes for a gate with no group at all, reached here by a gate that
  has one but finds no legal target inside it. Rejecting the sign-off
  means reopening the milestone's own `main` work period, not
  re-running `retro`.
- `proposals-read`'s own declared `throwback: retro` (`bundles/
  default-flow/gates/proposals-read.yaml`) names `retro` itself,
  skipping the dispatch-wait its own leading `pending` interposes. The
  derived default is `retro`'s own leading `pending` (§15.2), so
  naming `retro` explicitly is a genuine, non-default landing point
  this file needs to keep declaring — the identical shape as
  `engineering-review`'s, and for the identical reason.

The third sits in `milestone.yaml`'s other sub-array, `[pending,
setup, kickoff-review]` (§15.2). Neither of this type's two groups is
generation-shaped — neither `setup` nor `retro` is (§13) — so §13's
pending-precedes rule requires a leading `pending` in neither, and
both carry one anyway, as an authored choice (§15.2). The
earliest-entry derivation reads that `pending` first here exactly as
it does in `retro`'s group:

- `kickoff-review`'s own declared `throwback: setup` (`bundles/
  default-flow/gates/kickoff-review.yaml`) names `setup`, not the
  group's own leading `pending` the derivation would pick — a
  *different* landing point, and a legal one, `setup` sitting earlier
  in the sequence than the gate declining it. The identical shape as
  `engineering-review`'s and `proposals-read`'s: a genuine,
  non-default landing point. Declaring it is not redundant.

All five files declare a single status rather than a list.
`ux-review`'s is the one declaration the derivation makes redundant,
and dropping it loses no landing point a decliner can still reach.

**Throwback reopens the whole sub-array — the all-reopen rule
(`docs/v5-design-decisions.md` §7.19) is definitional, not prose.**
Falling back to the group's own earliest entry *is* "reopen everything
downstream of the regeneration," restated structurally: there is no
entry between the fallback point and any gate later in the same
sub-array that the reopen could leave standing, because the fallback
point is, by construction, the earliest entry the group has — its own
leading `pending` for a generation-shaped group (§13), its own
non-review-shaped agent-balled entry directly otherwise. This is what
closes v5 §7.19's own observation that the all-reopen rule was written
as a description nothing enforced — a passed gate re-checked against a
sub-array whose own agent step regenerated is exactly §7.11's
staleness-is-derived machinery running over a structural boundary
instead of an implied one.

**This also answers `docs/v5-design-decisions.md` §7.16's open item,
"what a passed gate pins."** A gate's citing sub-array has exactly one
non-review-shaped agent step (the check above), so what the gate
approves is that step's own committed content, read at the gate's own
declared `depth:` — the identical node set `critique`'s own depth
already selects among when a critique entry sits in the same group
(§15.5), generalized from "review this generation" to "this gate
approves this generation." Staleness for the gate becomes the same
derived join a review tier's 1:1 pin already uses (§7.16, ORC-84/
ORC-6): the gate is stale exactly when the pinned node's own committed
content has moved past what the gate's approval event recorded,
answerable from the log rather than a stored field. The join itself is
`systems/delivery.md`'s Phase 7 work, declared workflow gates being
that phase's to build; this section gives it a structural node to pin
against.

**Backward movement is one rule with one target test, not two.**
`docs/v5-design-decisions.md` §7.19's "a throwback from a review and an
unblock to an earlier status are the same movement" is about reopen
scope, and that reading is correct — "both reopen everything
downstream" is the entire content of "the same movement." The two
entry points also share what counts as a legal target, for the reason
given above: `DeclineGate` enforces no declared list, and the command
edge that would is unbuilt. A gate's decline and a Blocked-return both
resolve against the identical "earlier in the effective sequence"
test; they differ only in their *default* — a throwback's one-click
default is the citing sub-array's own earliest entry (this section), a
Blocked-return's is the tracked origin status (§7.19) — and in nothing
else, except that a gate's default may itself be overridden by an
explicitly declared `throwback:` (§15.4, above); Blocked-return has no
analogous override, since nothing groups it the way a sub-array groups
a gate. `docs/ui-spec.md`'s J2, J4 and its `ticket`-screen gate-action
bullet state the same rule.

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
  it.** Settled: a `review:` entry sitting outside every sub-array has
  no derived default at all and must declare its own `throwback:`
  (§15.4). The derivation above only ever has a sub-array's own
  contents to compute a default *from*; a gate outside one has no
  group to derive against, so there is nothing to compute a default
  out of — this is a closure, not a placeholder. The general "earlier
  in the effective sequence" legality test still covers what such a
  gate *may* target, regardless of whether it declares a default; what
  this bullet closes is only whether the grammar picks one for it when
  it doesn't.
- **Whether a sub-array is a visible grouping or flattens for
  display.** Settled, not left open: visible grouping. `board`'s lanes
  render a bounded box around each sub-array's own lanes, badged with
  whatever this section's own `throwback_default/3` resolves for the
  group; `ticket`'s sequence rail groups the identical way. This
  section fixes the grammar and the derivation; the rendering decision
  and its reasoning live in `screens/board.md`, not here.
- **Whether the `pending`-precedes-`generation`/`deploy` check (§13)
  needs a sub-array of its own head.** Settled: it does. §13's rule
  requires a generation-shaped entry's own `pending` as the first
  member of its sub-array, when it sits in one — sub-array membership
  is not incidental to this check the way it is for `deploy`'s own,
  looser "somewhere earlier" reading. Everything else this section
  computes is unaffected: grouping governs throwback derivation and
  reopen scope and nothing about which entries are legal where (§15.1's
  table loses no entry to this section, only a second job — see
  below); it is specifically the pending-precedes check, not the fixed
  skeleton's shape in general, that sub-array membership reaches into.

**§15.1's fixed vocabulary loses a job here, not an entry.** The
vocabulary's re-resolution role (§15.1's own opening paragraph, and
§7.19's cutover-survival rule) is untouched — every anchor this
section discusses exists, fixed, undeclarable — while it has no
*legality-bounding* role: what a decline may target is "earlier in the
citing type's own effective sequence," full stop, never a bound stated
in terms of a per-gate declared list, so a declared list is optional
rather than load-bearing. `throwback:` itself survives (§15.4, above),
a single override on the *default landing point* a decline picks — a
different job from bounding legality, and untouched by this paragraph.

**`milestone`'s `setup` and `retro` fold into `milestone`'s own array**
— `retro` inside the sub-array above, `setup` needing no sub-array of
its own (§15.2) — rather than running as separately dispatched
ticket-skeleton types, and `types/setup.yaml`/`types/retro.yaml` do
not exist as dispatch targets (`docs/v5-design-decisions.md` §7.8
records the same). A container instance is a legal agent dispatch
target, on the identical footing as a ticket instance
(`docs/v5-design-decisions.md` §7.8, `systems/delivery.md`).

### 15.11 `reconcile` — the join before `merge`, and gate scope derived from position

**§15.1's `ball` column carries two kinds for two jobs — judging a
produced PR against its own argument, and mechanically joining it into
the parent branch — that a single `merge` kind would otherwise do
both of.** `docs/v5-design-decisions.md` §7.5 describes the first job
as reading, not merging — "Child reconcile reads the child PR against
the child's argument, merges to the feature branch" — and
`Catapult.Dsl.SystemStatus.agent_steps/0` carries `:reconcile` as one
of the five fixed agent steps. With `merge` standing in for both, the
only way to keep it out of
`Catapult.Delivery.ContainerLifecycle.inline_dispatch_point?/1`'s
target set is a check **by name** — `not queue_shaped? and
non_critique_agent_step? and status != "merge"` — inside a module
whose own moduledoc states it branches on no status name at all. So
the kind is split (§15.1, above): `reconcile` is the review-shaped
kind that does the judging, agent-balled; `merge`'s own `ball` is
`plane`, since a mechanical join effected by the plane the moment
`reconcile` approves needs no agent dispatch to do it — and the
exclusion becomes what it always meant: `merge` is absent from the
inline dispatch point's target set because it is not agent-balled, not
because its name is checked. `SystemStatus.agent_balled?/1` answers
false for `"merge"`, and `inline_dispatch_point?/1` carries no
`status != "merge"` clause — the predicate is "agent-balled and not
review-shaped," with nothing left for a name check to do.

**Required wherever `merge` appears, stated positionally rather than
per skeleton.** A `merge` entry must be preceded, earlier in the same
array, by a `reconcile` entry — a fact about that array's own
contents, exactly the shape §15.5's own `critique` rule takes rather
than a skeleton-keyed version of it. This is *stronger* than "every
ticket-skeleton array holds one": it reaches `container`-skeleton
arrays too, and closes the gap that framing leaves open — a container
type running its own bare `checks → merge → deploy` would merge with
nothing read first. `milestone.yaml`'s own worked example does not
exercise it: neither `setup` nor `retro` produces code, so neither
merges, and §15.2's declaration holds no `merge` at all — the
requirement above is satisfied vacuously there, not dropped. A
workflow bundle can decline `critique` by writing no entry for it; it
cannot decline `reconcile` the same way wherever `merge` appears,
because nothing merges, of any skeleton, without having been read
against its own argument first (v5 §7.5) — `feature.yaml` (§15.2) is
this record's own live example of a `merge` and the `reconcile` it
requires.

**Where `reconcile` sits, not a sub-array.** §15.10's sub-array groups
a gate around its own generation-shaped agent step — `types/feature
.yaml`'s own `design` group (§15.2) is one draft and everything that
reviews that one draft, closely enough to share a throwback target.
`reconcile` reviews something else: the checked, CI-passed state of a
PR that may already carry more than one generation's worth of change
and, at a level with children, the composed diff those children
already merged up into it. It sits in the flat backbone, after
`checks`, positioned like `merge` and `deploy` always have been — not
inside the generation's own sub-array, and ordinary bundle content is
not expected to put it there. Nothing in this grammar forbids it
(§13's sub-array bullet counts `reconcile` among the review-shaped
entries a sub-array may hold any number of, the same way it permits an
unbounded run of `critique`), but the shape this section actually
describes is `reconcile` as its own array entry — tree-shape-scoped
rather than depth-scoped, unlike `critique` and a gate, which use a
declared ceiling (below) — and, like a generation-shaped entry, free
to recur.

**A gate's scope derives from its position relative to the nearest
`reconcile` entry before it, not a single global before/after split —
`reconcile` recurring means a gate can sit between two of them.** A
`review:` entry earlier than every `reconcile` in the citing type's
own effective sequence approves what that tier alone produced. One
sitting after a `reconcile` approves what that particular `reconcile`
has already read and accepted — every child artifact joined into it up
to that point — which a later `reconcile` in the same array supersedes
again: the worked example below has `architecture-synthesis-review`
scoped to the architecture-phase join alone, never superseded by
implementation's own later `reconcile` because nothing after it cites
that gate again. This answers `docs/v5-design-decisions.md` §7.16's
own open item, "what a passed gate pins," for a gate positioned
relative to a join, the way §15.10 answers it for a gate inside a
sub-array (the sub-array's one generation-shaped entry). The pinning
mechanism itself is `systems/delivery.md`'s Phase 7 work, declared
workflow gates being that phase's to build; this distinction is the
structural fact it keys on, rather than a depth number alone. **What
"approves what has already been joined" means follows from every
child a `reconcile` reads having also actually merged by the time it
runs (this section's own merge-cascade rule): a gate sitting after
`reconcile` reviews content already committed to the citing instance's
own branch, not a synthesis existing only inside the reconcile agent's
own read.**

**No new field, and no `docs/non-goals.md` entry — gate scope is
derived from array position the identical way throwback's own default
already is (§15.10).** A field naming a gate's scope explicitly
(`scope: own | joined`) would only restate a fact already computable
from where the entry sits, and a restated fact can disagree with the
position that actually governs it — the reason `throwback:` is a
single override rather than a declared bound. `docs/non-goals.md`'s
"No per-project restructuring of the automation protocol" entry
already covers this without amendment, the identical reasoning §15.1
above gives for `reconcile` joining the fixed table without an entry
of its own: nothing here is newly declarable, only newly derivable
from vocabulary that already was.

**Two `reconcile` entries per type, not one — each closing a different
phase, ordered relative to that phase rather than pinned once between
`checks` and `merge`.** True of both declarations this record carries:
`types/feature.yaml` (§15.2) and this section's own worked example
below. Architecture's own fan-out produces a doc at every connected
chain tier (sysarch, comparch, subcomparch); those need joining
bottom-up before `architecture-synthesis-review` reads a single
composed document, which is the first `reconcile`. Implementation is
a separate phase closing separately: no instance merges until both its
own docs and its own code are complete, so a second `reconcile` closes
the implementation phase the identical way. `merge` itself does not
recur (§13): it runs once, at the root, after both phases are done
(below).

**Dispatched once per tree level, through the same ticket the level's
own doc-graph node already has — not this whole array run
`depth:`-filtered inside one ticket.** Running it inside *one* ticket
— the feature's — dispatching comparch and subcomparch generation as
scope-runs under a single `architecture, depth: 2` visit cannot give
`critique` its own per-level throwback: a ticket has one status at a
time (v5 §7.19), so one ticket sitting in one `critique` visit means a
failing subcomparch review throws the whole feature back and
regenerates everything architecture fanned out, comparch included — no
`depth:` value narrows the bounce, because depth was never able to say
"only this branch." **Every tier from `sysarch` through `subcomparch`
dispatches through its own ticket instance instead**, spawned the
identical way a feature's own component and subcomponent children
already spawn — "when the plan node names them," recursively, one
level at a time, wherever the plan proves independent parallel work
exists (`docs/v5-design-decisions.md` §7.2, §7.10; §7.15's own
statement of when children spawn is the same mechanism, not a second
one this section invents).

**Two type declarations, not one spanning the whole tree.** One
declared type instantiated "once per node the plan names," feature
included, at depth 0 of its own array, cannot be `types/feature.yaml`
itself (§15.2): `design` and `product-review` are feature-only — no
comparch or subcomparch wants its own product-facing sketch — and
neither `design` nor a bare `status:` entry carries a `depth:` field
to make it no-op below the root the way a gate or `critique` already
can (§13's own depth-bearing-site list). `feature` and this section's
own type are therefore two separate declarations, sharing no array:
`feature` (§15.2) has exactly one instance, ever, so its own two
architecture-phase gates — `architecture-review` and
`architecture-synthesis-review` — need no `depth:` at all (trivially
depth 0, the only level `feature` has); this section's own type —
instantiated at component and subcomponent tickets alike, since a
subcomponent is nothing more than a component instance with no
children of its own — is where `depth:` does real work, because it is
where more than one level actually exists. This is v5 §7.6's own
"Child" lifecycle: not `feature`'s array depth-filtered, a second
declaration in the shared status vocabulary, `type:component` and
`type:subcomponent` labels alike running it (the tracker-facing label
is not the same fact as which `types/<name>.yaml` an instance's
`statuses:` array comes from). It is also the exercised case behind
§13's `depth:`-never-validated-against-the-chain rule, two types
declaring different ceilings: a `component` gate's own ceiling reaches
one level deeper than `feature`'s ever needs to, because the two types
fan to different depths by declaration, not by anything the chain
itself claims.

Each instance of this section's own type computes its own **effective
sequence** the way a single fan-out level already does (v5 §7.19's own
worked example, `checks(2) → code review(1) → merge(2) → deploy(0)`),
filtered against *that instance's own position in the doc-graph tree*
rather than against a run dispatched at several depths from inside one
ticket. `gate 1`'s depth reaches a subcomponent's own effective
sequence the identical way it reaches a subcomponent-level scope run;
the run and the ticket sitting in that status are the same thing,
which is what lets a subcomparch review's decline land on the
subcomparch ticket's own `architecture` entry (§15.5) without touching
a sibling or a parent.

**`reconcile` carries no `depth:` of its own** (§13) — **whether a
given instance runs one is a fact about that instance's own children,
not a declared ceiling.** A leaf instance has nothing to join, and its
own effective sequence simply has no `reconcile` in it; an instance
with children runs exactly one, joining what those children have
merged up (below). A declared ceiling would only restate what the tree
already settles for every instance; `depth:` stays where it narrows
something the tree's own shape does not answer by itself — on
`critique` and on a gate, which review a level regardless of whether
that level has children at all.

Worked against a component instance at depth 0 of this type's own
array and a subcomponent instance at depth 1 — the type §15.2's own
`feature` spawns as children, sharing no array with it (above):

```yaml
# types/component.yaml — a subcomponent instance runs the identical
# declaration, one level deeper; the two are told apart by tree
# position alone, never by a second type (above)
type: component
skeleton: ticket
statuses:
  - - status: pending
    - status: architecture             # every instance: each
                                        #   component's comparch, each
                                        #   subcomponent's subcomparch
    - status: checks                   # no depth: field (never a
                                        #   depth-bearing site, §13) —
                                        #   every instance's own CI on
                                        #   its own produced draft.
                                        #   Before critique, not after
                                        #   (§15.5)
    - status: critique
      depth: 1                         # reaches every instance of
                                        #   this type — the deepest
                                        #   level it fans to
    - review: architecture-review
      depth: 1                         # before either reconcile in
                                        #   this instance's own
                                        #   sequence: scoped to this
                                        #   instance's own artifact

  - status: reconcile                # declared once for the type,
                                      #   like every entry here — a
                                      #   leaf subcomponent's own
                                      #   effective sequence selects
                                      #   nothing from it (nothing to
                                      #   join); a component's own
                                      #   selects its subcomponents'
                                      #   merge (below). Flat backbone,
                                      #   not the group above (§15.11's
                                      #   "not a sub-array" paragraph)
  - review: architecture-synthesis-review  # after reconcile: the
                                      #   joined set — a separate
                                      #   declared gate (§15.4), not
                                      #   the same one cited twice
                                      #   (ORC-155, §15.12).
                                      #   depth 0 (the default):
                                      #   reaches a component's own
                                      #   instance only — a
                                      #   subcomponent's own sequence
                                      #   has no reconcile ahead of
                                      #   this entry to have joined
                                      #   anything for it to review

  - - status: pending
    - status: implementation           # this instance's own code — no
                                        #   gate, the identical reason
                                        #   `feature`'s own
                                        #   implementation group has
                                        #   none (§15.1, §15.2)
    - status: checks                   # before critique (§15.5)
    - status: critique

  - status: reconcile                # the identical selection test
                                      #   as the first occurrence:
                                      #   nothing at a leaf, its
                                      #   subcomponents' merged
                                      #   implementation at a
                                      #   component — flat, the
                                      #   identical reason as above

  - status: merge                      # depth-0 by rule (below): a
                                        #   non-root instance's own
                                        #   copy never reaches this by
                                        #   its own dispatch — every
                                        #   component and subcomponent
                                        #   merges when *its own
                                        #   parent* enters reconcile
                                        #   instead
  - status: deploy
  - status: terminal
```

A subcomponent instance's own effective sequence runs `pending →
architecture → checks → critique → architecture-review → pending →
implementation → checks → critique → terminal`-shaped, minus what
depth and tree shape between them exclude: no `reconcile` at either
occurrence (a leaf, nothing to join), no `architecture-synthesis-review`
citation (depth 0 stops short of a depth-1 instance, the identical
ceiling mechanism excluding any entry too deep for it), and — below —
no `merge`. **What `deploy` means for an instance that is not the
tree's root is not settled by this array**, and is named rather than
assumed: `checks`, `implementation` and `deploy` carry no
depth-bearing field at all (§13), so nothing here states whether a
non-root instance's own effective sequence reaches `deploy` the way it
reaches its own two `checks` occurrences, or whether that is a
question this declaration cannot answer and a dispatcher must resolve
some other way. **`terminal` is not the same open question** — v5
§7.6's own Child lifecycle ends `Merged → Done`, so a non-root
instance's own `terminal` is reached and means exactly what it always
does, closing that instance's own ticket; what stays open is `deploy`
alone, and by extension whatever an `environment:` entry paired with
it would mean below the root. Left for the loader work
(`systems/delivery.md`'s Phase 7) against an actual bundle.

**`merge` is depth-0 by rule, not merely by an inherited default — the
same posture a gate's own depth 0 already has (§15.4).** No occurrence
of `merge` reasons about how far the chain fans out to decide its own
scope; a mechanical join belongs to the root because "the root" is
what merging into main means, the identical argument that keeps a
human gate's own depth at 0 by default. This keeps `merge` out of
every non-root instance's own effective sequence by the same
depth-ceiling mechanism filtering any other entry too deep for it —
nothing added.

**A non-root instance still merges — through its parent, not through
an entry of its own. Two interlocking rules, and neither is a second
mechanism:**

1. **A ticket cannot enter its own `reconcile` until every child
   blocking its completion has finished that child's own subflow** —
   `docs/v5-design-decisions.md` §7.2's child-blocks-parent rule, read
   as a precondition on *entry* rather than only on completion, the
   identical widening §7.8 already gave a container's own `blocks:`
   (§15.7), applied here to the ticket tree instead of a queue. A
   leaf's "own subflow" is its own effective sequence running out; a
   non-leaf's is its own `reconcile` having already joined its own
   children in turn.
2. **The moment a ticket enters `reconcile`, the plane mechanically
   merges every child now ready to merge, before the reconcile agent
   run reads what they produced.** This is `merge`'s own `ball`
   (`plane`, §15.1, above) doing the identical mechanical join it
   always does once a `reconcile` approves — the trigger is simply the
   *parent's* `reconcile`, for every instance that is not itself the
   root. A leaf merges the moment it and its parent both reach this
   point; a non-leaf merges the same way, once past the end of its own
   subflow.

Both rules are the same completion rule read twice — once as the
precondition that makes a parent's own `reconcile` well-timed, once as
the trigger that makes a child's own merge automatic — never a rule
about subflows, grouping, or the word "tree" beyond the doc-graph
shape a spawn already reads. **This is why `merge` leaves the
per-instance backbone without leaving the declared array's own
required backbone (§13):** every `ticket`-skeleton type still declares
exactly one `merge`, reconcile-preceded, load-checked the way §13
already states; only the instance sitting at the tree's own root ever
reaches it by its own dispatch, and every other instance's copy of the
same declaration means "merge, once your parent says so" rather than
"merge, once your own reconcile approves."

**This is not plane logic branching on grouping, and it is not in
tension with `docs/non-goals.md`'s automation-protocol entry.** That
entry's rule is about *states* — "a state may be declared iff no plane
logic branches on it" — extended by §15.10 to *groupings* of
already-legal entries, because a sub-array is an authored choice a
bundle makes; the entry itself never mentions grouping, and §15.10's
own extension says why it applies there. The trigger this section
uses is neither a state nor a grouping choice — `merge` is not implied
from "the end of a tier's own sub-array" or from "subflow exit" — it
is the doc-graph tree's own shape, a runtime fact the plane observes
the identical way spawning itself already does (v5 §7.10), never
vocabulary a bundle declares or arranges. §15.10's own concern — "we
fix the shape of the automation, not the shape of the organization" —
is untouched: no bundle says where a merge happens by how it writes
its array; every bundle gets the identical rule, and the tree a given
project happens to fan into is what decides which instances are root,
exactly as it already decides which instances have a `reconcile` in
their own sequence.

**Synthesis attaches to `reconcile`, and `reconcile` needs no
synthesis tier to mean something.** A chain bundle may declare a
generation tier — the `synthesis` edge type already in this grammar's
closed vocabulary (`Catapult.Dsl.Edge`'s `@types`), with edges to the
child nodes and/or their `critique` runs, plus the tier it synthesizes
into — whose own `delivery:` names `phase: reconcile`, dispatching
whenever the citing instance's own `reconcile` entry is reached and
producing the composed artifact that entry's own read then judges.
This is chain-side content, not a grammar addition: an unknown `phase:`
is already a load error against the platform's fixed vocabulary and
`reconcile` is in it (§13, §15.1 above), so a tier naming `phase:
reconcile` already resolves; which `agent_step:` it pairs that with —
a synthesis run is generation-shaped work dispatched at a review-shaped
status's own position, a combination this section names without
settling — is `bundles/**` content. **A `reconcile` with no synthesis
tier behind it is still a real fan-in, not a gap.** The mechanical
merge and the reconcile agent's own read (v5 §7.5) happen whether or
not chain content produces fresh prose at that position — a bundle
wanting no authored synthesis document gets a promptless join,
structurally present for gate-scope and staleness derivation exactly
as one with a synthesis tier is; declaring the tier only decides
whether a human reading the post-join gate sees a document a model
wrote, or the composed diff alone.

**What a component or subcomponent's own implementation work merges
into is answered by this array, not left open by it.** Every instance,
whatever its depth, runs a second generation-shaped sub-array — its own
`implementation`, real dispatched code (§15.1) — closed by the
identical `reconcile` test its own architecture phase already ran,
selecting nothing at a leaf instance's own effective sequence and its
own children's merged implementation at an instance with children. A
subcomponent's own `implementation` runs and its own `reconcile`
selects nothing (leaf, nothing to join, the identical test as the
architecture phase); a component's own second `reconcile` joins its
subcomponents' merged implementation the same way its first joined
their merged docs. No second array shape, no second declaration, no
field distinguishing "architecture's own join" from "implementation's
own join" beyond which sub-array a given instance's `reconcile`
occurrence closes.

### 15.12 A status entry's own name, and positions namespaced by it

**A `status:` entry carries a bundle-authored `name:`, distinct from
its kind, defaulting to the kind when omitted.** §15.1's kind table is
unchallenged by this — the closed, undeclarable platform vocabulary
every load-time predicate and every plane branch reads stays exactly
what it is, and nothing here grows it or lets a bundle invent a
member. What a bundle authors is a second, independent fact: what to
*call* a given occurrence of a kind. Without a name, telling two
occurrences of the same kind apart means growing the kind table itself
— `design`, `architecture` and `implementation` are three names for
what would otherwise be three indistinguishable `generation` visits
(§15.1) — which works only as long as a chain lifecycle's own visits
are few and fixed enough to deserve a platform-wide name each. A
bundle wanting two `critique` entries in one array, three `pending`
entries, or two `checks` entries has no such platform-wide need and
gets none: `name:` tells them apart without asking `docs/non-goals.md`'s
admission rule ("a state may be declared iff no plane logic branches on
it") to admit a fourth or fifth generation-shaped kind that no chain
lifecycle actually wants — nothing branches on a `name:`, so nothing
here is a state being declared in that rule's sense, only a label.

```yaml
- status: critique
  name: second-look        # optional; defaults to "critique"
```

**A position's identity is `<anchor>.<name>` inside a sub-array, bare
at the top level — derived, never declared.** §15.10 already fixes
exactly one non-review-shaped agent-balled entry per sub-array; that
entry's own name (bundle-authored, or its kind by default) *is* the
sub-array's namespace, the identical way a sub-array is already
referenced through the entry it contains rather than through a name
of its own (§15.10). Every other entry sharing that sub-array — its
leading `pending`, an intervening `checks`, a `critique` or
`reconcile`, a `review:` citation — is addressed as
`<anchor-name>.<its-own-name>`; an entry outside every sub-array is
addressed by its own bare name, the top-level array being its own
namespace. **One level only, and nothing qualifies an anchor by
anything it sits after or before** — a `reconcile` included: §15.11's
own gate-scope derivation is a fact about array order, read to decide
what a gate approves, never a second namespace level a position's
*identity* also carries. Two entries told apart only by which side of
a `reconcile` they fall on are not automatically namespace-distinct by
that fact alone; §15.4 above states what follows when that is the only
thing telling them apart.

**Names are unique within their own namespace — the top-level array,
and each sub-array — a load-time check.** No two entries sharing one
sub-array may resolve to the same name, the sub-array's own anchor
included (it is as much a member of its own namespace as anything else
inside it), and no two top-level entries — bare ones, or the anchors of
other sub-arrays — may share a name either. A default that would
collide (two undeclared `checks` entries in one sub-array, say, both
defaulting to the name `checks`) is exactly as much a load error as a
declared collision naming the same string twice on purpose; the fix is
identical either way — an explicit `name:` on at least one of them.

**A reference stays bare when it is unambiguous and must qualify when
it is not — ambiguity is a load error, never a silent pick.** `blocks:`,
`throwback:`, and any other reference into a `statuses:` array resolve
against the full set of namespaced positions the citing type's own
array declares. A bare name resolving inside exactly one namespace
resolves there; a bare name recurring across more than one namespace —
three sub-arrays each with their own `pending`, the shape this
section opens with — has no single answer and is refused at load
rather than silently resolved to whichever occurrence happens to come
first, the identical posture every other cross-reference in this
grammar already takes (§13: validate the reference, never guess the
shape). `<anchor>.<name>` is what a bundle author writes instead.

**A declared gate's own name stays disjoint from every addressable
status name in the loaded union — a load-time check.**
`Catapult.Delivery.FeatureLifecycle.Sequence.resolve_position/3`
decides whether a bare string names a gate or a status kind by
membership in the workflow's own declared gate set alone, and its own
documentation states this is safe because "a gate name is never also a
declared status kind" — true only while a gate's bundle-chosen name
and a status's platform-fixed kind are drawn from vocabularies that
cannot collide by construction: a bundle could cite the kind
`pending`, never declare it. A bundle-authored status `name:` breaks
that guarantee — nothing stops an author writing `name: ux-review` on
a `status:` entry inside a bundle that also declares a gate named
`ux-review`. The loader checks, across the whole loaded union, that no
declared gate name collides with any addressable status name, bare or
namespace-qualified, refusing the bundle at load rather than letting a
runtime resolution silently pick one meaning. Without this check a
collision resolves to `{:gate, name}` unconditionally and an
unrecognized name raises inside `String.to_existing_atom` — both on
the throwback path, both invisible until a decline actually fires,
which is the failure mode this check moves to load time instead.

**Every load-time predicate, and every plane branch, reads the kind —
never the name.** Nothing above changes what
`SystemStatus.agent_balled?/1`, `.generation_shaped?/1`,
`.review_shaped?/1`, `Status.non_review_shaped_agent_step?/1`, or
`Catapult.Dsl.Workflow`'s own `{:status, name} ->
SystemStatus.generation_shaped?(name)` branch on: the kind is the only
thing any of them has ever needed, and the authored name is purely a
label a human or a screen reads. This reaches a site that does not
look like predicate work: whether a `status:` entry admits `depth:` is
a fact about its *kind* (today, whether it is `critique`) and must
stay one — a `critique` entry given an authored `name:` is still a
`critique` for every purpose this grammar or the plane cares about,
`depth:` included, and a check keyed to the authored name instead
would silently stop admitting `depth:` the moment a bundle renamed the
entry that carries it.

**The projection keeps `status_kind` and carries a name beside it.**
`Catapult.Delivery.Store.tickets_for_project/1`'s `status_kind`/
`status_gate` columns are unaffected in shape and meaning — a gate's
own name was always its whole identity, and a status's kind is still
what every downstream branch reads. What is added is the authored
`name:` a status entry carries, read for display and for reference
resolution alone; `String.to_existing_atom` keeps operating on the
kind at every site it already does, and the name is a string that is
never atomized — the identical discipline `Catapult.Dsl.Fields`
already holds every other piece of bundle content to.

**Namespacing does not compose with depth.** A subcomponent's own
effective sequence (§15.11) reaches the identical declared type its
parent component does, at a deeper tree level — depth is a fact about
how far a declaration fans out, orthogonal to which sub-array a given
entry sits in within one instance's own array. `<anchor>.<name>` is the
whole of a position's identity within one instance's own effective
sequence, whatever depth that instance runs at; nothing here adds a
depth-keyed axis to it.
