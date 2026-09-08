---
paths:
  - lib/catapult/engine/**
  - test/catapult/engine/**
  - priv/repo/migrations/**
---

# engine

The reactive core: the Commanded application, per-project aggregates
and the event log, the reducer, the universal projections (nodes,
edges, fragments, drafts, reviews, ready_scopes, staleness, flows),
the reactive scheduler with its sweeper, and replay/rebuild. The
first consumer of the ES store family (v5 §2.4) — its purity floors
and `events/0` registry are proven here before any target app uses
them.

## Standing decisions

- **The log is the source of truth; projections are derived and
  disposable.** Rebuild-from-zero byte-identity is a standing test:
  replaying the full log into fresh projections must equal
  incremental state, always. This is also the
  recovery mechanism — no projection surgery, ever.
- **The scheduler is state-driven, not event-driven**:
  readiness is a query against current projections, so the same
  query answers "ready now" and "ready at sequence T," and there is
  no in-memory pending-set to corrupt. Fast path via PubSub;
  sweeper as the convergence floor.
- **"Write the ready_scopes row" (the scheduler's rule 3) is a PubSub
  broadcast, never a table write** — the same "never materialized"
  standing decision below applies to the scheduler's own output, not
  only to the query it wraps. On each trigger the scheduler re-runs
  `Catapult.Engine.Projections.ReadyScopes.ready/3` (rules 1 and 2)
  for the tiers the trigger could have affected and broadcasts the
  resulting `(tier, scope)` pairs on `engine:ready_scopes:<project_id>`
  (naming spine, `Catapult.Engine.Topics`, conventions §3). The
  scheduler holds no memory of what it last broadcast — diffing
  against a remembered ready-set to announce only deltas would be
  exactly the in-memory pending-set the state-driven doctrine refuses
  to grow, so it re-announces liberally instead: every event that
  could plausibly move readiness (draft committed, draft approved,
  bundle flipped) re-triggers the query and the broadcast fires
  unconditionally on that trigger, whether or not the ready set
  actually changed. The payload is a hint, never an authority: a
  consumer re-validates before acting on it (§7.1's validate-or-revert
  discipline, applied to an internal signal the same as an external
  one), which is also why the broadcast needs no de-duplication of its
  own — whatever a consumer does with a ready pair is idempotent on
  its own side regardless of how many times the pair gets announced.
- **The scheduler dispatches to no component by name.** Generation and
  delivery both land after this ticket in the build order
  (`docs/build-plan.md` Phase 3/4), so the scheduler cannot call an
  enqueue function that doesn't exist yet and must not be built to
  assume one particular shape for a consumer that hasn't landed.
  "The engine writes it; generation and delivery consume it" (below)
  is a claim about which side owns the *readiness signal* — engine,
  exclusively, which is what makes "nothing else initiates work" true
  — not about the engine performing generation's or delivery's own
  outbox insert. When each consumer lands, its own ticket names the
  cross-component edge, and conventions §7's pattern ("insert the job
  through the target's exported enqueue function inside the local
  transaction") applies on *its* side of the subscription, not this
  one's.
- **Review-tier dispatch is a second, simpler readiness rule, not an
  extension of the context-walk one.** `ReadyScopes.ready/3` filters
  review tiers out entirely (`generation_tier?/1`) because §7.19
  already settled their dispatch: fired one cycle after the tier they
  review commits, unconditionally — no context walk of their own to
  gate on. Left unaddressed, that exclusion would make review dispatch
  bypass `ready_scopes` altogether, which is exactly the "nothing else
  initiates work" invariant this ticket exists to hold. The
  scheduler's enumeration therefore carries two rules feeding one
  signal: a tier's own context-walk readiness for generation tiers, and
  "the reviewed tier's current draft has no review yet" (already
  answerable via `Store.reviews_for_draft/1`) for review tiers — both
  land on the same broadcast, so a consumer never has to know which
  rule produced a given pair.
- **`scope_filter` is evaluated where readiness is, and answers a
  different question than the context walk does.** A node failing its
  tier's `scope_filter` is not a candidate at all — it never appears in
  enumeration, which is distinct from appearing and being not-yet-ready.
  Evaluation is a new engine-side predicate evaluator, beside
  `ContextResolver` and built on the same `Store` edge/node primitives,
  because a `scope_filter` predicate (`has_edge`, `count`, `exists`,
  `all`/`any`, `reaches`) needs live graph state the same way a context
  walk does. Built as the shared home for the predicate language's
  other three slots (`cardinality.when`, an edge `constraint`, a flow
  `completion`, `dsl-syntax.md` §8) when their own tickets land, not a
  one-off for this slot alone.
- **`input.<role>` and `input.*` resolve to `{:ok, []}`, always — never
  a real target, never `{:error, :unsupported}`** (ORC-107, closing the
  gap `systems/generation.md`'s ORC-10 entry names). `ContextResolver.resolve/2`
  used to fold `:input` into the same `when source in [:input, :ticket]`
  clause as `:ticket`; that guard is split, because the two sources stay
  unsupported for different reasons and only one of them is this
  ticket's to fix — `:ticket` is untouched, still `{:error, :unsupported}`,
  v5 §7.11's Phase 7. `:input` covers both the `role` and the wildcard
  forms identically: neither is a graph walk (an input document is
  pinned prose, not a node with a tier, a status, or edges — the
  intake entry below is where the pinned content actually lives and
  how a prompt reads it), so `ContextResolver` — whose whole job is
  walking *declared node/edge instances* — has nothing to resolve
  either form against and says so the same way for both.

  **The empty list is the whole mechanism, not a placeholder for one.**
  `ReadyScopes.walk_ready?/2` and `.walk_report/2`, and `Staleness
  .walk_stales?/2`, already fold `{:ok, targets}` generically —
  `Enum.all?(targets, &(&1.status == :approved))` on an empty list is
  vacuously true, `Enum.any?(targets, &target_newer?/2)` on an empty
  list is vacuously false. Neither module gained a line for this: an
  `input.<role>` walk is therefore *structurally* incapable of blocking
  readiness or reporting staleness, which is dsl-syntax.md §7's "a role
  with no documents never blocks readiness" and v5 §1.1's "an input-doc
  edit... stales nothing" — both already true of every `{:ok, []}`
  regardless of source, so neither invariant needed a bespoke branch
  written *for* it. The alternative — modeling a pinned input document
  as a synthetic `Node` so it could flow through the existing
  `{:ok, [Node.t()]}` shape uniformly — was rejected: it would need a
  fabricated `status` for every consumer's status check to key off, and
  the one status that keeps both call sites correct (permanently
  `:approved`) is a fact about the readiness query, not about the
  document, which is exactly the "special case grown to fit an escape
  hatch" this system's standing decisions elsewhere refuse (see
  "Navigation edges get no second check," above).

  **Consequence for `explain/2`:** an `input.<role>` walk now resolves
  satisfied with zero targets, the same shape a fully-satisfied ordinary
  walk has, so `Enum.reject(& &1.satisfied)` drops it from `blocking`
  entirely — it no longer carries `reason: :unsupported`. Only
  `ticket.<source>` walks still do. `screens/explain-why.md` and its
  storybook fixture are corrected to match (ORC-107).
- **Explain-why is `ReadyScopes`'s own second query, not a parallel
  implementation.** "What is blocking this scope"
  (`systems/dashboard.md`'s naming) reuses `candidates/2` and the same
  per-walk resolution `ready?/2` already does, replacing the boolean
  fold with a structured report: which context-walk entry is unmet,
  and for each of its resolved targets, its current status. Built
  beside readiness because both read the same candidate/target
  machinery — a second traversal implementation is the drift risk, not
  the convenience.
- **Navigation edges get no second check in the engine.**
  `Catapult.Dsl.Chain` already refuses to load a context walk that
  traverses a `navigation: true` edge (dsl-syntax.md §4, §13) — the
  readiness and explain-why queries walk only what the loader already
  proved is readiness-bearing, and add no redundant edge-kind filter of
  their own. Restated here because a query written defensively
  (checking a property its input already guarantees) is exactly the
  kind of drift-prone duplication `core_dsl.md`'s "all validation at
  load time where possible" standing decision exists to prevent.
- **Creation is not dispatchability, and the engine needs no new node
  status to hold that line.** `Reducer.apply_mint/2` already lands a
  minted child at `status: :absent` the moment its parent's draft names
  it (v5 §7.10's "children are created when the plan node names them"),
  and an `:absent` node's readiness is exactly its declared `context:`,
  evaluated the same as any other node's — nothing about having just
  been minted makes it a special case. A bundle wanting a child gated
  on its parent's workflow gates points that child tier's context at a
  walk the parent's review/approval flow actually resolves through
  (the node's own `:approved` status, set only once its review tier's
  chain-axis pass lands); the gating is therefore a bundle-content
  decision, not an engine mechanism, and no `:pre_queue` node status is
  introduced to duplicate what the context walk already expresses.
  §7.2's child-blocks-parent (completion) and any future
  `openBlockerFor`-style check are delivery's concerns over the ticket
  tree, not this system's over the node graph, and the readiness query
  never treats a node's children as a precondition of that node's own
  readiness — only its declared `context:` is.

- **A join-target tier mints straight to `:approved`, and the mint-
  time default is what changes — readiness needed no new rule**
  (ORC-117, design pass). The bullet above assumed every minted child
  eventually earns `:approved` through `DraftApproved`, and that
  assumption is false for exactly the tiers dsl-syntax.md §3 calls a
  **join-target tier** — one declared with no `draft:` block (`comp`,
  `subcomp`, `resp`, `policy` in `bundles/default`, all `generator:
  synthesis` today, though the condition that matters is "no `draft:`,"
  not the generator kind — see below). Such a tier commits no draft, so
  no `DraftCommitted`/`ApproveDraft` pair ever runs for it, and
  `Store.approve_node/2`'s one caller (`Reducer.apply(%DraftApproved{},
  _)`) can never name it. Minted at `:absent` per the bullet above, a
  join target sits there forever, and `walk_ready?/2`'s `status ==
  :approved` — dsl-syntax.md §7's "readiness requires all targets
  ready; context is the only readiness signal" — never turns true for
  any tier whose context walk reaches it (`comparch`'s `per(comp)`
  `self.parent.handle`, and the same shape for `subcomparch`). The
  chain stalls at the first join target and never reaches the tiers
  downstream of it.

  **The fix is where the node is minted, not where readiness is
  read.** `Catapult.Engine.Reducer.apply_mint/2` stops hardcoding
  `status: :absent`; the mint entry itself now carries the status to
  write — `:approved` when the target tier declares no `draft:`,
  `:absent` otherwise — and the reducer copies it onto `Store
  .mint_node/1` unchanged, the same "copy, never derive" shape every
  other reducer branch already follows. `Node.status` keeps its
  existing three values — `:absent`, `:drafted`, `:approved` — no
  fourth value for "synthesized, never reviewed." A join target's
  `:approved` is a deliberate reuse of the readiness-only reading of
  that atom ("this node satisfies anything walking toward it"), not a
  claim that a human or a draft was ever approved; recorded here so a
  later pass doesn't split it into a fourth status to make the name
  more honest.

  **What a reader makes of that value is a separate question from
  what the mint writes.** `status: :approved` at mint time answers
  "does this node itself have anything left to review" — correctly,
  since a join target never does — but a reader walking onto it is
  asking a different question, "has the content behind this node
  settled," and the two coincide only once the draft that minted the
  node is itself approved. So `walk_ready?/2` and `explain/2`'s
  `walk_report/2` resolve a target through `settled?/2` (below)
  rather than testing `status` directly, and the "is this target's
  tier a join target" check lives in exactly one place, shared by
  `ready?/2`'s boolean fold and `explain/2`'s structured one — never
  folded independently into each, which would be two computations of
  one fact.

  **Why the condition is "no `draft:`," not "`generator: synthesis`."**
  Every join-target tier in `bundles/default` happens to declare
  `generator: synthesis`, but the causal fact is the missing `draft:`
  block: that's what makes `DraftCommitted`/`DraftApproved` structurally
  unable to name the node, and dsl-syntax.md §3 already has a name for
  a tier in that shape — "join-target tier" — independent of which
  `generator:` it declares. Keying the mint-time default on `tiers
  .<target>.draft == nil` rather than on the generator atom is what
  answers this ticket's own open question — whether the fix generalises
  to a future `generator:` kind that also produces no draft (`external`,
  `template` per dsl-syntax.md §3.2, neither of which happens to omit
  `draft:` in `bundles/default` today) — without needing to revisit this
  decision when one does: any tier a bundle author writes with no
  `draft:` gets the same mint-time `:approved`, whatever its `generator:`
  says.

  **Where the value is computed: the command edge, not the reducer.**
  `Catapult.Generation.Extraction.mints/4` already resolves the target
  tier's full declaration (via `chain`) to build each mint entry's
  `tier`/`scope_key`/`edge_name` — the same lookup that already has
  `chain.tiers[instance.target].draft` in hand gains one more field on
  the entry it returns, threaded unchanged through `Catapult.Engine
  .Commands.CommitDraft`'s `mints:` and onto `DraftCommitted`'s own
  `mint()` type. This keeps `Catapult.Engine.Events.DraftCommitted`'s
  own moduledoc true without qualification — "extraction against the
  bundle's `declared_in` paths happens at the command edge... never
  inside the reducer" — rather than having `apply_mint/2` load a
  `Chain` to answer the same question, which is exactly the impure,
  bundle-content-dependent read this system's purity floor and the
  fourth ORC-34 design-review correction (below) both already ruled out
  for a different value. `system:generation` carries this ticket
  alongside `system:engine` for that reason: the decision is engine's
  (what a join target's status means), the computation is generation's
  (where the tier's declaration is already being read).

  **This also settles two of the ticket's other open questions.**
  `policy` (`bundles/default/tiers/policy.yaml`) is `generator:
  synthesis` with no `draft:`, structurally identical to `comp`/
  `subcomp`/`resp` — checked, not assumed — so it gets the identical
  fix. That `Extraction.mints/4`'s `id`/`alias` identity fallback is
  verified only against `sysarch`'s own `<component alias="...">`
  shape, and mints `resp`/`vocab`/`policy` a `nil` scope_key otherwise
  (the module's own comment on `identity_value/2`, and
  `test/catapult/generation/toy_seed_chain_test.exs`'s moduledoc, which
  is why that test still seeds those three by hand even after this
  fix) is a real but separate gap in *identity extraction*, orthogonal
  to a join target's *status* — this ticket closes the latter, not the
  former. `vocab`
  (`bundles/default/tiers/vocab.yaml`) declares a `draft:` block and is
  unaffected, matching the ticket's own read. And `Catapult.Engine
  .Projections.Staleness.stale?/2`'s early `:absent` clause ("not
  stale, merely not drafted") stops matching a join target once it
  mints at `:approved` — checked rather than assumed to be safe: every
  join-target tier in `bundles/default` declares no `context:` of its
  own (there is nothing to gate its own generation on, since it is
  never dispatched — `generation_tier?/1` requires `draft` non-nil),
  so `stale?/2`'s general clause (`Enum.any?(tier.context, ...)`)
  degenerates to the same `false` the `:absent` short-circuit already
  gave. **Named rather than silently relied on:** nothing at load time
  stops a bundle from declaring `context:` on a tier with no `draft:`
  the way `Catapult.Dsl.Tier`'s `@review_forbidden` already stops one
  on a review tier — a gap in `core_dsl`'s own validation
  (`lib/catapult/dsl/tier.ex`, outside this doc's file map), not this
  ticket's to close, but worth stating so a future bundle author
  hitting it reads a known gap rather than a surprise.

- **A node's readiness-effective status is resolved, not read bare —
  a join target defers to whichever node minted it, recursively**
  (ORC-235, design pass). `walk_ready?/2` and `explain/2`'s
  `walk_report/2` stop testing `target.status == :approved` directly
  and instead call one shared resolver — call it `settled?/2` here,
  named for the concept rather than committing dev to a literal
  function name — that both already fold generically over a walk's
  targets:

  - a target whose tier declares a `draft:` (`chain.tiers[target.tier]
    .draft != nil`) is `settled?` exactly when `target.status ==
    :approved` — unchanged, the ordinary review/approval path;
  - a target whose tier declares no `draft:` and is not `generator:
    supplied` (a join target fanned out by some other node's
    `DraftCommitted`) is `settled?` exactly when its minting parent is
    `settled?` — `Store.get_node(project_id, target.parent_node_id)`,
    recursed through the same predicate. `apply_mint/2` already writes
    `parent_node_id: event.node_id` (the committing node, i.e. the
    minting parent) for every mint, and a `per(X)` node's own
    `parent_node_id` is already its `per`-parent for the identical
    reason (`Reducer.apply/2`'s `DraftCommitted` clause,
    `parent_node_id: event.parent_node_id`) — this fix reads a field
    the reducer already writes, on both sides of the recursion, and
    adds no column. A node reaching this branch with `parent_node_id
    == nil` is a data-integrity error to surface, not a signal to read
    as settled — every fanout mint writes this field, so its absence
    here means the mint itself is broken, not that the node has
    nothing to wait on;
  - a target whose tier declares `generator: supplied` (`design_system`
    is `bundles/default`'s only instance today) is `settled?`
    unconditionally, the moment the node exists at all — keyed on the
    tier's own declaration rather than on `parent_node_id == nil`, so
    a genuine join target that somehow reached the store with no
    parent recorded falls into the error case above instead of reading
    as settled by coincidence. A supplied tier is pinned complete at
    intake (v5 §1.1, §5.4) with nothing upstream in the generation
    chain that produced it and could still revise it — the join-target
    recursion above exists because a join target's content traces back
    to a draft that may not yet be approved, and a supplied node has no
    draft anywhere in its history to be unapproved.

  Recursion terminates because a node's `parent_node_id` chain is
  acyclic by construction: a node's minting parent is committed, and
  exists as a stored row, strictly before the mint that names it as
  parent, so no chain of `parent_node_id` lookups can revisit a node
  still being resolved. The tier graph's own type-level acyclicity
  check (`core_dsl.md`'s standing decision) does not cover this
  guarantee: that check covers which tiers may name which as `per(X)`/
  `child_of(X)` targets at the schema level, and says nothing about
  instance-level `parent_node_id` pointers, which is the thing this
  recursion actually walks. A join-target chain in `bundles/default`
  today is one level deep
  (`comp`'s minting parent is a `sysarch` node, which has a `draft:`
  and stops the recursion there), but nothing in the rule assumes that
  depth. This closes the concrete cases the ticket named: `comparch`'s
  `self.parent.handle` now requires the `comp` it reads to trace back
  to an `:approved` `sysarch`, not merely a minted one, and the
  identical shape fixes `subcomparch` off `comparch`, `ui_collarch`/
  `screen_collarch` off `frontend_sysarch`'s minted `ui_coll`/
  `screen_coll`, and every `all.journey.handle`/`all.screen.handle`
  read that lands on a `journey`/`screen` node once one exists.

  **What this does not touch:** `Node.status`'s three values, the
  mint-time write itself (still `:approved` for a `draft:`-less tier,
  ORC-117 above, unrevisited per this ticket's own "not in scope"), and
  `ContextResolver.resolve/2` — a walk still resolves to exactly the
  targets it always did; only how a resolved target is judged
  `settled?` changes. And it does not yet reach every walk the ticket's
  scope touches: `.fragments[kind]` reads (`self.parent.dependency ->
  comp.handle.fragments[pubapi]` and its siblings) name a fragment a
  *different* node writes (the `per(comp)` `comparch` node, via
  `produces:`, never `comp` itself), a provenance question `settled?`
  as stated here does not answer — moot for every such read in
  `bundles/default` today for an unrelated reason
  (`systems/generation.md`'s ORC-235 entry: every `.fragments[kind]`-
  typed walk in this bundle walks a `dependency`-typed edge, and no
  `dependency` instance in this bundle is extracted, because its
  `source` always names a join-target node type that never commits a
  `DraftCommitted` under its own name — a source-identity gate, not an
  edge-type one, but one that excludes this whole family regardless —
  so the walk resolves to `[]` and stays vacuously satisfied whatever
  `settled?` says). Closing that
  gap is generation's, not this entry's; a future pass reopening
  `.fragments[kind]` readiness once dependency extraction exists should
  extend `settled?` with a same-tier carve-out (a tier reading a
  fragment its own sibling instance writes — `comparch` reading another
  `comp`'s pubapi — stays ungated, preserving "a tier's own nodes fan
  out in parallel," the same allowance this entry's own scope note
  below states) rather than treat this as a fresh problem.

- **`all.<tier>` is satisfied only once `<tier>`'s own population is
  exhausted, not merely once every node that happens to exist already
  is approved** (ORC-235). `ContextResolver.resolve/2`'s `source: :all`
  clause is unchanged — it still returns every currently-`Store
  .list_nodes/2` node of `<tier>` — but `ReadyScopes` no longer folds
  that list alone with `Enum.all?/2`; empty is satisfied only when
  emptiness is known to be final, which `Enum.all?([], _)` cannot tell
  from "nothing has minted or drafted here yet." A tier's population is
  exhausted — call it `drained?/1`, the same naming register as
  `settled?/2` above — when no further node of that tier will ever
  appear *and* nothing that already exists is still pending. The
  recursion below folds over the same closed `scope:` vocabulary
  `candidates/3` already switches on, but its two recursive branches
  (`per(X)`, `child_of(X1..Xn)`) test that definition differently,
  because the two node kinds come into existence at different points.
  A `per(X)` node has no stored row until it drafts (`ReadyScopes`'s
  own moduledoc: a transient, never-persisted placeholder stands in
  until then), so the existing-row list at a `per(X)` tier is never
  trustworthy as a final population on its own — zero rows there means
  either "none will ever exist" or merely "hasn't drafted yet," and the
  only way to tell them apart is to check whether the driving tier `X`
  is itself exhausted first. A `child_of(X)` node's row appears at its
  parent's mint, not at its own draft, so once every minting parent
  `Xi` is exhausted the current row count at `<tier>` is already final
  and the recursion needs no further condition on those rows
  themselves — the asymmetry between the two branches below is this,
  not an inconsistency:

  - `singleton` with `generator: supplied` (`design_system` is
    `bundles/default`'s only instance today): drained unconditionally,
    from the moment the project exists — a supplied tier's population
    is fixed at intake, before the chain ever dispatches a single tier,
    so there is no "not yet" state between zero and its final count for
    this recursion to distinguish. A project supplying no document
    tagged `design_system` mints none (`design_system.yaml`'s own
    header — the same optionality every `input.<role>` carries), and
    that zero is final the instant the project exists, not
    provisional on anything the chain does later;
  - `singleton` with a `generator: llm` draft dispatched through the
    chain itself — exactly the tiers that are both `scope: singleton`
    and `generator: llm` (`feature_expansion`, `non_goals`,
    `frontend_sysarch`; `ref` is `scope: authored`, not `singleton`,
    below, so it is not in this bucket): `Sweeper.dispatchable?/1`
    matches each of the three on its `draft:`/`generator: "llm"` pair
    exactly like any other chain-dispatched tier, and the engine's
    `{:singleton}` scope holds exactly one row per project per tier
    (`candidates/3`'s `scope_key: %{}`, the `unique_index` on
    `(project_id, tier, scope_key)`): drained once its one node exists
    and is `settled?` — never vacuously, because such a tier's count is
    exactly one once the chain reaches it, never legitimately zero;
  - `authored` (`ref` is `bundles/default`'s only instance, `docs
    /dsl-syntax.md` §3.1, ORC-236): never drained. An indefinite,
    write-path-created pool cannot tell "no more will ever be authored"
    from "none exist yet" the way every branch above can — there is no
    upstream tier whose own exhaustion would settle the question, and
    no chain event marks the pool complete. Rather than leave that
    recursion hang the first time anything asks, `dsl-syntax.md` §13
    refuses two things at load time instead: an `all.<tier>` walk
    targeting an `authored`-scope tier, and a non-zero cardinality `min`
    on the side of an edge instance that names one (below) — nothing in
    `bundles/default` needs either (every `ref` read is a named
    `reference`/`fulfills` citation resolved by id, never a population
    walk, and every `→ ref` instance's cardinality is `{min: 0}` on both
    ends), so both refusals cost no shipped content and this branch of
    `drained?/1` is never actually called;
  - `per(X)`: drained once X is drained *and* every node `Store
    .list_nodes(X)` names (trustworthy as the final list only because X
    is already confirmed drained) has its corresponding `per(X)` node
    `settled?` — and a corresponding node with no stored row at all
    reads as not settled, the same "hasn't drafted yet" case the
    driving-tier check above exists to catch, not a gap the clause
    forgets to answer;
  - `child_of(X1..Xn)` (every tier a `type: fanout` edge instance
    targets — `chain.edges`, filtered to `type == "fanout"` and
    `instance.target == tier`, already gives the source set, a purely
    load-time-derivable list): drained once every `Xi` is drained
    *and* every row already at `<tier>` is `settled?` — a fanout mint
    runs exactly once, synchronously with its source's own
    `DraftCommitted` (regeneration is chosen, not triggered,
    `docs/v5-design-decisions.md`), so once every possible minting
    source has committed and been approved, no further instance of
    `<tier>` will ever appear and the current list is final, whatever
    its length. The second conjunct costs nothing at the ten
    `child_of` tiers that are join targets (`comp`, `subcomp`,
    `journey`, `screen`, `resp`, `policy`, `ui_coll`, `ui_subcomp`,
    `screen_coll`, `screen_subcomp`), whose rows are `:approved` from
    mint and whose `settled?` already defers to the very `Xi` this
    branch checks. It is load-bearing at the eleventh: `vocab` is the
    one `child_of` tier in `bundles/default` carrying a `draft:` of
    its own, so its rows mint `:absent` and stay pending until drafted
    and approved — without the conjunct, `drained?(vocab)` would read
    true the instant `feature_expansion` is approved and every vocab
    entry is still undrafted, which is "no further node will appear"
    without "nothing existing is still pending."

  This is what tells `all.vocab.handle` (`vocab` is `child_of
  (feature_expansion)`) that zero vocab entries is a legitimate,
  terminal answer once `feature_expansion` is `:approved`, apart from
  `all.journey.handle`/`all.screen.handle`/`all.sysarch.handle` in a
  fresh `frontend_sysarch` context, where `journeys`/`screens`/
  `sysarch` (respectively `per(feature_expansion)`/`per(feature_expansion)`
  /`per(requirements)`) have not drafted at all — `drained?` is `false`
  for all three, so `frontend_sysarch` no longer dispatches on the
  first sweep with an empty context, which was this ticket's own
  opening claim.

  **Termination is a property of `bundles/default`'s own scope graph
  today, not one the loader enforces.** `per(X)`/`child_of(X1..Xn)`
  references are declared over tier *names*, not edge instances:
  `Chain.build`'s acyclicity check (`lib/catapult/dsl/chain.ex`) walks
  `edges:` instances only, and `scope_problems/1` checks only that a
  scope names a tier the bundle actually declares — nothing at load
  time rejects a bundle declaring `A per(B)` and `B per(A)`, which
  would recurse `drained?` forever the first time either tier's
  readiness is asked for. `per(X)`/`child_of(X1..Xn)` are the only
  cases that recurse at all — every `singleton` tier is a base case
  for this recursion, whatever its own `drained?` branch decides. In
  `bundles/default` today the scope graph is finite because every
  `per(X)`/`child_of(X1..Xn)` chain eventually reaches one of the
  bundle's five `singleton` tiers (`design_system`, `feature_expansion`,
  `frontend_sysarch`, `non_goals`, `ref`), because the bundle's authors
  have kept the scope graph a DAG by convention — not because anything
  checks it. Closing that gap — extending `Chain.build`'s existing
  cycle detection to scope references alongside edge instances — is a
  `core_dsl` loader change, outside this ticket's own
  engine-and-generation scope; filed as a project finding, since
  `drained?`'s own correctness leans on a guarantee the loader does not
  yet supply.

  **Rejected: a declared tier sequence, as the ticket's own alternative
  invited.** A separate ordering declaration would still need this same
  recursion to answer "is the tier before me actually finished" — a
  sequence position alone cannot tell "zero nodes because none will
  ever mint" from "zero nodes because nothing upstream has drafted yet"
  any more than the unfixed fold could, since that is a fact about the
  scope/fanout graph, not about position in a list. A sequence would
  therefore buy no simplification over deriving order from the graph
  `context:`/`scope:` already declare, while adding a second,
  independently-authored representation of the same fact — exactly the
  drift a declared order and a declared graph disagreeing would invite,
  and exactly what `docs/dsl-syntax.md` §7/§7.2's "context is the only
  readiness signal" already commits this system to not needing.
  `ready_scopes` stays derived from one graph, not two.

  **What this ticket's fix reaches, and what it does not — stated once,
  plainly.** The Scope section above states
  the point of ordering `frontend_sysarch` after the backend as letting
  "the front-end family read real component APIs on its first pass
  rather than a shape it has to guess at." This fix delivers the
  ordering half — `frontend_sysarch` no longer dispatches before
  `sysarch` is approved — but not the reading-real-APIs half, for two
  reasons already on record separately and stated together here for
  the first time: `frontend_sysarch`'s new `all.comp.handle` and
  `ui_collarch`'s `self.parent.uses_shapes -> comp.handle
  .fragments[pubapi]` wait, via `settled?`, only on the `comp` node's
  own minting `sysarch` — never on `comparch`, the tier that actually
  writes the `pubapi` fragment `uses_shapes` reads (the `.fragments
  [kind]` provenance gap noted above, in this same entry); and
  `uses_shapes`/`calls` resolve to `[]` regardless once relocated,
  because relocating a `dependency` edge's declaration does not change
  whether its `source` tier can ever commit it (`systems/generation.md`'s
  ORC-235 entry) — **closed at ORC-236, below**: `source_ref:`/
  `target_ref:` extracts every `dependency` instance regardless of which
  tier `declared_in` names, `uses_shapes`/`calls` included, so this walk
  no longer resolves to `[]` for want of extraction. One gap stands
  between here and the ticket's own stated purpose now, not two — a
  same-tier `.fragments[kind]` provenance carve-out in `settled?`,
  unclosed by ORC-236 and not attempted there (its own scope is
  extraction and mint-time values, not readiness's mint-ancestry-vs-
  fragment-authorship distinction).

- **A minted node's `fields` are written at mint time, copied from the
  mint entry unchanged — the identical "copy, never derive" shape
  ORC-117 already established for `status`** (ORC-236, design pass).
  `apply_mint/2` already threads `mint.status` from
  `Extraction.mints/4`'s own entry onto `Store.mint_node/1` without the
  reducer deriving anything; the mint entry now also carries `fields:`
  — every `mint.<name>`/`mint.parent.<name>` value `Extraction.mints/4`
  resolved at the command edge (`docs/dsl-syntax.md` §3,
  `systems/core_dsl.md`'s ORC-236 entry) — and `apply_mint/2` copies it
  onto the same call, alongside `status`. No new reducer branch and no
  new purity-floor exposure: the values are already computed,
  purity-floor-clean, before the event is dispatched, the same
  guarantee `mint.status` already relies on.
- **`settled?/2`'s `generator: supplied` clause widens to
  `generator: authored`, unconditionally, for the identical reason**
  (ORC-236, design pass, extending ORC-235's own three-way match,
  above). A `supplied` node is settled the moment it exists because
  nothing upstream in the generation chain produced it and could still
  revise it; an `authored` node (`ref`, the tier `dsl-syntax.md` §3.1's
  new scope kind exists for) has the identical property for a different
  reason — its content is written once, by a write path outside the
  chain, with no draft anywhere in its history to be unapproved. Both
  clauses now read "settled unconditionally, the moment the node
  exists," keyed on the tier's own generator declaration rather than on
  `parent_node_id == nil`, unchanged from ORC-235's own reasoning for
  keeping the check declaration-keyed. This is what makes a
  `self.reference -> ref.handle` walk (`docs/dsl-syntax.md` §3.3's own
  worked example) resolvable at all: a `ref` node has no draft anywhere
  in its history, so there is no approval for `settled?` to wait on —
  it has to read the node's `generator: authored` declaration and say
  "settled" the moment the node exists, the same way it already reads
  `generator: supplied` for `design_system`.
- **Cardinality and instance-level `graph_constraint` are evaluated
  once the edge's own bound side is drained, never eagerly, and a
  violation is a reported, non-blocking finding — never a retried draft
  and never a blocking gate** (ORC-236, design pass). `dsl-syntax.md`
  §13's own opening line already places this at "projection time," not
  load time; what it left unstated is which moment of projection time,
  and the ticket's own warning is exactly the failure a naive answer
  ("check on every `DraftCommitted`") produces: `fulfills`'s
  `source: {min: 1}` ("every comp fulfills ≥1 resp") reads as violated
  on every comp that hasn't drafted its `fulfills` edge yet, which is
  every comp for some nonzero span of the chain's own run — a check
  that fires on every intermediate state is not a check, it is noise
  indistinguishable from a real defect. The fix reuses the mechanism
  this system already built to tell "not yet" from "never": a `{min,
  max}` bound on one side of an edge instance is evaluated only once
  that side's own tier is `drained?/1` (above) — the identical
  "has everything that could ever exist already committed and settled"
  question `all.<tier>` readiness already answers, asked here of a
  cardinality bound instead of a context walk. `max` bounds need no
  such gate (a count that has already exceeded a ceiling stays
  exceeded; checking early costs nothing) and are evaluated as soon as
  they can be violated, `min` bounds and `graph_constraint: acyclic`/
  `no_self_loop`/`tree` (both real properties of the whole instance
  graph, not of a single edge as it's written) wait on drainage the
  same way.

  **Why a reported finding rather than a blocking gate or a retried
  draft.** Grammar validation retries the agent that wrote the failing
  body — there is exactly one draft and one author to hand a typed
  error back to (`systems/generation.md`'s "validation failure is
  feedback, not error"). A cardinality or graph-constraint violation
  has neither: the defect is a property of the graph as a whole, most
  often spanning several already-committed, individually-valid drafts
  (a `{min: 1}` violated because a *different* tier's draft failed to
  reference this one, or never existed at all) — there is no single
  agent whose retry could fix it and no single draft to decline.
  Surfaced as a finding a human resolves, the same shape a policy
  enforcement gap already takes (`docs/v5-design-decisions.md` §4.5's
  "enforcement gaps are plane-filed tickets, instantly visible") rather
  than as a new blocking state this system's readiness graph would have
  to reason about. This system gains no new node status and no new gate
  for it — the finding's own surface (a ticket, a dashboard entry, or
  reuse of an existing structured-signal channel) is generation's/
  delivery's to build against this timing rule, not a new engine
  primitive.
- **A declared edge now resolves to the node it names, closing the
  chain this ticket's own audit found empty — from two independent
  directions, not one fix gating the other.** Every `<arch> → ref`
  citation was already extracted before this ticket (`systems/generation
  .md`'s ORC-235 entry: nine instances satisfy the source-identity gate
  today); what made every one of them resolve to nothing was `ref`'s own
  broken `scope_key` (above) — `ref`'s `scope: authored` correction
  alone is what makes `resolve_target/3`'s `Store.get_node_by_scope
  (project_id, target_tier, %{"id" => value})` lookup succeed for all
  nine, since a `ref` node's `scope_key` is now `%{"id" => <the id the
  write path assigned>}`, the exact shape a `<reference target="...">`
  citation already looks up, rather than the single flat `%{}` every
  node of a `scope: singleton` tier shares. Separately,
  `source_ref:`/`target_ref:` extraction
  (`systems/core_dsl.md`'s ORC-236 entry) makes the seventeen `dependency`
  and non-`ref` `reference`/`fulfills` instances extractable for the
  first time. Sixteen of their targets (`comp`, `resp`, `journey`,
  `screen`, `subcomp`, `ui_coll`, `ui_subcomp`, `screen_coll`,
  `screen_subcomp`) already carry a correctly id-shaped `scope_key` from
  their own ordinary fanout mint, so those sixteen resolve by the same
  `%{"id" => value}` lookup the moment they're extracted, with no
  dependency on the `ref` fix at all. The seventeenth, `ui_coll →
  design_system`, does not: `design_system` is `scope: singleton`, not
  fanout-minted, and its one node's `scope_key` is the flat `%{}` every
  `scope: singleton` tier shares — an id lookup against it can never
  match. That instance resolves through the `scope: singleton` endpoint
  locator instead (`docs/dsl-syntax.md` §4.2), which is what makes
  `resolve_target/3` gain a second clause: a `scope: singleton` target
  resolves by `Store.get_node_by_scope(project_id, target_tier, %{})`,
  no id involved, selected by the tier's own declared scope rather than
  by an attribute value. `Extraction.references/5` changes too, for the
  reason `systems/generation.md`'s own entry gives — it gains the
  `source_ref:`/`target_ref:` locator resolution itself, not only
  better-shaped inputs. `apply_declared_edge/2` alone is unchanged: it
  applies whichever edge list it is handed, and does no locating of its
  own either before this ticket or after.

- **A fanned-out child cannot leave its parent's workflow-axis
  sub-array, and this is a consequence of readiness already gating,
  not a new rule for this system to enforce** (ORC-115, design pass —
  stated as an invariant `docs/dsl-syntax.md` §15.10's sub-array
  grouping and ORC-116's own subflow-navigation design both lean on).
  `walk_ready?/2`'s own predicate — `Enum.all?(targets, &(&1.status ==
  :approved))` — already requires every node a context walk reaches to
  be `:approved` before the tier reading that walk can dispatch; §7
  states the same fact from the grammar side ("readiness requires all
  targets ready. Context is the only readiness signal"). So a tier
  positioned in a workflow sub-array *after* a gate can never become
  ready while the tier(s) the gate's own sub-array pins remain
  unapproved — not because anything checks the workflow-axis grouping
  against the chain-axis node, but because there is no path to
  `:approved` for the later tier that does not first satisfy the
  earlier one's own context walk. **What this is not:** a claim that
  this system reads or enforces sub-array membership at all — it
  doesn't, and gains no new code from this entry. The invariant is
  chain-axis readiness, restated for a workflow-axis reader (ORC-116's
  navigation) who needs to know a fanned-out node cannot be "ahead of"
  its own group's gate. If that reader ever needs something this
  system doesn't already expose — the sub-array a given node's tier
  belongs to, say — that is a new query, not evidence this invariant
  is wrong.

- **Sweeper cadence defaults to 30s, `tunable`** (v5 §7.10's bindings
  surface, same mechanism as every other marked threshold) — enough
  headroom that a burst of events doesn't turn the convergence floor
  into a second fast path, short enough that a lost PubSub message
  (process crash, netsplit) is invisible within one dispatch cycle in
  practice. **`staleClaimGrace` (§7.16's still-open item) is not this
  constant** — it measures ticket-claim staleness on the delivery/
  tracker side (`max(Run.EndedAt, StateSince)`), a different clock for
  a different job, noted so the two are not conflated by a later pass
  reaching for "the scheduler's timer" and finding two candidates.
  §7.16's item stands exactly as recorded; nothing here resolves it.
  **A tick walks its projects serially, not fanned out.** `Catapult
  .Repo`'s pool is a shared, finite budget, not this ticket's alone to
  spend — SETUP.md §2 sizes it against the projector's writes, Oban's
  workers as queues land, the health check, *and* this sweep together,
  on the one reference cluster this code deploys to, and owns that
  number alone (`docs/non-goals.md`: the instance's live facts have
  one home). `Task.async_stream`'s default width
  (`System.schedulers_online`) is the idiomatic move and the wrong one
  here: on a run of any real size it alone can reach for more
  connections than the pool holds, ahead of a request the pool exists
  to serve. One project at a time keeps a tick's own footprint at a
  single checked-out connection regardless of how many projects exist,
  which is affordable at 30s cadence because a readiness query is
  cheap and the floor's whole job is convergence, not speed. Revisit
  condition: a measured tick duration exceeding the cadence at real
  project counts — the fix then is a bounded width stated as a number
  here, never the default.
- **The sweeper is a distinct registered process and declares
  `:singleton` placement, the same kind `engine_projector` already
  uses** (v5 §2.5) — not, as first sketched, `:local`. The fast path
  is not a second process to place: "on each trigger the scheduler
  re-runs `ReadyScopes.ready/3` ... and broadcasts" (above) rides
  inside `Catapult.Engine.Projector.handle/2`, which already runs
  cluster-wide singleton by construction (a Commanded event handler
  subscription is consumed once, in order, or replay guarantees break)
  — so the fast path was never a placement question and this bullet is
  only ever about the timer loop. `:local` was argued on
  redundant-computation grounds alone (a stateless read costs cycles,
  not correctness, if every node repeats it) without pricing what
  "every node" costs against a pool sized in the single digits: a
  rolling deploy runs two full instances briefly, and `:local` turns
  one sweep into two, against the same budget the paragraph above
  already spends down to one connection per tick. `:singleton` removes
  the doubling by construction — one sweeper cluster-wide, like the
  projector beside it — rather than accepting it and arguing the size
  is fine; the two processes now share one placement rule for one
  reason (each must run exactly once, not once per node) instead of
  each defending a different number. Registered via `processes/0`
  like any other named process.
- **A node id is a per-project slug, not globally unique** (ORC-87).
  ORC-6 fixed the id column's *type* at `:string` rather than
  `:binary_id` deliberately, to leave the scheme open — but fixed the
  primary key to `id` alone in the same migration, which only one of
  the two legal schemes supports. This settles it the other way.
  `scope_key` and `handle` are already how a node is addressed
  *within* a project (`dsl-syntax.md` §3), and neither the command
  edge nor a bundle's own vocabulary promises more than that. A
  caller-supplied string unique across every project the plane will
  ever build is not a constraint anyone picks on purpose, and both
  alternatives are worse: reopen the UUID door ORC-6 deliberately shut
  for no gain the DSL asks for, or lean on bundle authors to
  hand-prefix every id with its project — a convention nothing
  enforces.

  **The evidence is that authors already do not follow it.** Test
  modules deadlocked on shared bare ids — `"sysarch"`, `"comp1"`,
  `"n1"` — before this pass, independently written and each reaching
  for the same plausible name, exactly as a bundle's own tier and
  scope vocabulary would. That is ordinary authoring rather than a
  test artifact, which is why per-module id prefixing was the wrong
  fix: it makes the suite pass without saying whether two real
  projects can collide the same way.

- **Every engine table keys by `(project_id, id)` — and so does every
  *secondary* unique index on it, which is the half that does not
  follow from the first.** A natural key like `engine_edges`'
  `(edge_name, source_node_id, target_node_id)` gains nothing from the
  primary key widening, and `Repo.insert!`'s `on_conflict: :nothing`
  names exactly one arbiter: a *different* unique index the same
  insert violates either raises, or drops the row as an apparent
  replay and leaves a graph silently missing an edge. The failure mode
  is silence by construction, so a new table in this store carries the
  obligation whether or not a test has tripped over it yet.
  `priv/repo/migrations/20260820000003_key_engine_store_by_project.exs`
  carries the per-table mechanics and that arbiter subtlety in full,
  at the point either would be edited.

- **Purity floors are absolute in this system**: no clocks,
  randomness, or generated ids in aggregate/reducer/projection code;
  inject at the command edge. Enforced by the substrate's call-graph
  audit check, which this system is the reason to build.
- **`ready_scopes` is the plane's dispatch source** (v5 §1.2's
  inversion) — the engine writes it; generation and delivery consume
  it; nothing else initiates work.
- **Events are versioned and upcast on read** (v5 §2.4): shapes are
  immutable contracts; changes are new versions with pure upcasters
  registered beside the reducer; the log is never rewritten; replay
  fixtures retain every historical shape. Built into the ES family
  from the first event, because retrofit means a broken replay.
- **Every atom an engine event carries needs a `JsonDecoder` on read,
  and the class is exactly four events today, not one** (ORC-226,
  design pass; the crash that found it: `Catapult.Engine.Projector`
  raising `Ecto.ChangeError` on `ReviewWritten.kind` and taking the
  reference instance down with it — a `Commanded.Event.Handler` with
  no `error/3` stops on the first bad event, permanently, since it
  re-reads the same event on every boot). `Catapult.Engine.EventStore`
  sets `Commanded.Serialization.JsonSerializer` deliberately (its own
  moduledoc: it round-trips atom-keyed struct fields, which the
  library's default serializer does not attempt); `deserialize/2`
  rebuilds the event via `struct/2` and then always runs
  `Commanded.Serialization.JsonDecoder.decode/1` on the result — the
  same mandatory second step `Catapult.Delivery.ContainerLifecycle`
  and `Catapult.Delivery.FeatureLifecycle` already implement for their
  own persisted state (ORC-120), and one this log had zero
  implementations of, for any event, before this pass. `struct/2`
  restores atom *keys*; it does nothing for a value that started life
  as an atom and travelled the wire as a JSON string, and no consumer
  downstream ever casts on read — every `Store` insert/upsert this
  system makes goes through `Ecto.Changeset.change/2`, which performs
  no casting, which is exactly why the defect surfaces as
  `Ecto.ChangeError` against an `Ecto.Enum` column rather than a
  silent coercion.

  **The class, checked against every event this doc's file map owns,
  not assumed from the one that fired:** four events carry a value the
  reducer passes unchanged into a `Store` call backed by an
  `Ecto.Enum` column — `ReviewWritten.kind` (`Store.Review.kind`),
  `ActiveBundleFlipped.axis` (`Store.ActiveBundleVersion.axis`),
  `FindingAdjudicated.disposition`
  (`Store.ContainerFinding.disposition`), and `DraftCommitted
  .mints[].status`/`.edge_type` and `.edges[].type` (`Store.Node
  .status`, `Store.Edge.type`), the last landing through `Reducer
  .apply_mint/2`'s and `.apply_declared_edge/2`'s own pass-through
  `status:`/`type:` assignments. Every other atom- or `DateTime`-typed
  field on an engine event either never reaches a `Store` call at all
  (`DraftCommitted.committed_at` is read off the event but never
  forwarded to `insert_draft/1`; `CommentPosted.posted_at` and
  `RunFailed.occurred_at` fold through `apply/2` clauses that write no
  projection row, by design, above) or is a plain string end to end
  (every `reason`, every `gate`, every `type_name`) — this is the
  whole set this pass found for atom- and `DateTime`-typed fields, not
  a sample of it. `keys: :atoms` also turns a map-valued field's own
  keys into atoms on the way back — `DraftCommitted.scope_key` and
  `.fields` both go in string-keyed and come back atom-keyed — but
  neither is atom- or `DateTime`-typed, so both sit outside the
  predicate above rather than inside a gap it missed. They are safe
  today for a reason worth keeping rather than assuming: every
  consumer re-encodes them straight to jsonb without ever comparing a
  key in memory — `Store.Node.scope_key` is a `:map` column, and both
  `mint_node/1`'s `conflict_target: [:project_id, :tier, :scope_key]`
  and `get_node_by_scope!/3`'s `Repo.get_by` compare the dumped jsonb,
  where the Elixir key type has already stopped existing. The day a
  map-valued field's keys are compared in memory rather than dumped
  whole, it joins this class and this predicate widens to say so.

  **`DraftCommitted` fails as `Ecto.ChangeError` one level in, not as
  `KeyError`, because `keys: :atoms` reifies nested keys as well as
  top-level ones:** `Commanded.Serialization.JsonSerializer.deserialize/2`
  only turns on `keys: :atoms` when its caller supplies a `type:`, and
  it is the caller, not this function, that "always" applies to —
  `EventStore.RecordedEvent.deserialize/2` calls it with
  `type: event_type` for event data and with no `type:` at all for
  metadata, which is also why metadata stays string-keyed on arrival
  while event data does not. Once `keys: :atoms` is on, it threads
  through every nested object Jason's own decoder parses, not only the
  struct's top level (confirmed by reproducing the exact round trip
  against `Catapult.Engine.Events.DraftCommitted`, not inferred from
  reading the library). A `mint`'s `node_id`/`tier`/`edge_name` keys arrive as
  atoms already; dot access on them does not raise `KeyError`. What
  survives the wire wrong is the same failure the other three events
  have, one level in: `mint.status`/`mint.edge_type` and `edge.type`
  are JSON strings, `Reducer.apply_mint/2`/`.apply_declared_edge/2`
  copy them unchanged into `Store.mint_node/1`/`.insert_edge/1`, and
  both land on an `Ecto.Enum` column through the same uncasted
  `Ecto.Changeset.change/2` — `Ecto.ChangeError`, not `KeyError`, and
  only once a committed draft's `mints`/`edges` are non-empty, which is
  why nothing has fired yet.

  **The fix is one shared helper, not four bespoke decoders, and it
  resolves each value against the legal set `Ecto.Enum.values/2`
  returns rather than against the runtime atom table — which an event
  module's own compiled form does not populate with its legal
  values.** `ContainerLifecycle`/`FeatureLifecycle` are each
  safe by the argument their own moduledocs give: the legal values are
  compile-time literals *in that module*, so they are in the atom
  table before any decode runs. An event module's `@type` spec is not
  that — typespec atoms never reach the runtime atom table — and
  loading only `Catapult.Engine.Events.ReviewWritten` and decoding
  confirms it: `"ai"` resolves, because it is also the struct's default
  value and so a real literal, while `"human"`, named only in the
  `@type`, raises `ArgumentError`. For `ActiveBundleFlipped` and
  `FindingAdjudicated`, measured the same way, every legal value is
  missing outright until something else happens to have already loaded
  their `Store.*` schema, whose `Ecto.Enum, values: [...]` list is the
  actual literal. For `DraftCommitted`, measured with only its own
  module loaded, three of its six legal values (`:absent`, `:approved`,
  `:reference`) resolved anyway, from atoms other already-loaded
  modules happened to carry, while the other three (`:fanout`,
  `:dependency`, `:policy_application`) still raised `ArgumentError` —
  and that partial result is the sharper evidence, not a softer one: a
  decode that fails every time is a loud bug any smoke test catches,
  while one that succeeds on some values and crashes on others
  depending on incidental load order is exactly the shape that passes
  every offline check and only fires in production on the first
  unlucky value. The failure mode either way is worse than the one
  this ticket opened against: decode runs before
  the reducer ever touches `Store`, so a poison value here raises
  inside `JsonDecoder.decode/1` itself — before `Projector`'s handler,
  and its `error/3`, are ever reached. `Catapult.Engine.Events
  .WireDecoding` (new, `lib/catapult/engine/events/wire_decoding.ex`)
  is what recovers the same safety property `ContainerLifecycle`'s
  idiom rests on, without keeping a second copy of any value set and,
  as the entry below states, without calling
  `String.to_existing_atom/1` on the wire value at all: each repaired
  field's legal atoms come from `Ecto.Enum.values/2` read against that
  field's own `Store` schema and column at decode time
  (`Ecto.Enum.values(Store.Review, :kind)`, and the same call shape for
  the other three), never from a list `WireDecoding` writes out itself.
  That call forces the same `Store.*` module load that puts the real
  literals in the atom table — the exact property `ContainerLifecycle`'s
  argument rests on — and it leaves no duplicate list for `Store`'s own
  enum to drift out of step with: the day a value is added to
  `Store.Review.kind`'s `Ecto.Enum, values: [...]`, `WireDecoding` sees
  it on the very next call, with nothing to edit and nothing that can
  fall out of sync. A single `defimpl Commanded.Serialization.JsonDecoder,
  for: [ReviewWritten, ActiveBundleFlipped, FindingAdjudicated,
  DraftCommitted]` block in the same file gives each struct its own
  `decode/1` clause built on this lookup, rather than four `defimpl`
  blocks scattered across the four event files each repeating the same
  three-line shape. This is a deliberate departure from where
  `ContainerLifecycle`/`FeatureLifecycle` keep theirs (in the struct's
  own file) — each of those is the only consumer of its own repair, and
  this one repair is six fields across five `Store` schemas, not four
  call sites: `ReviewWritten.kind` → `Store.Review`,
  `ActiveBundleFlipped.axis` → `Store.ActiveBundleVersion`,
  `FindingAdjudicated.disposition` → `Store.ContainerFinding`,
  `DraftCommitted.mints[].status` → `Store.Node`, and
  `DraftCommitted.mints[].edge_type` alongside `.edges[].type` — both
  → `Store.Edge`, because `Reducer.apply_mint/2` writes both `status:`
  and `type:` from a single mint and `.apply_declared_edge/2` writes
  `type:` again from a declared edge, so `Store.Edge` is read twice.
  Six is the count a shared file is sized against, and reading the
  column's own set rather than the event's `@type` is strictly
  stronger, not merely equivalent: `Store.Edge.type` declares five
  values (`:fanout`, `:reference`, `:dependency`,
  `:policy_application`, `:synthesis`) where `DraftCommitted`'s own
  `@type` names four, so sourcing from `Ecto.Enum.values/2` lets the
  decoder accept a value the column already considers legal even where
  the event's own typespec has not caught up with it.

  **An unrecognised value never raises inside `decode/1`, and the
  mechanism that guarantees it leaves no ordering hazard for a dev to
  get backwards.** `WireDecoding` does not call
  `String.to_existing_atom/1` on the wire string as an independent
  second step — it matches the wire string against the atoms
  `Ecto.Enum.values/2` already returned (comparing each to
  `Atom.to_string/1`) and substitutes the matching atom it already
  holds. There is no separate lookup that could run before the
  `values/2` call and reintroduce the `ArgumentError` measured above:
  the only atoms `decode/1` can ever produce are the ones `values/2`
  just handed back, already resolved, so there is no ordering for a
  later change to invert. When no match exists, `decode
  /1` leaves that field's value as the wire string, unchanged, rather
  than raising — the struct then reaches the `Store` call it always
  would have, meets the same uncasted `Ecto.Changeset.change/2` every
  field in this class already goes through, and fails as
  `Ecto.ChangeError` at the one site `Projector`'s `error/3` (`:stop`,
  below) already governs. That is deliberate, not a default left
  unchosen: this entry has already established that raising inside
  `decode/1` is the worse placement, landing before `Projector`'s
  handler and its `error/3` exist to see it, and an unrecognised value
  — a schema migrated ahead of this decoder, say — is exactly the case
  that placement would be worst for.

  **The comment that documented the serializer choice is the site that
  hid this defect, and dev amends it in the same change.**
  `lib/catapult/engine/event_store.ex`'s `init/1` carries: "it
  round-trips the versioned event structs this component emits,
  including their atom-keyed fields, which the library's own default
  `EventStore.JsonSerializer` does not attempt." That sentence is true
  and reads as covering atom-*valued* fields too, which it does not and
  never did — atom-keyed is exactly what `struct/2` restores, and
  atom-valued is exactly the gap the four decoders above close. Left
  as written, the next reader reaches this comment and draws the same
  conclusion the milestone's worth of code that shipped around it did.
  Dev states the distinction in that comment as part of this change,
  rather than leaving true words to keep implying the wrong thing.

  **`Projector` keeps Commanded's default `error/3` (`:stop`),
  unchanged — a decision, not an oversight.** A handler that skipped a
  bad event instead would leave this doc's own "rebuild-from-zero...
  must equal incremental state, always" quietly false for whatever
  that event should have folded — worse than the crash-loop this pass
  fixes, and this pass builds no mechanism yet (no alert, no
  parked-event queue, no replay-from-here tool) to make a skip visible
  rather than silent. The four decoders above remove the only known
  way to reach a poison event today; a *different* future defect
  reaching the same `:stop` is a real gap, but designing what a human
  does about a skipped event is its own ticket, not a side effect of
  this one.

  **The round-trip gap closes in the one test that reaches the real
  serializer.** `config/test.exs`'s
  `Commanded.EventStore.Adapters.InMemory` performs no serialization at
  all, so the default suite is structurally incapable of exercising
  any `JsonDecoder`, this class or the next one.
  `test/catapult/engine/event_store_test.exs` — the one test already
  reaching the real, Postgres-backed adapter — gains one case per event
  in the class above, each asserting the decoded struct's atom-typed
  field is an atom, not the string `Jason` would otherwise leave it as,
  plus one case, on any single field in the class, asserting that an
  unrecognised value comes back as the wire string unchanged rather
  than raising inside `decode/1` — the fallback stated above, exercised
  rather than only asserted in prose. `FlowCompleted`'s existing
  two-binary case stays: it proves the
  migration and the adapter wiring, which is a different and still-
  needed fact from the one the new cases prove. No case asserts that
  `WireDecoding`'s value sets agree with `Store`'s `Ecto.Enum`
  declarations, because there are no separate sets to agree — the
  `Ecto.Enum.values/2` lookup above reads `Store`'s own list directly,
  so there is nothing a test would be checking for drift.
- **The reducer resolves bundle semantics per event, from the log —
  never from whatever `core_dsl` currently has loaded.** The active
  bundle can flip mid-log, on either axis (v5 §6/§7.19;
  `core_dsl.md`'s cutover decision), and rebuild-from-zero must equal
  incremental state *always*, a flip included. A reducer that asks
  "what bundle is loaded right now" would apply today's semantics to
  yesterday's events on rebuild and diverge from what actually
  happened. So the flip events fold into their own small per-axis
  projection — current bundle version, and the sequence it became
  current, two rows per project — and the reducer consults that
  projection, in log order, exactly like every other event; it never
  reads `core_dsl`'s loaded state mid-fold. This is also the
  engine-side half of the join `core_dsl.md` already promises
  delivery's Phase 7 re-resolution (a blocked ticket's status history
  against the bundle-version timeline): the timeline is this
  projection, so delivery reads it rather than re-deriving one of its
  own. Built in from Phase 3 on the `events/0` precedent above: the
  discipline costs nothing before a cutover exists and is a broken
  replay to retrofit after one has landed. **A ninth projection, not
  a port** — the intro paragraph names eight; this one exists because
  the other eight can't be replayed correctly across a bundle flip
  without it, not because the ticket asked for it by name.
- **Staleness is a projection, never stored state** (v5 §7.11): a
  node is stale when its committed content predates the inputs its
  context walk reads — computed from the log on demand, consumed by
  flow walks and the plane's out-of-band ticket filing. No stale
  flag is ever written, and no pending work attaches to nodes;
  pending work is always a ticket.
- **A review tier needs no staleness treatment — but this does not
  close v5 §7.16's open item, which names a different object.** §7.16
  asks what a passed *workflow* gate pins ("Approval is a status, and
  review states are declared"); `dsl-syntax.md` §3.3 (ORC-84)'s
  `reviews: <tier>` is the chain axis, and §7.19 draws the line
  explicitly: a review tier is dispatched immediately after the
  generation tier it reviews, one cycle, and "has no throwback
  semantics: there is no passed gate downstream of it to reopen." A
  review tier also declares no `draft:` and no committed artifact, so
  there is nothing for §7.11's staleness derivation to anchor on even
  if it wanted to run. So a review tier is simply never consulted by
  the derivation, in either direction — not stale, not pinned, not
  reopened, and no "approved version" field is ever needed for one.
  §7.16's item stays open (restored at `v5-design-decisions.md`
  §7.16): a workflow gate is declared delivery-bundle vocabulary, not
  an engine node, so what it pins is delivery's to design when
  workflow gates land (`systems/delivery.md`'s Phase 7), over
  whatever this system's node/staleness projections already expose —
  not this ticket's to answer.
- **Snapshot cadence and stream partitioning carry the v4 defaults
  forward, unmoved.** Stream partitioning: one EventStore stream per
  project, the Commanded aggregate identity being the project id (v4
  §C.3) — already implied by "per-project aggregates" above, stated
  explicitly here because the ticket asked; both axes' events land in
  the same project stream; a project has one aggregate, not two.
  Snapshot cadence: every 10,000 events per project.
  Neither is built in Phase 3 (snapshots stay Target, below), but the
  value is decided now rather than left for whoever builds them —
  snapshots are disposable projections like any other (v5 §8's
  cold-storage rider agrees), so a wrong cadence costs a resweep, not
  a migration, and there is no reason to leave it unstated in the
  meantime. Revisit condition: measured per-project event volume
  disagreeing with v4's assumption enough to matter — nothing has run
  long enough yet to measure it.

- **Container and workflow-axis lifecycle events land on the same
  single per-project aggregate, not a second one** (ORC-104, design
  pass; `docs/dsl-syntax.md` §15.6-§15.8, `docs/v5-design-decisions.md`
  §7.8, settling what `systems/delivery.md`'s three ORC-105 entries
  left as "not yet built... this system owns"). A container instance's
  mint, its activation, each move of its current queue — forward past
  a resolved gate, or backward on a step's own outcome (a decline, from
  a `critique` entry's own agent run, landing on the generation entry
  it pairs with, or from a human at a gate, landing per its
  `throwback:` — one mechanism per §7.19, not two) or an explicit
  author transition, never on a queue's population refilling (§15.8,
  corrected at ORC-148's third design review and again at its fourth)
  — a carried finding's filing or decline, and a milestone's flag-set
  flip are none of them derivable
  from anything already in the log: nobody else records "this
  milestone instance now exists" the way nobody else records "this
  draft was approved." They are original protocol facts, the identical
  shape `OpenFlow`/`CommitDraft`/`ApproveDraft` already are, and "a
  project has one aggregate, not two" (above) already answers where
  they land — `Catapult.Engine.Aggregate`, dispatched through the same
  `Catapult.Engine.Router`, in the same per-project stream every
  chain-axis event already writes to. New command/event modules join
  the existing set under this doc's own file map
  (`lib/catapult/engine/commands/**`, `lib/catapult/engine/events/**`),
  not a parallel set delivery owns: a second Commanded aggregate
  identified by `project_id` would be the second aggregate this doc
  already refuses, and command modules living under delivery's own map
  while dispatched through this system's router would point the
  dependency the wrong way — `systems/delivery.md`'s own "Depends on"
  already runs delivery → engine, never the reverse. Command
  validation — a queue-advance naming a declared anchor, a `blocks:`
  relation (`singleton:`'s own lifetime bound retired at ORC-148,
  `systems/core_dsl.md`, rather than becoming a fourth check here) —
  reads the loaded
  `Catapult.Dsl.Workflow.t()` the identical way the reducer already
  resolves bundle semantics from the log rather than from whatever
  `core_dsl` currently has loaded (above); this system already depends
  on core_dsl for exactly this, so no new dependency edge is needed.

  **This is the first command edge into this aggregate that isn't this
  system's own.** Deciding *when* a queue has emptied or a `blocks:`
  sibling has cleared, and issuing the command, is
  `systems/delivery.md`'s new queue dispatcher; this system only
  validates and records what it's told, exactly as "engine is state of
  record, delivery is the protocol interpreting it" already reads in
  that doc. The split is not new in kind, only new in direction — every
  writer into this aggregate so far has been this system's own command
  edge, not another system's process manager. It does not reopen "the
  scheduler dispatches to no component by name," several bullets up:
  that invariant is scoped to the chain-axis generation signal
  (`ready_scopes`) specifically, and stands exactly as written — a
  queue's resolved `flow:` that turns out to open ordinary ticket work
  still dispatches through the existing `OpenFlow` path, driven by
  nothing but `ready_scopes`, unchanged.

- **Membership is derived by reference, never a stored list — the
  queue-as-query principle applied one level up** (ORC-104, design
  pass; ORC-105's grammar, `dsl-syntax.md` §15.6-§15.7,
  `docs/v5-design-decisions.md` §7.8's "containers and projects alike
  keep references to their work items even once archived"). A
  container's access path to its own work is answerable from each work
  item's own `container_id` — set once, at open, the same way
  `project_id` already is — filtered to this container instance, with
  no resolution predicate to make it look like a queue's population
  query. Archiving a work item is policy, decided at
  `systems/delivery.md`, and never touches this column, so the
  reference survives archival for free: no membership list to keep in
  sync, and nothing here reopens `ready_scopes`'s own "never
  materialized" reasoning by writing a bucket for a different query
  that reasoning already refused a bucket for. A new projection reads
  current queue position per container instance in the same shape the
  ninth projection already gives current bundle version — one row per
  instance, current queue and the sequence it became current — since
  "which instance is minted vs. which is active" (`dsl-syntax.md`
  §15.8) is exactly that same two-fact shape, mint recorded once and
  activation a later, separate write to the same row.

  **The dev pass found membership needed a version bump, not a new
  table, and that is worth recording where the upcasting discipline
  is.** `container_id` and `queue` are set once, at open — which means
  they are fields on the event that opens a work item, so
  `Catapult.Engine.Events.FlowOpened` is version 2 and
  `FlowOpenedV1` joins `ReviewWrittenV1` as a frozen historical shape
  with an upcaster (v5 §2.4). The upcast fills both with `nil` rather
  than backfilling a guess: a version-1 event was written before
  containers existed, so the work item it opened was genuinely a member
  of nothing, and a guessed container would have made an unowned work
  item silently count into some queue's population — the one failure
  the queue-as-query has no way to notice.

- **`CommentPosted` (v1, explicit) is a new `events/0` entry, and a
  human review comment is an original protocol fact on this same
  aggregate, not a second one** (ORC-34, design pass, revised on
  design review — the FeedbackBucket cache the first draft proposed is
  gone; see the correction below for why). It joins
  `DraftApproved`/`FindingAdjudicated` on the identical ground "a
  project has one aggregate, not two" already gives: nobody else in
  the log records that a human left this comment on this node's
  `body_sha`, so it cannot be derived, and it lands through the
  existing `Catapult.Engine.Router` in the same per-project stream.
  `Catapult.Engine.Commands.PostComment` carries `project_id`,
  `node_id`, `body_sha`, `locator` (nullable — see below), `author_id`,
  `body`, `posted_at` (supplied by the caller, per this system's own
  purity floor — never generated in the aggregate); `CommentPosted`
  mirrors it. Validation rejects a `body_sha` that doesn't match the
  node's currently committed draft, the same stale-view rejection
  every other command on a surface we own already gives (`systems
  /delivery.md`'s point-of-action rule) — a comment posted against a
  view the author hadn't refreshed fails here rather than silently
  attaching to the wrong version. **No `kind`/`author_kind` field:**
  nothing in Phase 4 posts a machine comment through this event — the
  chain's own auto-review is `ReviewWritten`, a distinct record with
  its own `kind: :ai | :human` — so `CommentPosted` is human-authored
  by construction and stays that way until something actually needs to
  post through it, the same "don't validate a scenario that can't
  happen" discipline this codebase already keeps elsewhere. This is
  what ORC-31's author-identity filter exists to reconstruct on a
  surface we don't own; on a surface we do, the identical outcome
  falls out of never having built a channel two kinds of author could
  write through in the first place. **Two reviewers commenting
  concurrently need no new mechanism**: this command carries no
  `expected_version` invariant of its own to protect (it appends a
  fact, it doesn't compare-and-swap a mutable one), so the ordinary
  case is Commanded's own optimistic-concurrency retry on the
  aggregate stream — the identical primitive §7.16 already names for
  human-vs-human races generally, not a second one built for comments.
  **The sentence locator is nullable, and is always null in Phase 4**:
  `docs/ui-spec.md` §5 stages per-sentence anchoring in `document
  -review` at v2; v1 (Phase 4's own) has no diff producing one yet.
  Nothing below reads `locator` to decide what to fold in, only to
  decide how to render an entry once folded — so v5 §7.4's per-span
  bucket key degenerates to per-node today (there is exactly one
  committed body per node to comment on) and activates for free,
  unchanged, the day v2's anchoring ships a real one.

- **Harvesting is a query against this log, not a second table — the
  identical shape `Catapult.Engine.Projections.RunFailures` already
  established for a different derived fact, corrected onto here after
  design review found the first draft's cache reopened the exact
  silent-failure risk it claimed to close** (ORC-34, design pass,
  design-review correction). The reopened risk, named precisely: a
  cache table is written asynchronously by whatever process reacts to
  a decline, while the *sweeper* that would dispatch a regeneration is
  timer-driven and reads readiness from projections the same reducer
  updates independently (`Catapult.Generation.Sweeper`) — nothing
  orders the two, so a sweep tick landing between "the gate declined"
  and "the cache row landed" dispatches with a blank `feedback`,
  indistinguishable from a genuine zero-comment case at render time.
  That is exactly the ambiguity this ticket's own record says must be
  resolved before dispatch, and a cache cannot resolve it — only
  removing the asynchronous write can. `Catapult.Engine.Projections
  .CommentFeedback.since_last_resolution(project_id, node_id)` reads
  `Commanded.EventStore.stream_forward/2` directly, the same call
  `RunFailures.count_since_commit/2` already makes, and is a
  synchronous read of the log itself, not a projection anything writes
  ahead of time — so there is no ordering gap for a sweep tick to land
  in, whatever the reset boundary turns out to be.

  **The reset boundary is not `DraftCommitted`, on a second design-
  review finding this pass corrects: that boundary and
  `GateComments.any_since_last_resolution?/2`'s boundary, below, are
  different queries that can each pass while the other sees something
  different, which reopens the same blank-vs-zero ambiguity one level
  in** (ORC-34, design pass, second design-review correction). A
  concrete case second review gave: `GateDeclined` at T1 resets
  validation's window; a comment lands at T2, mid-regeneration;
  `DraftCommitted` at T3 reset *this* projection's window on the old
  design, discarding T2 before it ever rendered; `GateDeclined` again
  at T4 passes validation (T2 postdates T1) and dispatches a
  regeneration whose `feedback` folds since T3 and sees nothing —
  burning the exact dispatch this ticket exists to prevent, and losing
  T2 outright in the process, since no later window ever folds back
  across T3 to find it. `DraftCommitted` plays no role in either fold
  from this point on: a comment posted while a regeneration is in
  flight is not discarded by that regeneration's own commit.

  **The fix the second pass built on top of that — "the resolution
  before the most recent one," unfiltered by gate — inferred the
  boundary from *position* in the global resolution sequence, and a
  third design-review finding shows that inference wrong the moment a
  workflow declares more than one gate, which `bundles/default-flow
  /types/feature.yaml` already does** (ORC-34, design pass, third
  design-review correction). The second pass's own argument for
  ignoring `gate` was "Phase 4's own single-gate `feature.yaml` makes
  it a difference with no effect... with exactly one gate declared,
  every `GateApproved`/`GateDeclined` in the project necessarily names
  it" — the shipped bundle declares two, `ux-review` then
  `engineering-review`, run in sequence over the same single
  pre-gate `generation` status, and `engineering-review`'s own
  `throwback: [generation, ux-review]` makes a decline-to-`ux-review`-
  then-decline-again-at-`engineering-review` path ordinary rather than
  contrived. Third review's case: `GateDeclined` on `engineering-review`
  at T1 resets *validation's* window for that gate; a comment lands at
  T2; `GateApproved` on `ux-review` at T3 is a resolution too, but not
  one naming `engineering-review`; `GateDeclined` on `engineering-review`
  again at T4 passes validation (the last resolution *naming*
  `engineering-review` is T1, and T2 postdates it) — but "the resolution
  before the most recent one," unfiltered, is T3, so the render folds
  since T3 and misses T2. Same blank-vs-real-zero ambiguity the ticket
  exists to close, one gate count higher than the second pass checked.

  **The fix stops inferring the boundary from position and has the
  validated boundary ride on the event that used it, so the two windows
  are the same window by identity rather than by an argument that has
  to stay true across every gate count — and a fourth design-review
  finding fixes *where* that computation happens, since the first
  version of this fix read the store from inside `execute/2`**
  (ORC-34, design pass, fourth design-review correction).
  `Catapult.Engine.Aggregate`'s own moduledoc states the constraint the
  first version broke: "`execute/2` and `apply/2` read only their own
  arguments; every id, timestamp and sequence number a resulting event
  carries is already present on the command" — checked by
  `Catapult.Engine.Policies.PurityFloor`. Calling
  `Catapult.Engine.Projections.GateComments.last_resolution_sequence/2`
  from inside `execute/2` breaks both halves at once: it is a
  `Commanded.EventStore.stream_forward/2` read, not a read of
  `execute/2`'s own state-and-command arguments, and `since_sequence`
  is exactly "a sequence number a resulting event carries" that arrived
  by being computed there rather than by already being on the command.
  The corrected split is this system's own standing purity rule,
  above — "no clocks, randomness, or generated ids in
  aggregate/reducer/projection code; inject at the command edge" —
  applied to a third kind of value that rule always implied but this
  ticket is the first to need: a **log position** is injected the
  same way a clock or an id is, not derived
  inside the aggregate. `Catapult.Engine.Projections.GateComments
  .last_resolution_sequence(project_id, gate)` keeps the definition the
  third pass gave it — the log position of the most recent
  `GateApproved`/`GateDeclined` naming `gate`, or `nil` if neither has
  happened yet (so `since_sequence` on a gate's first-ever `GateDeclined`
  is `nil`, and `CommentFeedback` folds from the start of the log, the
  same as its own "no resolution has happened yet" case below) — only
  its caller moves, from inside `execute/2` to wherever `DeclineGate` is
  built.

  - **Validation moves onto the aggregate's own state — no store read,
    because none is needed.** The aggregate already keeps the "minimal
    state needed to reject a malformed sequence" for containers and
    nodes (its own moduledoc); it gains the same shape for gates: a
    project-wide comment counter, bumped by one on every `CommentPosted`
    it applies, and a per-gate mark of that counter's value as of each
    gate's last `GateApproved`/`GateDeclined`, recorded when `apply/2`
    folds that event. `DeclineGate`'s `execute/2` rejects unless the
    current counter is past the mark recorded for `cmd.gate` — the
    identical predicate the retired `any_since_last_resolution?/2`
    computed by reading the log, now answered by reading `state`, one
    of `execute/2`'s own two arguments. `GateComments
    .any_since_last_resolution?/2` is retired outright: its only caller
    was `execute/2`, and leaving it standing beside the aggregate's own
    copy of the same fact is the exact two-windows-that-can-disagree
    shape the second and third design reviews spent two passes
    closing — one predicate, and the aggregate is now where it lives.
  - **`since_sequence` moves onto the command.** `Commands.DeclineGate`
    gains a `since_sequence` field, computed by whatever constructs the
    command — the same command-edge boundary `posted_at` already
    crosses on `PostComment`, for the identical reason: an aggregate
    that computed it would be reading the store, and one that derived
    it from its own local counter would still be manufacturing an event
    field the moduledoc requires already be present on the command. The
    caller reads `GateComments.last_resolution_sequence(project_id,
    gate)` — a plain query, fine outside the aggregate — before
    dispatch; `execute/2` copies `cmd.since_sequence` onto the emitted
    `GateDeclined` unchanged, the same copy `CommentPosted` already
    makes of `posted_at`.
  - **A caller-supplied boundary that has gone slightly stale is safe
    in the one direction that matters.** If a comment lands between the
    caller's read and the aggregate processing the command,
    `since_sequence` undercounts how recent the true boundary is — but
    undercounting only makes `CommentFeedback` fold from *earlier*,
    including comments already answered, never *later*, so the failure
    mode is extra context, not a blank render. A stale command racing
    an actual resolution of the *same* gate is the one case that could
    go the other way, and it already can't reach the aggregate:
    `DeclineGate`'s `expected_version` (§7.16's optimistic concurrency,
    unchanged) rejects it outright, and the ordinary retry re-reads
    `GateComments.last_resolution_sequence/2` before trying again — the
    identical mechanism this doc already names for two humans commenting
    concurrently.

  `CommentFeedback.since_last_resolution(project_id, node_id)` is
  unchanged by any of this: it still reads the most recent
  `GateApproved`/`GateDeclined` event in the project's log, unfiltered
  by which gate it names — Phase 4's single pre-gate `generation`
  status is what makes "whichever gate" safe here, the reasoning the
  second pass actually needed and mislabeled as being about gate
  *count* — and if that event is a `GateDeclined`, folds every
  `CommentPosted` for `node_id` seen after its stamped `since_sequence`;
  if it is a `GateApproved`, or no resolution has happened yet,
  `feedback` is empty. Walked through the third review's own case:
  `GateDeclined@T4` carries `since_sequence: T1` — read off the command
  that produced it, not re-derived — so the render folds since T1 and
  sees T2, the comment that actually justified the decline, regardless
  of `GateApproved@T3` sitting between them in the log. "Consumed"
  still means "rendered into every regeneration dispatched before the
  next resolution naming this gate, and gone the moment that resolution
  lands" — not "discarded by an unrelated draft commit," and not
  "discarded by an unrelated gate's own approval" either.

  **This closes a second failure the position-based inference had, named
  by third review but not exercised by its main counter-example: a
  passed gate's already-answered feedback being re-litigated by an
  unrelated later re-dispatch** (staleness, a `RunFailed` retry). Under
  "the resolution before the most recent one," a re-dispatch happening
  after a `GateApproved` still folds from whatever position-based
  boundary that inference produced, which can resurrect comments the
  gate that approved already read. Under the fix, the most recent
  resolution being a `GateApproved` renders `feedback` empty outright —
  nothing is outstanding once a gate has passed, independent of what
  triggered the re-dispatch.

  **`since_sequence` is a log position, not a content claim, and does
  not reopen §7.16's "what a passed gate pins"** — the same distinction
  the sign-off entry below already draws for why neither gate event
  carries a `body_sha`. It says only "here is where `CommentFeedback`
  should start folding," never anything about what the gate approved or
  whether downstream content still matches it.

  Delivery reads this the same way it already reads `engine_flows` and
  the ninth projection — through a query, never a second copy of the
  log's own facts — which is what the pre-review draft's own text
  claimed while contradicting it with a cache in the same commit;
  there is now exactly one description of this mechanism, here, and
  `systems/delivery.md`'s entry points at it rather than restating it.

- **A workflow gate's sign-off is two new commands landing on this
  aggregate, closing the mechanism `systems/delivery.md`'s ORC-32
  entry left as "a later increment"** (ORC-34, design pass, scope
  correction: the ticket's own write path, deferred once to Phase 7,
  turns out to be this ticket's because `docs/ui-spec.md` §2 rule 2
  refuses a screen — `document-review`, ORC-75 — inventing protocol
  vocabulary the platform doesn't have yet, and neither `PostComment`
  nor a decline command exists before this pass). `Catapult.Engine
  .Commands.ApproveGate{project_id, flow_id, gate, actor_id}` →
  `GateApproved`, and `Commands.DeclineGate{project_id, flow_id, gate,
  throwback_to, since_sequence, actor_id}` → `GateDeclined`, both v1,
  `since_sequence` caller-supplied per the fourth design-review
  correction above, both keyed by the
  `(project_id, flow_id)` composite `systems/delivery.md`'s own ORC-32
  entry already establishes for this aggregate's process-manager
  consumer (ORC-87). **`gate`/`throwback_to` legality — is `gate` a
  key of `workflow.gates`, is `throwback_to` earlier in the citing
  type's own effective sequence (the "earlier in the array" test
  `Catapult.Dsl.Workflow`'s own `gate_throwback_problems/2` already
  runs at load time for a *declared* `throwback:` value, reused here
  at the command edge as a runtime check now that ORC-115 retires the
  declared list as a legality bound, `docs/dsl-syntax.md` §15.10,
  second design review — the field itself survives narrowed to a
  single-target override on the derived default rather than retiring,
  `docs/dsl-syntax.md` §15.4, third design review) — is the command
  edge's to check, not `execute/2`'s** (dev
  pass correction): the container commands this
  entry pointed to as precedent validate bundle content at their own
  dispatcher, `Catapult.Delivery.ContainerLifecycle`, and reject in
  `execute/2` only against the aggregate's own pure state — this
  aggregate's own moduledoc states that split ("never against bundle
  content, which the command edge already validated before dispatch")
  and `execute/2` loading a workflow bundle to check it directly would
  be exactly the impure read the fourth design-review correction above
  already retired for `since_sequence`, on the identical file this
  entry itself is recorded in. Whatever constructs `ApproveGate`/
  `DeclineGate` — ORC-75's screen, when it lands — validates `gate` and
  `throwback_to` the same way `ContainerLifecycle` validates
  `MintContainer`/`AdvanceContainerQueue`, before dispatch. **A decline
  requires at least one comment; there is no free-text override.** `docs/ui-spec.md` §3.2's own `document
  -review` action set is "approve / throw back," target chosen from
  the gate's own declared `throwback:` when it names one, its derived
  default otherwise, or the earlier-prefix picker for anything else
  (ORC-115, second design review corrects this from "the declared
  exits" as the bound on legality; third design review restores the
  field itself as a single-target override rather than retiring it,
  `docs/dsl-syntax.md` §15.4) — no reason field — so the
  simpler of the two fixes design review posed for the ticket's own
  zero-comment open question is also the one the screen this ticket
  answers to actually specs: `DeclineGate` is rejected outright,
  synchronously, at the point of action, when the aggregate's own
  comment counter has not advanced past the mark it recorded for
  `gate` at that gate's last resolution — pure aggregate state, no
  store read; the harvesting entry above (fourth design-review
  correction) has the mechanism and the reason it moved off
  `GateComments.any_since_last_resolution?/2`, a store read `execute/2`
  may no longer make. `since_sequence` on the emitted `GateDeclined` is
  `cmd.since_sequence`, copied rather than computed, for the identical
  reason — the caller populates it from `GateComments
  .last_resolution_sequence(project_id, gate)` before dispatch, and the
  same correction covers why that stays safe even when the read has
  gone slightly stale by the time the aggregate processes the command.
  **Project-
  wide, not flow-scoped, on purpose**: `CommentPosted` carries no
  `flow_id`, and `systems/delivery.md`'s own `FeaturePublisher` entry
  already leans on "nothing yet opens two flows concurrently on one
  project" to resolve a flow from a bare `project_id`; this reuses that
  exact standing simplification rather than inventing a second one, and
  carries the identical Phase 7 revisit condition — multiple concurrent
  flows per project need `CommentPosted` to carry `flow_id` too, not a
  new check here. **This is a rejection the aggregate makes, not the
  view**: `docs/ui-spec.md` §2 rule 1 and this doc's own "the rejection
  lands at the point of action" already rule out a UI-side check as the
  arbiter for any command on a surface we own; a decline attempt with
  no comments yet is simply invalid input to `DeclineGate`; the screen
  a future ticket builds surfaces that rejection synchronously, the
  same as any other compare-and-swap failure, but does not perform it.
  **What this does not pin: §7.16's "what a passed gate pins" stays
  exactly as open as it already was.** Neither event carries a
  `body_sha` or any other content-identity field — they record only
  enough for a ticket's projected status to move, forward or to a named
  throwback target, for the comment-count check above to run, and (
  `GateDeclined` only) the log position that check ran against —
  `since_sequence`, above, a position in the log, not a claim about
  content — so they are not a second attempt at the staleness-of-a-passed-gate question
  `systems/delivery.md`'s ORC-32 entry and this section's own §7.16
  bullet already leave to Phase 7. Which node(s) a given gate reviews —
  the general question behind "does what this gate approved still
  match what's downstream of it" — is likewise untouched; Phase 4's own
  shipped `feature.yaml` runs exactly one `generation` status ahead of
  its gates, so nothing here needs the general answer to work today.
  **Design-resolved at ORC-115, still not built here or anywhere:**
  `docs/dsl-syntax.md` §15.10's sub-array grammar now gives "which
  node(s) a gate reviews" a structural answer — the citing sub-array's
  own one non-review-shaped agent-balled entry, at the gate's declared
  `depth:` (`docs/v5-design-decisions.md` §7.16) — but neither event
  gains a field from that alone; the join still has to be built
  (Phase 7), and this entry's own claim (no `body_sha`, position not
  content) is unaffected until it is.
  **Named rather than left to be found by a fan-out: the decline check
  is project-wide and the render is per-node, and those are not the
  same scope** (fourth design-review's own minor finding). A comment
  on one node is enough to pass `DeclineGate`'s project-wide count, and
  the regeneration it triggers can cover several nodes; `CommentFeedback`
  still renders exactly what landed on each node's own log, so a
  sibling the comment never named regenerates with blank `feedback` —
  correct per-node, not blank-vs-real-zero ambiguous, but not
  "justified by a comment" either. That gap is the same node(s)-per-gate
  mapping this entry already defers, not a new one; it is named here so
  the deferral reads as a stated gap rather than an implied guarantee.
  Role authorization (does this `actor_id` hold `gate.role`) is left
  exactly where §7.16 already leaves grant evaluation — identity's, a
  Phase 7 component — recorded the same way `actor_id` rides
  unvalidated on `DraftApproved` today. **How a decline reopens a node
  for regeneration is closed at ORC-229 (below), off this same event.**
  `GateDeclined` moves the ticket's own projected status
  (`systems/delivery.md`, below) and, independently,
  `Catapult.Delivery.DraftResolution` dispatches `DiscardDraft` against
  the node this gate reviews; `Reducer.apply(%DraftDiscarded{}, _)`
  resets that node's projection to `status: :absent` with
  `current_draft_id`/`body_sha` cleared, so `ReadyScopes.ready/3`'s own
  `node.status == :absent` filter — unchanged — is what makes it
  eligible for `ready_scopes` again. This entry still only guarantees
  that whenever ORC-9's executor does re-dispatch, `feedback` cannot
  render blank where a real comment justified the decline:
  `since_sequence` on
  `GateDeclined` is read from `GateComments.last_resolution_sequence/2`
  at the same command-construction boundary that populates the decline
  (the fourth design-review correction above has the mechanism, and why
  a stale read there is safe in the direction that matters), and
  `CommentFeedback` (above) reads that stamped number back rather than
  re-deriving one from the log's shape — independent of what triggers
  the re-dispatch, how long the sweeper takes to notice, or how many
  gates the workflow declares.

- **`prior_review` needs a new `Store.reviews_for_node/2`, project-
  scoped per ORC-87 from the start — not the existing `reviews_for_draft
  /1` the pre-review draft leaned on, which answers a different
  question and stays exactly as bare-id as it already was, a real gap
  ORC-87's own audit missed** (ORC-34, design pass, design-review
  finding; the "audit's first pass missed it" pattern this doc's own
  ORC-87 entry already used once for `engine_drafts`' second key,
  applied here to a call site rather than an index).
  `reviews_for_draft(draft_id)` stays, bare id and all, because the
  review-tier dispatch rule above needs exactly what it already
  answers — does *this* draft have a review yet — and threading
  `project_id` through it is real but separate cleanup this ticket
  notes without taking (dev's, the same way every other decision in
  this doc is). What `prior_review` needs is a different query
  `reviews_for_draft/1` cannot answer, which is the ticket's own "the
  same slot doing different jobs" question the pre-review draft pinned
  without noticing it left one of the two jobs blank: reading by
  `draft_id` returns nothing until *this* draft has been reviewed,
  which is always true for a freshly regenerated draft and for the
  review tier about to review it for the first time — exactly the case
  where "what I said last time" is the whole point. `Store
  .reviews_for_node(project_id, node_id)` joins `engine_reviews` to
  `engine_drafts` on `project_id` **and** `draft_id`/`id` together —
  carrying `project_id` on both sides of the join predicate itself,
  not just in the function's own arguments, which is the exact spot
  the ORC-87 gap named above is actually won or lost — filters
  `engine_drafts.node_id`, and orders by `inserted_at` descending,
  project-scoped from the moment it's written rather than retrofitted.
  Both the
  regenerating generation tier and the review tier re-run after it read
  the same most-recent row — the node's last review, whichever draft it
  landed against — which is never empty once the node has been reviewed
  once, on either caller. A node never yet reviewed still renders
  `prior_review` blank via Solid's own unset-is-empty behavior,
  unchanged. **The row carries `body_sha`** (`Store.Review` already has
  the field — `write_review`/`ReviewWritten` set it from the draft they
  reviewed) **and `reviews_for_node/2` renders it**, so a prompt reading
  `prior_review` can tell whether the review it sees applies to the
  node's current committed body or a superseded one; without it,
  nothing distinguished "what I said about the body you're now
  regenerating from" from "what I said about a body two commits ago,"
  which the deliberate cross-draft read above makes possible for the
  first time (`feedback`'s own entries carry the same kind of
  provenance — `posted_at` against the log's own ordering).

- **`ApproveGate`/`DeclineGate` carried no compare-and-swap, which is a
  defect against §7.16's own rule, not an open question — found reading
  the code against the rule, not filed as a finding by either of the
  two tickets that already dispatch these commands** (ORC-114, design
  pass, revised on design review — the first draft's single compare
  turned out to guard only one of two distinct staleness questions; see
  below for the second). `ApproveGate`'s `execute/2` clause bound no aggregate state at
  all (`def execute(%__MODULE__{}, %ApproveGate{} = cmd)`) and emitted
  `GateApproved` unconditionally; `DeclineGate`'s only check was the
  comment-count mark above, which guards a different fact (has anyone
  commented since the last resolution) and has never guarded staleness
  of the resolution itself. Two role-holders racing to resolve the same
  gate — both looking at the same pending action, both dispatching
  around the same moment — land both writes today; the second is never
  told. `docs/ui-spec.md` §3.1 already promises otherwise for both
  screens that dispatch these commands: `ticket`'s "optimistic-
  concurrency feedback: a rejected transition names who moved it and
  where (§7.16)" and `board`'s "the controls are the same two
  transitions the ticket screen offers, under the same compare-and-
  swap (§7.16), so a stale card fails the same way and says who moved
  it" — sentences already committed against behavior the aggregate does
  not have.

  **The shape to copy is already in this file.** `AdvanceContainerQueue`
  matches `%{state: :active, queue: current} when current == cmd.from_queue`
  and carries `from_queue` on the command for the identical reason
  §7.16 gives: first writer wins, a stale `from` is rejected rather than
  applied. A gate's own precondition turns out simpler than a
  container's, and the shape is smaller for a stated reason rather than
  copied short: a container queue can be *any* of several named values,
  so `AdvanceContainerQueue` has to say which one it believes it is
  leaving; a gate has exactly one meaningful precondition — has this
  resolution already happened — so nothing about the command needs to
  say what state it expects to find, only which gate it is resolving,
  which both commands already carry. **This compare alone needs no new
  field** — the reopening-window fix below is a second, independent
  one, guarding a different question.

  The aggregate gains two project-wide fields beside `comment_count`/
  `gate_marks` above, on the identical simplification those two already
  state and revisit-condition: **`gate_resolutions: %{String.t() =>
  :approved | :declined}`**, absent key meaning "open." `execute/2` for
  `ApproveGate`/`DeclineGate` rejects when `cmd.gate` is already a key —
  `{:error, {:engine_gate_already_resolved, gate: cmd.gate, disposition:
  existing}}`, the same "name the value, not the actor" level of detail
  `:engine_container_queue_conflict` already gives (a screen wanting who
  reads the log the same way `document-review`'s own conflict rendering
  already would). `apply/2` for `GateApproved`/`GateDeclined` sets the
  key to the disposition; `apply/2` for `DraftCommitted` clears the
  whole map — a fresh commit reopens every gate, the identical fact
  `Catapult.Delivery.FeatureLifecycle.Projection.commit/2` already
  encodes on the delivery side (below), tracked here independently and
  for the same reason the container's own copy of `queue` is: "this
  copy exists only so `execute/2` can reject without a read." Project-
  wide rather than flow-scoped is the same call `CommentPosted` above
  already made and for the same reason — `DraftCommitted` carries no
  `flow_id`, "nothing yet opens two flows concurrently on one project"
  is exactly as true here as it was there, and the identical Phase 7
  revisit condition applies: multiple concurrent flows need this keyed
  by `{flow_id, gate}`, not a new mechanism.

  **This settles §7.16's still-open "compare token: version, not
  status" item, in favor of the recorded rule rather than the still-
  open alternative — a decision this ticket owes since it is the first
  to build the mechanism the item is about.** `gate_resolutions` is a
  named-value compare (`:approved | :declined | absent`), the same
  status-shaped kind `AdvanceContainerQueue`'s `queue` already is, not
  the aggregate's Commanded stream version — following "Author's call:
  the rule as stated compares on status" (§7.16) and the precedent
  already in this file, over the ABA risk the item itself names and
  leaves open. The ABA exposure this carries is the same one
  `AdvanceContainerQueue` already carries and no worse: a gate resolved,
  reopened by a commit, and resolved again looks identical, at the
  compare, to a gate resolved once — which is correct, since a second
  legitimate resolution *should* succeed. What stays closed either way
  is the case this fix exists for: two writers racing on the *same*
  still-open resolution.

  **Design review found a second axis `gate_resolutions` alone cannot
  cover: staleness against a regenerated body, not staleness against a
  resolution.** `DraftCommitted`'s own `apply/2` clears the whole
  `gate_resolutions` map (above) — correctly, since a fresh commit does
  reopen the gate for review — but reopening the *compare* also reopens
  the *action*: a reviewer who has `document-review` open on the body a
  decline just threw back can still click Approve after a regeneration
  commits a new body underneath them, and finds no key at `cmd.gate` to
  reject against, because the key that would have named their view was
  just cleared by the very commit they never saw. `gate_resolutions`
  answers "has this gate already been resolved since it last reopened,"
  which is the right question for two writers racing on one resolution
  and the wrong one for a single writer acting on a view of the wrong
  resolution.

  **The fix is the one already in this file, not a new one: `PostComment`'s
  own `body_sha` compare, on the same two commands.** `ApproveGate`/
  `DeclineGate` gain `node_id` and `body_sha`, the identical pair
  `PostComment` already carries and for the identical reason —
  `execute/2` rejects when `cmd.body_sha` doesn't match `nodes[cmd
  .node_id].body_sha`, the same per-node value `DraftCommitted`'s own
  `apply/2` already maintains (that's what makes `PostComment`'s
  existing check possible with no new aggregate state): `{:error,
  {:engine_stale_gate_resolution, node_id: cmd.node_id, current:
  current, got: cmd.body_sha}}`, `:engine_stale_comment`'s own shape
  reused rather than invented. This runs beside `gate_resolutions`, not
  instead of it — the two guard different failures: `gate_resolutions`
  rejects a second writer racing the first on one still-open
  resolution, `body_sha` rejects a resolution whose view is a body the
  aggregate has already moved past, resolved or not. Which `node_id`:
  Phase 4's own shipped `feature.yaml` runs exactly one `generation`
  status ahead of its gates (already named above), so the command edge
  — `document-review`, when ORC-75 builds it — has exactly one node to
  read `body_sha` off; the general node(s)-per-gate mapping stays
  exactly as open as the rest of this entry already leaves it, not a
  second deferral.

  **This does not reopen §7.16's "what a passed gate pins."** `body_sha`
  rides the *command*, compared and discarded before the aggregate
  decides whether to emit; `GateApproved`/`GateDeclined` gain no new
  field and still carry no content-identity of their own, so the
  content-pinning question this entry already leaves to Phase 7 (above)
  is exactly as open as it was. A command-side compare token and an
  event-side content pin are different mechanisms answering different
  questions, the same distinction `since_sequence` already draws on
  `DeclineGate` — a position the check ran against, not a claim about
  content.

  **Verify by breaking it, per orchestration's own rule for a guard
  rather than a feature**: two probes, not one. Revert `gate_resolutions`'
  compare and watch a regression test exercising two racing
  `ApproveGate`s (or an `ApproveGate` racing a `DeclineGate`) fail;
  separately, revert the `body_sha` compare and watch a test exercising
  decline → regenerate → stale approve fail — the exact sequence design
  review's own finding walks. Read each failure, put each compare back,
  record both probes in the commit message. Dev's, at implementation
  time; recorded here so the expectation travels with the decision
  rather than being invented at review time.

- **Unblocking a limit-class failure gains a real command — a human
  action, not only a regeneration retry** (ORC-114, design pass).
  `Catapult.Delivery.FeatureLifecycle.Projection`'s own moduledoc
  records the gap precisely: "a block clears only via a subsequent
  `DraftCommitted` retry — never a human action." `docs/ui-spec.md`
  §3.1's `my-queue` names **unblock** as one of exactly three actions
  the plane ever asks a human for, and J4 (§4) is "`board` (blocked,
  grouped under origin) → `ticket` → return to origin, or pick an
  earlier status from the prefix" — a real write, with nothing in
  `lib/catapult/engine/commands/` to dispatch.

  `Catapult.Engine.Commands.ResumeFlow{project_id, flow_id, to,
  actor_id}` → `Catapult.Engine.Events.FlowResumed{project_id, flow_id,
  to, actor_id}`, both v1, dispatched through the same router and
  landing on the same per-project aggregate as every other command
  here — an original protocol fact ("a human chose to resume this
  ticket at this position") nobody else in the log records, the
  identical ground `GateDeclined`/`CommentPosted` already stand on.
  `to` is the chosen return position (`Sequence.position()`-shaped,
  `systems/delivery.md`); validating it against the effective-sequence
  prefix up to and including the ticket's own `blocked_origin` — "never
  forward" (`docs/ui-spec.md` §6) — is the command edge's job, the
  identical division `gate`/`throwback_to` already draw: bundle- and
  projection-derived content is checked before dispatch, never inside
  `execute/2`.

  **The compare-and-swap is the same mechanism as the gate fix above,
  scaled down further: a gate has one precondition; being blocked has
  one too.** The aggregate gains a third project-wide field, `blocked:
  boolean`, `false` by default. `apply/2` for `RunFailed` sets it `true`
  — unconditional, since every `RunFailed` this system's own event
  already is limit-class by construction (its moduledoc: "a dispatched
  agent run failed on a limit-class error"), so there is no second
  failure class to distinguish here the way there was for a gate's
  disposition. `apply/2` for `FlowResumed` and for `DraftCommitted` both
  set it `false` — a retry and a human resume clear the same fact, the
  identical pair `Projection.commit/2` already clears on the delivery
  side. `execute/2` for `ResumeFlow` rejects unless `blocked == true`:
  `{:error, {:engine_flow_not_blocked, flow_id: cmd.flow_id}}` — a
  stale resume attempt (someone else already resumed it, or a retry
  already landed) reads identically to "never was blocked," which is
  enough for the rejection to be correct without the aggregate having
  to retain who resolved it, the same level of detail the gate fix
  settled on above. Project-wide, not flow-scoped, for the identical
  reason and the identical Phase 7 revisit condition as `gate_resolutions`
  and `comment_count` before it: `RunFailed` carries no `flow_id` either.

  `Catapult.Engine.Router` gains `ResumeFlow` in its dispatch list,
  beside `ApproveGate`/`DeclineGate`, with the same comment marking it
  part of this ticket's edge. Role authorization (does this `actor_id`
  own the blocked ticket's origin status) is left exactly where every
  other gate-adjacent command already leaves it — identity's, Phase 7.

- **`ApproveDraft`/`DiscardDraft` gain a dispatcher and the identical
  compare-and-swap `ApproveGate`/`DeclineGate` needed** (ORC-229,
  design pass). Both commands were registered and validated but had no
  production caller anywhere in `lib/**`: `Catapult.Delivery
  .FeatureLifecycle`'s `GateApproved`/`GateDeclined` handling
  (`systems/delivery.md`) already advances a ticket's projected status,
  but neither event ever touched `Node.status`, so a node reached
  `:drafted` and stayed there and `ReadyScopes.ready/3`'s
  `Enum.all?(targets, &(&1.status == :approved))` never turned true for
  anything downstream of it (dsl-syntax.md §7). Fixed at the dispatch
  side, not the read side — the identical shape ORC-117's join-target
  fix above already took. A new process manager,
  `Catapult.Delivery.DraftResolution` (`systems/delivery.md`, below),
  reacts to `GateApproved`/`GateDeclined` and dispatches
  `ApproveDraft`/`DiscardDraft` against the flow's own reviewed node —
  Phase 4's already-standing "one node per flow" simplification
  (above, and `systems/delivery.md`'s ORC-34 entry), unchanged by this
  ticket. Both events' own `actor_id` threads onto the resulting
  command unchanged, so `DraftApproved`/`DraftDiscarded` carry who
  acted the same way `ApproveGate` already does — v5 §7.19's "who
  approved is answerable from the object" holds for a draft the
  identical way it already holds for a gate.

  **Approve only when the resolving gate is the review group's own
  last one; decline discards unconditionally.** A gate's own citing
  sub-array (dsl-syntax.md §15.10) may hold more than one `review:`
  entry ahead of `checks` — `feature.yaml` ships two, `ux-review` then
  `engineering-review`, both reviewing the same single node (Phase 4's
  own mapping, above) — and marking the node `:approved` the moment
  the first of them passes would let a downstream context walk
  dispatch before the ticket's own required second sign-off ever ran,
  which is not what "readiness requires all targets ready" is supposed
  to mean. So `ApproveDraft` dispatches only when `GateApproved`'s own
  forward advance leaves the citing sub-array — the identical
  `leaves_group` computation `Catapult.Dsl.Workflow
  .throwback_target_details/3` already derives for a throwback target
  (`lib/catapult/dsl/workflow.ex`), read here in the forward direction
  instead; an earlier gate's approval only advances the ticket's own
  projected status, exactly as before this ticket. A decline is not
  the same shape: every `review:` entry in a `generation`/`critique`/
  review group falls back to the same leading `pending` (§15.10's
  fourth-pass correction, already the rule `screens/document-review.md`
  cites), so any `GateDeclined` against the node dispatches
  `DiscardDraft` unconditionally — there is no partial-decline case
  where the draft should survive.

  **`DraftDiscarded` resets the node to `:absent`, not a fourth
  status.** `Node.status` keeps the same three values ORC-117 already
  fixed it at — `Reducer.apply(%DraftDiscarded{}, _)` now clears the
  projection's `current_draft_id`/`body_sha` alongside the existing
  `set_draft_status(:discarded)`, and writes `status: :absent`, the
  identical value a never-drafted node already carries. This is the
  whole fix for "how a decline reopens a node for regeneration"
  (above, amending the still-open claim this doc made before this
  ticket): `ReadyScopes.ready/3`'s own candidate filter already reads
  `node.status == :absent` and needed no change, the same "write the
  correct value at the transition, not a new branch at the read"
  precedent ORC-117 set. The aggregate's own in-memory
  `pending_draft_id` was already cleared on `DraftDiscarded` before
  this ticket; only the projection was missing the equivalent reset.

  **`ApproveDraft`/`DiscardDraft` had no compare-and-swap either,
  found reading the code against §7.16's own rule the identical way
  ORC-114 found it missing on `ApproveGate`/`DeclineGate`.**
  `execute/2` for both commands read no aggregate state at all and
  would emit unconditionally on a replay or a duplicate dispatch —
  moot while nothing dispatched them, live the moment a process
  manager does, since a process manager's own event handler can itself
  be replayed. Both gain `PostComment`'s own shape:
  `execute(%__MODULE__{nodes: nodes}, %ApproveDraft{} = cmd)` rejects
  unless `nodes[cmd.node_id].pending_draft_id == cmd.draft_id` —
  `{:error, {:engine_stale_draft_resolution, node_id:, current:, got:}}`
  otherwise, `:engine_stale_gate_resolution`'s own shape reused rather
  than invented — and `DiscardDraft` takes the identical guard. A
  duplicate dispatch of either command against a node already moved
  past that draft (approved, discarded, or superseded by a fresh
  commit) is now a rejection, not a second event.

  **The review score stays exactly as parked as it already was.**
  Nothing here reads `ReviewWritten.score` — `docs/dsl-syntax.md`
  §15.10's "a parked scheduler item, §7.19, not bundle content" stands,
  and `ApproveDraft` dispatches only off a human's `GateApproved`,
  never off a review tier's own automated pass.

  **Closing this loop makes regeneration reachable, and regeneration
  leaves stale content downstream with no path back.** A fresh
  `DraftCommitted` against a node that was already `:approved` needs no
  new mechanism — `Reducer.apply/2` already sets `status: :drafted`
  unconditionally (above `Node.status`'s own three values), so
  `ReadyScopes.ready/3` correctly re-blocks every downstream context
  walk until the new draft is itself approved. What has no mechanism is
  content *already* committed downstream, against the superseded
  approval: nothing moves it back to `:absent`, so it stays put, stale,
  permanently.

  `Catapult.Engine.Projections.Staleness` computes exactly this fact —
  `stale?/2`, `target_newer?/2` comparing `committed_sequence` against
  each resolved context target's — and has no production caller: every
  `lib/**` reference to it outside its own module is a doc comment
  (`context_resolver.ex:8`, `:25`; `store/draft.ex:8`), not a call.
  Before this ticket no node ever reached `:approved`, so nothing ever
  drafted against one and the case could not occur; this ticket is what
  makes it live.

  How staleness is consumed is settled above — "consumed by flow walks
  and the plane's out-of-band ticket filing" — and
  `docs/v5-design-decisions.md`'s "staleness hints, never cascades"
  rules out an auto-reopening `ready/3`. What is missing is the
  connection: neither named consumer calls `stale?/2`. ORC-231 carries
  wiring it.

## Initial vs target

Initial (Phase 3): event log, reducer for the design dialect's event
set, core projections — including the active-bundle-version
projection above, decided now though no cutover exists yet to
exercise it — scheduler + sweeper, and the EventStore infrastructure
migration this needs to run at all. That migration's path,
`priv/repo/migrations_infra/**`, is `systems/foundation.md`'s mapped
file, not this doc's (this doc's own map above stops at
`lib/catapult/engine/**` and `test/catapult/engine/**`) — the need is
engine's, the file is foundation's, so this ticket carries
`system:foundation` alongside `system:engine`, matching
`foundation.md`'s own Initial-vs-target note that the migration lands
"with engine." Target: flow instances, staleness provenance,
snapshots, replay tooling surfaced in the dashboard.

**ORC-6's own diff stops short of the scheduler and sweeper**, despite
both being named Initial above. The ticket's own scope paragraph
enumerates "the Commanded application, per-project aggregates and the
event log, the reducer generic over bundle semantics, and the
universal projections" and names none of the reactive-runtime pieces;
`ready_scopes` and staleness land as this ticket's `Catapult.Engine
.Projections.ReadyScopes`/`.Staleness` — pure queries against current
projections, exactly the "state-driven" shape the scheduler standing
decision above describes — so a later ticket's scheduler process has
something to call rather than something to build from scratch. Filed
here rather than silently: this is a deviation from this doc's own
Initial line, argued for in ORC-6's hand-back.

**The engine's own store tables live at `priv/repo/migrations/**`**,
added to this doc's file map by the same ticket. Distinct from
`priv/repo/migrations_infra/**` (foundation's, for EventStore/Oban):
these are ordinary per-store domain tables (`engine_nodes`,
`engine_edges`, ... — conventions §6), and `priv/repo/migrations` is
Ecto's own default path, so nothing but foundation's is under
`_infra`. `staleness` and `ready_scopes` are deliberately absent from
that migration and from any table: both are pure queries
(`Catapult.Engine.Projections.Staleness`/`.ReadyScopes`), never
materialized, per this doc's own standing decision above.

## Depends on

substrate, foundation (EventStore infra), core_dsl (bundle semantics
the reducer is generic over).
