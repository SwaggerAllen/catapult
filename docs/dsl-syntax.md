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
and `gates:` / `environments:` globs in place of the chain's lists.
The file-list keys are per-kind: a `tiers:` list in a workflow bundle
is an unknown field and a load error, per §13.

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
  - self.parent.dependency -> target.handle.fragments[pubapi]
produces:                         # fragments this draft writes on other nodes
  - fragment: { owner: self.parent, kind: techspec, authored: draft.techspec }
review:                           # optional; presence enables the review pass
  prompt: prompts/review/comparch.md.liquid
  grammar: schemas/review.xsd
  required: false                 # true gates approval on review commit
delivery:                         # extension-provided namespace (§12)
  phase: Architecting             # platform-fixed vocabulary only (§11):
  agent_step: design              # statuses, queues, agent steps — never a
                                  # workflow bundle's gate or environment
enforcement: []                   # extension-provided profiles, e.g. [codegen: restricted]
```

Per-scope attributes that appear in *body* declarations rather than
tier files (they vary per node, not per tier): `implementation:
stubbed | real` with `swap: transparent | migration | reset` (v5
§2.16), declared in the comparch grammar; `locus: server | client`
(v5 §5.6) on backend-family component declarations.

### 3.1 Scope expressions — closed set

- `singleton` — one node per project.
- `per(X)` — one node per node of tier X. `self.parent` is that node.
- `child_of(X)` — nodes minted by X's fanout edge.

**Delta from v4: the phased variants (`per(X) × phase`) are removed**
with the phase machinery (v5 §6). There is no `phase` dimension.

### 3.2 Generator types — closed set, extension-growable

`llm` (default), `git_commit` (+ `code_repo_url`, `path_from_handle`),
`synthesis`, `webhook`, and the v5 additions: **`external`** (content
resolves from the component registry at the pinned version; requires
`package:` and optional `options:` per v5 §3.4) and **`template`**
(deterministic scaffold; requires `template:` path; slots filled from
context walks; no LLM call, same grammar validation).

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
```

Rules carried from v4, still normative: the full edge-instance graph
must be **type-level acyclic** at load; `graph_constraint: acyclic`
is additionally checked per-instance at projection time; `declared_in`
paths parse against committed bodies.

**v5 rule:** navigation edges (product tier, screen→screen) are
cyclic-legal reference edges and **must never appear in a readiness-
bearing context walk** — the loader rejects a context entry that
traverses an edge marked `navigation: true`.

## 5. Fragments

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

## 9. Prompts

Liquid (Solid). Variables: one per named context walk
(cardinality-many walks iterate), `self`, `feedback`, `prior_review`,
and — review prompts only — `draft`. Shared content via
`{% render "partials/<name>" %}` (v5 §6: one source for shared
framing across the six architecture tiers). Generation and review
templates for a tier receive identical context plus `draft` — the
per-tier triad invariant, enforced by the shared context-assembly
path, not convention.

## 10. Grammars

Body grammars are XML-fragmented markdown validated per tier
(`draft.root_tag` + XSD), at commit time, atomically — validation
failure is typed feedback, never a half-committed state. The review
grammar is platform-wide (v4 §B.3.2's `<review>` shape). v5 grammar
growth (the productions, not the prose): comparch carries
`<permissions>`, `<enforcement>`, per-scope `<implementation>`;
subcomparch carries the process inventory; impl's `<tests>` block is
normative for reconciliation.

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
- `extends:` never crosses axes, and each named bundle's `kind`
  matches the `catapult.yaml` key that named it;
- **a gate whose role has no holders is a load error**, not a runtime
  condition — otherwise a deadlocked gate is indistinguishable from a
  slow reviewer (v5 §7.16);
- a gate's exits (forward and throwback) resolve to states that
  exist, and its declared escalation policy is well-formed;
- every declared review state has a counterpart in the mirror mapping
  when the outbound tracker add-on is configured (v5 §7.17) — an
  unmapped state is the failure that has halted a sweep before;
- §7.6's naming discipline over the *declared* set: no two states, or
  a state and a label, one hyphen apart in meaning — cheap against a
  fixed list, and an actual check against a declared one;
- a workflow bundle under the `runtime` dialect is a load error, not
  dead weight: that dialect has no review lifecycle (§12).

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
kinds).

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
tier), `dev` (implements a child scope), `reconcile`, `validate`
(§7.11's repair loop), `boundary` (the milestone pass). Adding one is
a platform change, reviewed as one.

### 15.2 `gates/<gate>.yaml` — a review status

```yaml
review: ux-review               # status name; unique in the loaded union
after: product-review           # predecessor: a system status or another
                                #   review in this bundle (§15.3)
role: design                    # who signs off; identity holds the
                                #   holders, bindings the reviewers: map
ticket_types: [feature]         # which types visit it; omitted = all
depth: 1                        # fan-out depth (v5 §7.19); omitted = 0,
                                #   top level only. A maximum, never
                                #   validated against the chain.
throwback: [product-design]     # exits it may reject to; each must be
                                #   earlier in the effective sequence
escalation: author              # policy; human gates are author-owned
```

Approval is the transition itself (v5 §7.16) — there is no approval
object, and no `approvers:` list. Who approved is answerable from the
log because the plane records the command with its actor.

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
depth: 0                        # top level only, the usual case
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
