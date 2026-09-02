---
paths:
  - lib/catapult/generation.ex
  - lib/catapult/generation/**
  - test/catapult/generation/**
---

# generation

The plane's design-dialect coordination — **agents end-to-end (v5
§1.2): the plane never generates, it dispatches**. This system takes
ready `(tier, scope)` pairs from `ready_scopes`, evaluates context
walks and renders the Liquid prompt, dispatches an agent run via the
delivery system's host port, serves the rendered context to the
runner-side harness, and validates the committed body against the
tier's grammar (via core_dsl) when the agent reports. The app-facing
runtime dialect (components/runtime, Phase 8) shares the rendering
and validation logic and must not fork it.

## Standing decisions

- **The plane holds no working copies and makes no model calls.**
  The runner's checkout is the working copy; bodies reach the plane
  as commits to read at a SHA, never as files on its disk. The
  in-plane persistence class (branch management, working trees,
  ephemeral-disk writes) is deleted by construction.
- **Dispatch coordination holds no state and makes no decisions**:
  what to generate comes from `ready_scopes`; what to render comes
  from the bundle; whether output is acceptable comes from the
  grammar. If coordination needs memory, the design is wrong
  somewhere upstream.
- **Validation failure is feedback, not error**: a grammar-invalid
  commit returns a typed error the agent
  retries with, bounded; a half-committed state is impossible
  because commit-time validation gates the event.
- **Same renderer for generation and review** (the per-tier triad
  invariant, SiegeEngine's rule): the reviewer sees exactly the
  generator's context plus the draft. Enforced by sharing the
  context-assembly code path, not by convention.
- **Latency scales the pool, never the architecture**: slow
  generation means an autoscaling worker pool pulling from the
  queue — generation never moves in-plane.
- **`Extraction.mints/4` decides a minted node's initial status, not
  only its identity** (ORC-117, design pass). Building a mint entry
  already means resolving the target tier's own declaration out of
  `chain`; that same lookup now also reads whether the target
  declares a `draft:` block and carries the answer on the entry
  (`:approved` for a join target, `:absent` otherwise), rather than
  the reducer inferring it from bundle content it isn't supposed to
  read. The decision this answers to — what a join target's status
  means and why readiness needed no change — is `systems/engine.md`'s;
  this entry only records that the computation sits here rather than
  being rediscovered as a surprise in that ticket's diff.
- **The execution substrate is an adapter behind the host port**
  (v5 §7.12.1, §8): Actions (the default) and the worker pool (BYO
  cluster canonically, managed opt-in) are two adapters over one
  runner-harness contract — fetch rendered context, run agent,
  commit, report. The contract is the invariant; nothing outside
  the Actions adapter may assume Actions. The dispatch-concurrency
  cap is a per-instance `tunable` in plane state, never a config
  constant — scheduler backpressure and hosted tiering share it. A
  **daily dispatch budget** (warn + cutoff `tunable`s) rides beside
  it; alerts via observability, mirrored on the dashboard (v5 §7.4's
  two-channel rule).
- **Runners authenticate with GitHub Actions OIDC** (v5 §7.12.1):
  the plane's context-fetch and result-report endpoints accept
  GitHub's signed ID token, validated against GitHub's JWKS with
  audience + `repository` + `run_id` matched to the plane's own
  dispatch record. No secret rides the dispatch inputs (they are
  visible-log territory). Pool adapter: plane-minted per-dispatch
  tokens over the dispatch channel. **Rendered context never
  contains bindings or credentials.**
- **The endpoint's listener is foundation's, not a second one this
  system stands up** (design review finding, ORC-9): `systems
  /foundation.md` records where context-fetch and result-report are
  actually served — a second path on the existing health listener,
  composed from generation's and delivery's `api_surface/0`
  declarations, ahead of the general router that will eventually
  absorb them — and why it isn't dashboard's router yet. This ticket
  carries `system:foundation` alongside `system:generation` and
  `system:delivery` for exactly that reason: the handler logic (OIDC
  validation, run correlation, context/result payloads) stays here and
  in delivery's file map; foundation owns only the listener it answers
  on.
- **Run-result reporting is that same authenticated callback, not a
  marker comment** (ORC-9's open question, resolved): the
  result-report call reuses the identical OIDC bearer settled in the
  bullet above — no second trust decision. The deciding reason is the
  retry promise below: a grammar-invalid commit returns a typed error
  the agent retries with, *bounded within the same run* — and only a
  synchronous request/response can hand that back to a process still
  executing. A marker comment can announce a result to a human later;
  it cannot hand a typed validation error to the agent that is still
  running. Marker comments stay the right shape exactly where
  `systems/delivery.md` keeps them — GitHub PR comments, a surface
  whose cadence the plane doesn't own — but a result report is
  plane-to-plane over a channel the plane owns both ends of, so the
  marker's reason for existing doesn't transfer here.
- **Catapult owns its generation runner harness, built here** (ORC-215,
  reversing this entry's own prior reading of ORC-9's open question).
  The prior text read v5 §1.2's third reason — "one execution path...
  extended rather than duplicated" — as a mandate to consume
  orchestration's own harness as a pinned dependency, and read
  `docs/non-goals.md`'s no-self-bootstrap entry as supporting that.
  Neither does: §1.2's reason is proven-*pattern*, not proven-*code*
  (sharpened there, ORC-215), and no-self-bootstrap is about consuming
  the shared components (`components/**`) as an ordinary library user
  — a different question from which repo authors a `workflow_dispatch`
  file this repo already pushes into a bound project's own repo
  (`systems/delivery.md`'s ORC-10 entry). Orchestration builds
  Catapult; it participates in none of Catapult's own mechanisms, this
  one included.

  The contract is unchanged (v5 §7.12.1: fetch rendered context, run
  agent, commit, report) and so is the seam: the run-agent step is the
  only implementation-specific piece, so a second agent implementation
  is a bindings entry, never a rewrite of the steps around it (the
  entry below settles which one).

  **Where the run-agent step's code lives: inline in the dispatched
  workflow content, the same fixture-content mechanism `reset_repo/2`
  already pushes into a bound repo** (`systems/delivery.md`'s ORC-10
  entry) — no new mechanism, the placeholder step is filled in place.
  Two alternatives, ruled out rather than merely unconsidered: a
  composite action under this repo's own `.github/actions/**`,
  referenced cross-repo from every bound project's workflow (`uses:
  <this repo>/…@ref`), would tie every dispatched run forever to this
  repo's own git history instead of to the reviewed commit its own
  bound-repo workflow file already pins — the mirror image of the
  coupling §1.2's sharpened reason just closed off, one hop later —
  and `.github/actions/**` has no owner in this repo today
  (`systems/README.md`'s unowned-paths list doesn't carry it), so
  creating one is the author's call, not a ticket's. A script fetched
  from the plane at run time was the other candidate, also ruled out:
  it would give the plane a live code-serving role beyond its two
  settled dispatch endpoints (context-fetch, result-report), a new
  authenticated surface bought for no protocol gain, and it ties an
  in-flight run's behavior to whatever the plane's *current* deploy
  happens to serve rather than to the commit its own workflow file
  pinned when the run started.

  **The classified outcome vocabulary is not new** —
  `Catapult.Delivery.ResultHandler`'s `payload().status` is already
  the closed `:success | :limit_class_failure | :other_failure` union,
  and `Catapult.Generation.CommitPath`/`Catapult.Delivery.Dispatch`
  already branch on it; what was missing is how the harness computes
  which one applies. `claude -p --output-format json`'s terminal
  `result` object's `subtype` (`success`, `error_during_execution`,
  `error_max_turns`, `error_max_budget_usd`,
  `error_max_structured_output_retries`) does not itself carry that
  distinction: a usage/rate-limit failure and any other in-run failure
  both surface as `error_during_execution`, so classifying off that
  field alone would be exactly the stderr-string-matching shape this
  harness exists to leave behind. The structured signal is one layer
  down, in `--output-format stream-json`'s `system`/`api_retry` events
  (`{"type": "system", "subtype": "api_retry", "error_status": …,
  "error": …}`), whose documented `error` category is the CLI's own
  closed ten — `authentication_failed`, `oauth_org_not_allowed`,
  `billing_error`, `rate_limit`, `overloaded`, `invalid_request`,
  `model_not_found`, `server_error`, `max_output_tokens`, `unknown` —
  a read of the underlying API error, not a guess at the CLI's
  wording.

  Classification is two-stage and precedence-ordered, not a flat
  three-way split, and the harness already implements it in that
  order: a terminal `result` event whose `subtype` is `success`
  reports `success` regardless of anything seen earlier in the
  stream — a run that retried past a `rate_limit`
  `api_retry` event and then finished cleanly still reports
  `success`, because the harness checks the terminal event first and
  the accumulated retry history only matters when that check fails.
  Only then do the nine non-`success` categories apply, and each has
  a stated assignment rather than a default: `rate_limit` and
  `billing_error` are the two that answer to v5 §7.12.1's own phrase,
  "usage/rate limits, exhausted credits", so a non-`success` run whose
  stream carried either reports `limit_class_failure`, and the
  harness fails over to the next credential if one is still unused.
  The remaining seven report `other_failure`, each for a stated
  reason rather than by omission: `overloaded` is Anthropic's own
  capacity, not this account's usage or credit standing — the same
  reasoning that already keeps `server_error` out of limit-class —
  so a same-run credential failover wouldn't address it; a redispatch
  would, and stays outside this entry's failover mechanism.
  `oauth_org_not_allowed` is credential-shaped but not usage-shaped —
  the org has disallowed the OAuth credential outright, which is the
  same kind of problem `authentication_failed` already reports as
  `other_failure` rather than limit-class — so it joins that bucket
  rather than triggering a failover that would mask a configuration
  problem needing a fix, not a workaround. `model_not_found` and
  `invalid_request` are request-shaped, not usage-shaped, and join
  `other_failure` for the same reason `invalid_request` already did.

  `other_failure` stays undifferentiated by design, not by gap: the
  terminal `result` object also carries `stop_reason`, and
  `stop_reason == "refusal"` is a real, documented signal for
  detecting a declined request — the harness chooses not to consume
  it because nothing downstream of the `other_failure` bucket reads a
  finer split today, not because the CLI fails to expose one. The
  undifferentiated bucket is a recorded choice, not an absence of
  signal.

  **The subscription credential's own session and weekly ceiling is
  classified by the same rule, on a stated assumption rather than a
  documented shape.** Claude Code documents `api_retry`'s `error`
  categories for retryable API errors and, separately, a claude.ai
  usage limit as something that stops a run mid-task — a `-p` run
  does not wait for the reset — without saying which event a
  headless run emits when it does. Two shapes are possible, and the
  rule is right on one and blind on the other: a `429` arriving as
  `api_retry` with `rate_limit` fails over to the API key as
  intended; a terminal `result` of `error_during_execution` with no
  retry event reports `other_failure` and never fails over, which
  loses exactly the case the pair exists for. The first run that
  hits the ceiling settles which is real — its `stream-json` output
  is in the bound repo's Actions log for that run — and until then
  an `other_failure` on the subscription credential whose `result`
  names a usage limit is this rule's failure mode, and reads as one.

  **No failover retires today, not on a future date** (this same
  entry's prior text already named the day: "the adapter starts
  sending the tunable's full ordered pair instead of its head — a
  one-line change... because the contract was already built for two").
  That day is this ticket: `HostPort.request`'s `credential_name`
  widens to the bindings tunable's full ordered pair
  (`systems/delivery.md`'s own entry), and `Actions.dispatch_run/1`
  sends it whole.
- **The bindings entry is `:generation`, one kind in the same kind →
  runtime map v5 §7.10 already describes for ticket-delivery agent
  kinds** (design, dev, reconcile, validation, retro, setup — none
  built yet, Phase 7), not a second, generation-only mechanism:
  Catapult's own chain has exactly one kind today, and reusing the one
  map is what makes "supporting a second agent implementation is a new
  bindings entry and zero protocol or bundle change" (v5 §7.10) literal
  rather than aspirational the moment Phase 7 lands its own kinds
  beside this one. Per-tier executor-profile routing (model, effort,
  harness requirements) stays Target, unchanged by this entry — this
  ticket picks one runtime for every generation dispatch project-wide,
  never per tier.

  `Catapult.Generation.cast_credential_order/1`'s closed two-name set
  (`claude_code_oauth_token`, `anthropic_api_key`) is Claude-Code-
  specific and moves to bindings, keyed by whichever runtime is bound
  to the `:generation` kind — a second implementation's own credential
  names arrive as a new bindings entry, never a rewrite of this
  validator. The general bindings-as-plane-entities store (v5 §7.10)
  still doesn't exist and this ticket doesn't build it: the
  credential-order and kind→runtime tunables keep the
  "accepted-for-now" env-var-config shape `Catapult.Generation`'s own
  `config/0` already uses for exactly this reason, reorganized to be
  keyed by implementation rather than hardcoded to Claude Code's two
  names — a fact that holds however long the real store takes to
  land, not a placeholder timed to this ticket.
- **Model credentials are a pair with limit-class failover** (v5
  §7.12.1): the runner harness accepts `ANTHROPIC_API_KEY` and/or
  `CLAUDE_CODE_OAUTH_TOKEN` — customer-side secrets the plane never
  sees, named by whichever runtime is bound to the `:generation` kind
  (today, Claude Code's own two — the entry above). Order is a
  per-project bindings `tunable` passed as a dispatch input (a
  preference, not a secret); failover on limit-class errors only; the
  run report names which credential served.
- **The three §7.15 pause/resume invariants bind this executor, not
  aspirational**: one dispatched run per ready scope, one atomic
  commit per scope at the end, no memory across dispatches. The
  scheduler (`systems/engine.md`) already hands the third one over for
  free — `Catapult.Engine.Scheduler` broadcasts the *full* ready set on
  every trigger, holds no memory of what it last announced, and says
  so in its own moduledoc ("the payload is a hint, never an
  authority — a consumer re-validates before acting on it") — so this
  executor's own re-check at dispatch time (is this scope still ready?
  is it already committed?) is the same discipline one layer up, not
  new work. The first invariant is where dedup actually has to live:
  Oban's own job uniqueness, keyed on `{project_id, tier, scope_key}`
  and held for the scope's in-flight window, is what turns a
  liberally-re-announcing broadcast into one dispatch per scope,
  rather than a new in-plane pending-set — the exact kind of
  coordination memory the "holds no state" bullet above already
  refuses. Repeated limit-class failure on the *same* scope — as
  opposed to a failure that clears on redispatch — is `Blocked` with a
  named reason (§7.15), never a further retry: the readiness query
  cannot distinguish "will succeed next window" from "never fits in a
  window," so the executor answers that with a query, not a counter —
  **the count is derived from the log, never held** (design review
  finding, ORC-9, resolving the apparent conflict with the invariant
  just stated). Every limit-class run failure is its own event, on the
  scope's node, in generation's own `events/0` (a new entry this
  ticket adds), landing in the same per-project stream engine's
  `draft_committed` already writes to — one aggregate per project, not
  one per system. The derivation walks the log backward from now to
  the node's most recent `draft_committed` (or the log's start, if
  none), counting limit-class failure events since. `Blocked` fires
  once that count repeats past one. This satisfies the invariant
  rather than contradicting it: "no memory across dispatches" is a
  claim about the *dispatched run*, which still re-renders its context
  walk and starts clean every time — the count lives once, in the
  plane's log, the same place every other derived answer in this
  system already lives (`systems/engine.md`'s "no in-memory
  pending-set" doctrine, one layer down), not in a table row or an
  Oban attempt counter. The rejected alternative is concrete enough to
  name the reason it's wrong: an Oban attempt count is scoped to one
  job, and the uniqueness key that turns a re-announced ready scope
  into one dispatch (above) is held only for the scope's in-flight
  window — once that window closes, a redispatch is a *new* job
  starting its attempt count at zero, so the very mechanism that
  dedups dispatch would silently reset the failure count it would have
  to hold. The log has no such window.
- **ORC-87 confirmed rather than assumed, and this design carries its
  consequences forward.** The Oban uniqueness key the first §7.15
  invariant leans on, `{project_id, tier, scope_key}`, matches the
  unique index ORC-87 actually landed on `engine_nodes`
  (`(project_id, tier, scope_key)`) — `scope_key` is unique only
  within a project and a tier, exactly the granularity the dedup key
  needs and no finer than the table itself already enforces, so
  nothing about the key changes. Everything this executor commits —
  drafts, and the run-outcome events the bullet above adds — writes
  with `(project_id, id)` from the start, through `Store`'s
  post-ORC-87 shape (`get_node/2`, `edges_from/3`, `approve_node/2`
  all take `project_id` now); no new bare-id `Store` call site is
  introduced here for ORC-87 to have to find and thread later.
- **`feedback` and `prior_review` are read here, not routed through
  delivery** (ORC-34). Neither is delivery-owned state, so
  `ContextAssembly` reads both directly from the engine —
  `Engine.Projections.CommentFeedback.since_last_resolution/2` and
  `Engine.Store.reviews_for_node/2` — beside the
  `ContextResolver.resolve/2` and `Store.fragments/2` reads it already
  makes for everything else it renders. Both are unconditional, unlike
  `draft`: neither is review-tier-only (`docs/dsl-syntax.md` §9/§3.3,
  which also carries their rendered shapes).

  Two decisions this entry deliberately does not restate, because each
  is recorded where it would be edited: `since_sequence` is
  caller-supplied rather than computed inside `execute/2`
  (`Catapult.Engine.Commands.DeclineGate`, on this system's purity
  floor), and the reset boundary is neither `DraftCommitted` nor a
  position in the resolution sequence — `CommentFeedback`'s own
  moduledoc names both rejected alternatives, their failure modes, and
  the shipped bundle that breaks the second.

- **`ContextAssembly` renders an `input.<role>`/`input.*` entry from a
  second, direct read of delivery — never through the node-collection
  fold `ContextResolver.resolve/2` feeds every other walk** (ORC-107,
  closing the gap the ORC-10 entry below names). `ContextResolver`'s
  `{:ok, []}` answer for `:input` (`systems/engine.md`'s entry) is
  correct for readiness and staleness and useless for rendering: an
  empty node list has nothing for `render_node/2`'s `handle_fields`/
  `handle_fragments` to project, and an input document has no
  `handle:` to project in the first place — it is pinned prose, not a
  tier instance. So `build_variables/5` gains a second, parallel step
  for exactly the walks whose `source` is `:input`: it reads the
  pinned document(s) straight off `Catapult.Delivery` (the raft's
  storage and pinning mechanism is `systems/delivery.md`'s entry), the
  same cross-boundary shape `draft_variable/2` already uses for
  `Delivery.get_draft_body/2`, and sets the result as a **plain
  string** variable — keyed by role name for `input.<role>`, or the
  reserved word `raft` for the wildcard (`dsl-syntax.md` §9, both
  settled there). A role with no pinned documents is left out of the
  variables map entirely, the same omission-is-the-contract shape this
  module already uses for `feedback`/`prior_review` above — never
  `""`, never a key that would make a bare `{% if %}` fire on nothing
  the way an empty list does (this module's own moduledoc explains why
  that distinction is guarded on `.size > 0` rather than truthiness for
  the list-shaped variables; a plain string carries no such trap, so
  `input.<role>`'s prompts guard on bare `{% if project_doc %}` and
  that is sufficient).

- **The agent-port fake is scope, not test scaffolding** (the same
  standing decision `systems/llm.md` makes for the runtime's provider
  fake, made here for the same reason): canned bodies through the real
  commit path are what let the whole chain run offline and
  deterministic in the default suite (conventions §9 — no network,
  ever), and it is what proves dispatch and validation correct
  independent of a live run ever firing. It ships with the port, like
  every other fake in this codebase, and is never treated as
  disposable relative to the Actions adapter it stands in for.
- **ORC-36, design pass: what proves the authoring loop end to end,
  and the one assertion that cannot be waved through.** The offline
  half extends `Catapult.Generation.IntegrationTest`'s existing shape
  — dispatch through `HostPort.Fake` into the real commit path —
  rather than founding a new ring: one run carries a scope past
  commit and into the gate-review commands this system's file map
  already owns test coverage for: `Commands.PostComment` against the
  committed `body_sha`, `Commands.DeclineGate` with `since_sequence`
  sourced the way production sources it
  (`GateComments.last_resolution_sequence/2`, `systems/engine.md`'s
  ORC-34 entry), then a second dispatch through the same fake reading
  the regenerated context back.

  The ticket names the assertion most likely to be quietly skipped,
  and it is bucketing, not occurrence: the test must post its comment
  against one named node, decline that node's gate, and assert that
  the *regenerated context for that node* —
  `ContextAssembly.build_variables/5`'s `feedback` entry — carries the
  comment's body, **and** that a sibling node minted off the same
  parent, never declined, regenerates with no such feedback.
  `CommentFeedback.since_last_resolution/2` is a per-`node_id` fold
  (`systems/engine.md`); a test asserting only "regeneration happened"
  cannot tell that fold apart from one bucketed by project or by gate
  — which is exactly the class of bug this same fold's history already
  produced once (the position-based `since_sequence` inference that
  broke the moment a workflow declared more than one gate, corrected
  on a third design-review pass in that file). Two nodes, one
  declined, is the cheapest fixture that makes the two hypotheses
  disagree, and the reasoning is orchestration's own, restated here
  because it applies: assert the thing that would go wrong, not a
  side effect every wrong implementation produces too.

  The `:live` variant extends `Catapult.Generation.ToySeedChainLiveTest`
  under the tag and the ORC-29 non-asks this file already binds it
  to (no polling, no round-trip closing, one bounded request per
  call): it widens which of this loop's real outbound calls that test
  exercises. It does not re-prove the decline-bucketing assertion
  above live — that assertion is a fold over the plane's own event
  log and crosses no network boundary, so a `:live` copy of it would
  be the exact empty gate ORC-29 refuses (conventions §9: the tag
  belongs only on a test that crosses a real network boundary, and a
  test that could run offline tagged to run less often instead is
  worse than an empty gate, because it reports as coverage).

  `docs/chain-runbook.md`'s retirement (this same design pass) leaves
  two references dangling in files outside `designOwnedPaths`, for
  dev to repoint when this ticket's test work lands rather than
  leave to be found later:
  `test/catapult/generation/fixtures/toy_seed/catapult-dispatch.yml`'s
  header comment, and `toy_seed_chain_live_test.exs`'s own moduledoc,
  which names the runbook as the reason that test doesn't assert a
  round trip — the reason still holds (above), only its citation is
  stale.

- **A test must be able to assert that a generated tier's rendered
  prompt reflects an `input.<role>` document, offline** (ORC-107,
  reversing what this entry recorded before intake existed — see the
  entry above for the mechanism). `ContextResolver.resolve/2` now
  returns `{:ok, []}` for every `input.*` walk (`systems/engine.md`'s
  entry), and `ContextAssembly` reads the pinned document straight off
  `Catapult.Delivery` for the variable itself rather than through that
  empty node list — so the content a chain test needs to assert on
  reaches the prompt through a path `ContextResolver` never touches.
  The offline chain test asserts on `project_doc`'s own pinned text
  reaching a rendered prompt, alongside the graph-native walks it
  already asserts on below: that assertion is the only one that
  reaches `ContextAssembly`'s direct-read step (the entry above) at
  all. `ticket.<source>`
  is unchanged — still `{:error, :unsupported}`, v5 §7.11's Phase 7 —
  and no test may assert a tier reflects one.

  The toy seed's per-role input documents (`test/support/toy_seed.ex`)
  are what such a test reads once intake pins them: real seed
  evidence, not a prop, and no longer inert. What the toy seed already
  proves — the graph-native chain, `self`/`self.parent`/`all.*` walks,
  every tier reachable from `comparch` down through `impl`, at least
  one instance of every edge type, which is the whole of what
  `ContextResolver` resolves — needs no input-role content and is
  unchanged by this entry; the input-role assertion above is additive
  coverage for the path that was previously unreachable, not a
  replacement for it.

- **The sweeper honours the test-project lifecycle, at both sites
  that can dispatch** (`systems/delivery.md`'s ORC-216 entry).
  `Sweeper.sweep_project/2` skips a project id `Catapult.Delivery
  .sweepable_project?/1` answers `false` for, checked once per project
  per tick rather than scope-by-scope after the fact: a released or
  deleted test project's whole tier loop is skipped outright, upstream
  of the tier walk. That alone leaves a gap open: a job already
  enqueued on the tick before a project releases would otherwise
  dispatch after it, since `DispatchWorker.perform/1`'s own
  re-validation checks only `still_ready` and `not_blocked` today
  (`DispatchWorker`'s own moduledoc, §7.1's validate-or-revert
  discipline). `sweepable_project?/1` becomes a third check there,
  run alongside those two, closing it. `sweepable_project?/1` answers
  `true` for a project id naming no row in `delivery_projects` at all
  (an ordinary, non-test project — none exist yet, and the predicate
  is written to hold once one does) and for a test project whose
  recorded state is `:active`; `false` for `:released` or `:deleted`.
  This is a read, not new sweeper state — neither process holds any
  memory of what it last enqueued, and `Catapult.Delivery` stays the
  one state of record for the lifecycle.

  **A dev-pass discovery, named here rather than left implicit: the
  sweep's own project enumeration has to widen too, or a freshly
  provisioned test project is never swept at all.** `Sweeper.sweep/0`
  walked exactly `Catapult.Engine.Store.list_project_ids/0` — every
  project id with a node, a flow or an active bundle version — and a
  project the provisioning surface has only just minted, bound and
  intake-pinned has none of the three until its first tier ever
  drafts. `feature_expansion`'s own singleton candidate is
  organically ready the moment a project id exists at all (this
  file's own ORC-107 entry), so the missing piece was never
  readiness — it was that the sweep never asked the question for a
  project id it had not yet heard of. `Sweeper.sweep/0` now walks the
  union of `Store.list_project_ids/0` and `Catapult.Delivery
  .list_bound_project_ids/0` (every project id ever bound to a repo —
  no dispatch happens without one regardless): Generation already
  depends on Delivery for dispatch, so the union sits here rather
  than widening `Catapult.Engine.Store.list_project_ids/0` itself,
  which would reverse that dependency and close the cycle `mix xref
  graph --format cycles --fail-above 0` refuses.

## Initial vs target

Initial (Phase 3): readiness-driven dispatch for the upstream tiers,
offline against the agent-port fake (canned bodies through the real
commit path). Live dispatch onto Actions returns `:dispatched` from
the workflow hand-off alone; the dispatched run itself calls back to
whichever plane is reachable, so closing that loop needs a project the
*deployed* instance's own database holds a row for, never the boundary
suite job's own throwaway one. The test-project lifecycle
(`systems/delivery.md`) is the mechanism: the live suite provisions a
project through the deployed plane itself, so a dispatched run's
context-fetch and result-report land in the same database that issued
the dispatch. The host
port's dispatch-facing slice — context-fetch, result-report, OIDC
validation, run correlation, its in-memory fake — is pulled forward
into this phase from delivery's Phase 4 (`systems/delivery.md`),
scoped to exactly what dispatch needs; the rest of the host port
(feature-lifecycle PR management, decline harvesting) still waits for
Phase 4. Regen-with-feedback threading has since landed (ORC-34,
above: `feedback`/`prior_review` read straight off engine's own
projections). Target: review passes, executor-profile routing, the
shared seam with the runtime dialect kept clean.

## Depends on

engine (ready_scopes, commands), core_dsl (grammars, walks),
delivery (host port, dispatch, run correlation), foundation (serves
the dispatch-facing host port endpoint on its listener),
platform_content (the prompts).
