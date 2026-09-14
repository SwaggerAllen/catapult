---
paths:
  - bundles/*/chain.yaml
  - bundles/*/schemas/**
  - bundles/*/prompts/**
  - bundles/*/flows/**
  - lib/catapult/dsl/**
  - test/catapult/dsl/**
---

# The chain

A chain bundle declares the document graph: which kinds of node
exist (tiers), how one node's draft mints others and refers to others
(edges), what each generating tier reads before it writes (context),
and what it contributes to the nodes around it (produces). The engine
walks that graph, dispatches an agent run for each ready node, and
validates what comes back against the tier's schema. `bundle.md` is
the contract for the file's place on disk and the seam with the
workflow; this is the contract for `chain.yaml` and the schemas and
prompts it names. Examples cite `bundles/default/chain.yaml` by tier
and edge name. Markers: **live** is read by the engine today;
**reserved** names the consumer that will read it.

## #1 The file

- **#2 `chain.yaml` has eight top-level keys**: `name`, `version`
  (reserved: the registry), `kind: chain`, `defaults`, `tiers`,
  `edges`, and the reserved `predicates` and `flows` (#36). A key
  outside this set, at any level, is a load error.
- **#3 `defaults:` carries per-tier scalars every tier inherits
  unless it says otherwise**, today `executor`. It never carries
  context, produces or any key that relates nodes. The default
  chain's `defaults: {executor: {effort: max}}` has its reason on the
  block: the first tiers sort and decompose rather than write prose,
  and a cheaper effort setting is where a decomposition loses
  structure.

## #4 Tiers

- **#5 A tier is a kind of node, and it is one of three things by
  what it declares.** A **generating tier** has a `phase:` and a
  draft: an agent writes its body (`feature_expansion`, `comparch`,
  `impl_backend`). A **join target** has a scope and no draft: its
  nodes are minted by a parent's draft and carry only the fields that
  draft gives them (`comp`, `resp`, `screen`, the three policy
  tiers). A **supplied tier** has a `generator: supplied` and a
  `source:` and no scope: its content arrives from outside the chain
  (`design_system`, `ref`). The keys a tier may carry are `scope`,
  `phase`, `draft`, `generator`, `source`, `prompt`, `review`,
  `reconcile`, `executor`, `handle`, `fields`, `context`, `produces`
  and the reserved `enforcement`; nothing else.
- **#6 `scope:` says how many nodes a tier has and who their parent
  is.** `singleton` is one node per project; `per(X)` is one node per
  node of tier X, and X is the scope parent; `child_of(X)` is one node
  per element that tier X's draft mints through a `fanout` edge, and X
  is the scope parent; `cascade_visit` (reserved: the flow engine,
  #38) is one node per scaffold node a flow visits. A supplied tier
  has no scope.
- **#7 `phase:` names the workflow position a generating tier runs
  at, and the paired type must declare it** (`bundle.md` #11,
  `workflow.md` #22). It is required on every generating tier and is
  the only cross-axis key a tier carries. Dispatch gated by the
  ticket's resting position is reserved: delivery Phase 7; until it
  lands, the sweeper dispatches every ready node and `phase:` decides
  what the board shows.
- **#8 `draft:` names the body's root element and schema, and its
  absence is what makes a join target.** `root_tag` defaults to the
  tier name and `grammar` to `schemas/<tier>.xsd`; a tier writes the
  key only where the default is wrong (`impl_backend`, `impl_ui` and
  `impl_screen` share `schemas/impl.xsd`). `generator:` defaults to
  `llm`; `supplied` is the other live value (#17); `external`,
  `template`, `git_commit` and `webhook` are reserved (#39).
- **#9 `prompt:` defaults to `prompts/<tier>.md.liquid`** and is
  written only where the file lives elsewhere, as the five flow plan
  tiers do (`flows/<flow>/plan.md.liquid`).
- **#10 `executor:` is the profile the runtime binds a tier's agent
  run to** (reserved: the LLM bindings in `systems/llm.md`), a map of
  `effort` and whatever a binding reads; it defaults to
  `defaults.executor`. Which agent implementation runs a tier is this
  profile's to say, never a separate kind on the tier.
- **#11 `handle:` is the projection other tiers read, and it defaults
  to every field plus every kind produced onto the node.** A tier
  that narrows it lists a subset of that set; a name outside it is a
  load error. No tier in the default narrows.
- **#12 `fields:` in the chain file names only cross-node copies.** A
  join target may declare `<name>: mint.parent.<kind>`, copying the
  parent's produced fragment of that kind into the child at mint
  (`subcomp` carries its component's `techspec`, `pubapi`, `privapi`,
  `policies` and `failure_surface` this way). Every other field, a
  draft's own elements and a mint element's own attributes, is an
  annotation in the schema (#32).
- **#13 `produces:` maps a fragment kind to the draft path that
  authors it, and the owner is always the scope parent.**
  `comparch`'s `techspec: draft.technical-specification` lands on the
  `comp` it is `per(...)`; the bundle's fragment vocabulary is the
  union of the kinds so produced, declared nowhere else.
- **#14 A review is a property of the tier it reviews, declared as
  `review:`.** `review: default` reads
  `prompts/review/<tier>.md.liquid` with the tier's own effective
  context (#20, #21) plus `draft`, and runs at the first
  critique-shaped position after the tier's own in the paired type
  (`workflow.md` #26). A map form overrides any of `prompt`, `context`
  and `phase`. Seventeen of the default's 22 generating tiers are
  reviewed; the five flow plan tiers are not.
- **#15 A fan-out tier may carry `reconcile:`, the prompt an agent
  runs when its children's PRs are joined.** `reconcile: default`
  reads `prompts/reconcile/<tier>.md.liquid` and runs at the first
  reconcile-shaped position after the children's positions
  (`workflow.md` #27); a map form overrides `prompt` and `phase`. The
  mechanical merge and the reconcile read happen whether or not a
  tier declares one (v5 4231); the block decides only whether a human
  at the post-join gate sees an authored document or the composed
  diff. The default declares it on `sysarch`, `comparch`,
  `frontend_sysarch`, `ui_collarch` and `screen_collarch`.
- **#16 `enforcement:` lists the enforcement profiles a tier's
  produced code is held to** (reserved: delivery, v5 §2.14). Each
  name must be an installed profile.
- **#17 A supplied tier's `source:` says where its content comes
  from, and a supplied node is never generated and never drained.**
  `input.<role>` pins the intake documents tagged with that role at
  intake (`design_system`); `write` (reserved: the reference write
  path, `systems/core_dsl.md`) is content written by a path outside
  the chain (`ref`). Re-pinning a source is what re-drains what reads
  it.

## #18 Context

- **#19 A walk names a node to start from, edges to follow, and what
  to read at the end.** `self` and `self.parent` start it; each
  `.<edge>` hop follows a declared edge from the current node, and a
  trailing `~` reverses the hop to match the edge's target instead of
  its source; `-> <tier>.handle` or `-> <tier>.handle.fragments[<kind>]`
  types the far end and names the projection. `all.<tier>.handle`
  reads every node of a tier with no walk; `input.<role>` and
  `input.*` read intake documents. Every hop is checked at load
  against the declared edges; the graph it runs over is runtime
  state.
- **#20 Most of a tier's context is derived from the edges, and the
  derivation is the rule, not a convenience.** A generating tier
  reads its scope parent's handle as `parent`, and for every edge
  instance whose source is the tier itself or its scope parent it
  reads the far end projected by the edge's `context:` (#25), under
  the edge's name, or the instance's `as:` (#27). Two derived reads
  under one name in one tier is a load error unless the second
  instance names itself. `subcomparch` declares no context and reads
  three things: its `subcomp`, that subcomponent's dependencies'
  public surfaces, and its references.
- **#21 `context:` adds to the derived reads and never removes one.**
  It is a map from variable name to walk; the explicit reads are
  every `all.<tier>` and `input.<role>` read, every reversed or
  multi-hop walk, and any second projection of an edge the derivation
  already gave (`comparch` adds `failure_surfaces`, the
  `failure_surface` fragment of the same dependencies whose `pubapi`
  it reads by derivation). A name that collides with a derived read
  or with `self`, `draft`, `feedback` or `prior_review` is a load
  error.
- **#22 Context is the only readiness signal.** A node is ready when
  every node its structural reads (#20, and the explicit walks from
  `self` or `self.parent`) resolve to is approved; a walk that
  resolves to many requires all of them. `all.<tier>` reads require
  the tier drained, every node of it approved, and are refused at
  load when the reading tier is in the target tier's driver closure,
  because it could never drain; a tier is drained only when it has
  exactly one minting parent (#28). `input.*` reads never block: a
  role with no documents yields an empty collection. Inside a flow
  ticket, a plan tier's `all.<tier>` reads are of the approved graph
  the flow is about to regenerate (reserved: the flow engine, #38).
- **#23 A `navigation: true` edge carries no context and no
  readiness in either direction.** `navigation` in the default
  connects screens for the journey's sake and is read by nothing.

## #24 Edges

- **#25 An edge declaration has a `type`, a `context` projection, an
  optional `graph_constraint`, and a list of `instances`.** `context:`
  is `handle`, `handle.fragments[<kind>]` or `none`, and is the read
  every tier gets for each instance from itself or its parent (#20);
  `graph_constraint: [acyclic, no_self_loop]` is checked over the
  instances at projection time (#30); `consistency: eventual |
  transactional` is reserved (delivery, v5 §7.5); `navigation: true`
  is #23.
- **#26 Five edge types.** `fanout` mints the target's nodes from the
  source's draft and carries no context, since a parent never reads
  the children it has not written yet; `reference` cites an existing
  node; `dependency` is a reference the engine orders builds by;
  `policy_application` scopes a policy to what it governs;
  `synthesis` (reserved: the flow engine, #38) is the correspondence
  a plan tier's cascade rides on.
- **#27 An instance names its `source` and `target` tiers, the draft
  path that declares it, and where the endpoints are read from.**
  `declared_in` is `<tier>.draft.<path>` for an element in a draft
  or `<tier>.mint.<marker>` for a marker on a mint element (#29);
  `source_ref` and `target_ref` are written explicitly wherever the
  endpoint is not the declaring node, as `"@from"`, `"@to"`, `"@ref"`
  or `self.parent`. An instance may override the edge's `context:`
  (`ui_coll → design_system` reads `handle`, since a supplied node has
  no fragments), name itself with `as:` when it shares a source with
  another instance of the edge, and carry `when:` (reserved, #37).
  A `synthesis` instance's `target` may be a list. There is no
  single-instance form: an edge with one instance writes a list of
  one.
- **#28 A tier has exactly one minting parent.** Two `fanout`
  instances may not target one tier; a pool minted from several
  drafts is a family of same-shaped tiers, one per parent
  (`sysarch_policy`, `comparch_policy`, `non_goals_policy`), because
  readiness is per tier and a tier with two drivers can never be
  known drained.
- **#29 `declared_in` reaches into a draft or onto a mint.** A draft
  path walks elements by name with `[]` for a repeated element
  (`sysarch.draft.components.component[]`); a mint path names a marker
  element or attribute on the minting element
  (`comparch_policy.mint.required`), which is how a policy's own
  `<required>` child becomes its `policy_application` instance.
- **#30 Graph constraints are checked when a draft commits, against
  the instances it declares.** `acyclic` and `no_self_loop` on
  `dependency` reject a body whose dependencies would close a cycle,
  with a typed error the agent can retry against.

## #31 The schema's half

- **#32 A schema annotates what the chain file no longer says.**
  `<catapult:mints tier="comp" identity="alias"/>` in an element's
  `xs:appinfo` says the element mints that tier and which attribute
  is its identity, one of `id`, `alias`, `name` or `slug`;
  `<catapult:identity>id</catapult:identity>` on a draft's root says
  the same for a generating tier; `<catapult:field name="purpose"/>`
  on an element or attribute makes it a field of the node the
  element belongs to. The loader reads these where it reads the
  schema, and a `produces` path or a `declared_in` path that resolves
  to no element is a load error.
- **#33 Occurrence bounds are the schema's, and the commit path
  enforces them.** How many components a system may declare and
  whether a subcomponent may have no dependencies are `minOccurs` and
  `maxOccurs`; every draft is validated against its schema before the
  event that commits it lands, and a body that fails is rejected with
  the validator's message. A constraint the schema cannot state, one
  that counts children by a field value, is a predicate (#37).

## #34 Prompts

- **#35 A prompt is a Liquid template whose variables are the tier's
  effective context by name.** Every derived read (#20) and every
  explicit read (#21) is a variable of that name; `self` is the node
  being written, `draft` the current body in a review or reconcile
  prompt, `feedback` and `prior_review` the last critique's output
  on a regeneration. Shared prose lives in
  `prompts/partials/<name>.md.liquid` and is included with
  `{% render %}`; a variable a partial needs is passed with `with` or
  `for`, since a partial does not see the caller's variables.

## #36 Reserved

- **#37 `predicates:` names the invariants a projection rejects a
  commit for, and the conditions a flow completes on.** (Reserved:
  the commit path for `when:`, the flow engine for `completion:`.)
  The language has comparison, boolean, edge-counting, existential,
  universal and reachability operators and nothing else; a predicate
  is named here and cited by a `fanout` instance's `when:` or a flow's
  `completion:`. The default names `has_foundation_child` for the
  rule that every level of decomposition has a foundation child,
  which `minOccurs` cannot count.
- **#38 `flows:` declares the traversals a ticket may open.**
  (Reserved: the flow engine, v5 §7.2.) A flow names its `walk`
  (`full`, `downward_cascade`, `up_then_down`), the `entry` tier the
  cascade enters at, the `delta` of tiers and edges active only in
  it, and
  the workflow type it dispatches into as `ticket: {type, labels}`,
  which is the second cross-axis reference and is checked like the
  first (`workflow.md` #22). A plan tier is `cascade_visit`-scoped,
  runs at the flow's `plan` position, and reads the approved graph
  through `all.<tier>`; the `synthesis` edge from it to each spine
  tier is what the cascade follows. The `seed` flow is the whole
  chain with no delta.
- **#39 Four generator types and every context-source kind beyond
  `input` are extension vocabulary** (reserved: the registry, v5
  §9). `external` resolves a node's content from the component
  registry at a pinned version; `template` renders a node from
  `template:` with its context walks as slots, no agent run, validated
  like any draft (reserved: the commit path); `git_commit` and
  `webhook` take a node's body from a repository commit or an inbound
  post, so that repository history and external events can serve as
  context and as flow triggers.
