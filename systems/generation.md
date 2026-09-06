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
  recorded state is `:active`; `false` for `:provisioning`, `:released`
  or `:deleted` (`:provisioning` added by ORC-224, below — a test
  project reads unsweepable from the moment it is minted, not only
  once released or deleted).
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

- **A fourth re-validation closes the loop the other three couldn't
  see: an in-flight guard, derived rather than held** (ORC-223).
  ORC-216's `still_sweepable/1` catches a released test project;
  `still_ready/4` catches a scope that already committed or fell off
  the ready set; `not_blocked/3` catches a scope that keeps
  limit-class-failing. None of the three answers "is a dispatch for
  this exact scope already running" — the failure mode 574 dispatch
  runs on `SwaggerAllen/catapult-test` in twenty minutes actually was,
  and every one of them slipped past all three because each looked
  ready, unblocked and sweepable on its own terms every time it was
  re-checked. `DispatchWorker.perform/1` gains a fourth check, placed
  first — it needs nothing `still_ready/4` and `not_blocked/3` resolve
  a node to answer, only the job's own `project_id`/`tier`/`scope_key`
  args: skip if `delivery_dispatch_runs` already holds a
  **non-terminal** row (`status` in `:dispatched`/`:context_fetched`)
  for this `(project_id, tier, scope_key)`, dispatched within the last
  `dispatch_stale_after_ms` — a new `tunable`, the same
  accepted-for-now config-constant shape `sweep_interval_ms` above
  already carries (`GENERATION_DISPATCH_STALE_AFTER_MS`, default
  `10800000` — three hours). The query itself is delivery's own
  (`systems/delivery.md`'s companion entry states the mechanism); this
  entry states the policy.

  **Age, not held state, is what frees a wedged scope** — the same
  "derived from the log, never held" discipline the limit-class-failure
  count above already uses, for the identical reason: a counter or a
  status flip this worker would have to remember to clear is exactly
  the in-plane pending-set both this system's "holds no state" bullet
  and that log-derived-count entry already refuse. A genuinely dead run
  (a crashed runner, a network partition that ate the final report, an
  expired OIDC token on the last call) ages out of the guard's own
  window on its own, without anything writing to the stale row — the
  next sweep tick simply dispatches a fresh one for the same scope once
  the cutoff passes, with no distinct "abandoned" state anything has to
  invent, notice or reap.

  **The cutoff, argued rather than picked.** The harness's own
  worst-case wall clock for a *legitimate* run is bounded, not
  open-ended, once this ticket's other two parts land. The run-agent
  step tries up to two credentials, each bounded at the existing 1800s
  subprocess timeout (`catapult-dispatch.yml`); a credential that
  itself hits that timeout reports `other_failure` and does not fail
  over (the harness's own exception handler `break`s rather than
  `continue`s), so the only path that reaches a `:success` outcome
  costs at most two such windows — 3600s. A `:success` outcome that
  then fails grammar validation retries in the report step, bounded at
  two further attempts (the entry below), each against that same 1800s
  timeout — up to another 3600s. 7200s (two hours) is the harness's own
  ceiling for a run that ends in `:success`; three hours is that
  ceiling with room for GitHub's own queue/startup delay before the job
  even begins running, not a second independent guess.
- **The harness's own report step bounds its grammar-retry loop and
  always reaches terminal** (ORC-223, making good on
  `Dispatch.simulate_result/2`'s own comment that "a further
  `report_result/2` call for the same `run_key` is expected next" — a
  promise the harness never actually kept until now). Only a
  `:success` report that the grammar rejects stays in flight
  (`Catapult.Delivery.Dispatch`'s own `mark_failure/3` clauses — a
  `:limit_class_failure`/`:other_failure` report always completes
  today, unaffected by this entry); the four reasons `report_result/2`
  answers 422 for are exactly the grammar-class failures named in
  `Catapult.Delivery.Dispatch`'s `status_for/1` (`schema_invalid`,
  `malformed_xml`, `root_tag_mismatch`, `schema_not_found`), and none
  of the others (`missing_bearer`, `run_not_found`, a repository/run-id
  mismatch) is fixable by asking the agent to resubmit — the harness
  does not retry those, and a run that fails one of them still ends
  non-terminal exactly as today, which is what the in-flight guard
  above exists to bound regardless of cause.

  On a 422 whose body decodes to one of the four grammar reasons, the
  report step re-invokes the agent — same credential, no failover
  (grammar rejection is not a usage signal), the same 1800s subprocess
  timeout as the original call, prompted with the original rendered
  prompt plus the decoded error appended as a corrective turn — and
  reports again. Bounded at two such retries (three submission attempts
  total): enough for a shape mistake to self-correct without turning
  one rejected report into the open-ended loop this same ticket exists
  to close. Exhausting the bound reports `other_failure` with
  `reason: "grammar_retries_exhausted"`, the same shape every other
  classified outcome already reports in — no new status on
  `DispatchRun`, no new branch in `Dispatch.simulate_result/2`, because
  `other_failure` was already a terminal report before this entry.
- **Stub mode is a per-dispatch workflow input, tied to test-project
  state — never a repository variable on the fixture repo** (ORC-223,
  author's decision). The alternative — a `vars.STUB_MODE` set once on
  `SwaggerAllen/catapult-test` — is out-of-band state the plane doesn't
  control per dispatch: it would apply to every future dispatch to that
  repo regardless of which run needs it, and reading it back to know
  whether a given run *was* stubbed would mean a second source of truth
  beside `delivery_dispatch_runs`. A `workflow_dispatch` input costs
  nothing new: `run_key` and `credential_order` already ride this
  channel, and stub mode is exactly the same shape — plane-decided,
  per-dispatch, visible in the run's own log.

  **`stub_mode` is a per-project opt-in, not a fact of being a test
  project** (design review correction — the first draft of this entry
  read it off `delivery_projects` row existence alone, which would have
  stubbed every test-project dispatch unconditionally, Waypoint's
  Phase-5 proof run included, defeating the one proof
  `docs/build-plan.md`'s Phase 5 exit criterion needs to run for real).
  Test-project status and stub status are two different questions —
  "is this project reclaimable by the milestone cadence" and "should
  its dispatches skip the model" — and the lifecycle record now answers
  both, as two independent fields rather than one collapsed into the
  other: `delivery_projects` gains `stub_mode` (boolean, not null,
  default `true` at the column). `POST /dispatch/test-project` (the
  provisioning surface's mint operation, above) takes an optional
  `stub_mode` field in its JSON body and `Store.mint_test_project/1`
  widens to accept and persist it; omitting it keeps today's toy-chain
  behavior unchanged. `ToySeedChainLiveTest` sends no such field and
  gets stub dispatches by the column default, exactly as it does today;
  `TodoAppProofLiveTest` sends `stub_mode: false` and its dispatches run
  the real model. `Catapult.Delivery.stub_mode?/1` reads this column,
  not row presence — and, for a project id holding no `delivery_projects`
  row at all, answers `false`. That is the deliberate mirror of
  `sweepable_project?/1`'s own no-row answer (`true`, above): no row is
  the ordinary-project case for both predicates, but the two questions
  they answer point opposite ways on it — an unbound project is
  trivially sweepable (nothing exempts it) and must never dispatch
  stubbed (nothing opts it in), so the same absence reads as `true` on
  one and `false` on the other. Worth stating rather than leaving
  implicit, since row presence is exactly the reading the first draft
  of this entry got wrong in the other direction (the correction
  above).

  When set, the harness skips "Install Claude Code" and "Run the
  agent" entirely and reports the fixture matching the context
  response's own `root_tag` field — a field `fetch_context/2` already
  returns (`Catapult.Delivery.Dispatch`) — as a `:success` outcome,
  `credential_used: "stub"` (a plain string column,
  `DispatchRun.credential_used`; no enum to widen). **Keyed by
  `root_tag`, not by tier**, because `ContextAssembly.root_tag/1`
  already collapses every reviewed tier's root_tag to the literal
  `"review"` — the nine fixtures already checked into
  `test/catapult/generation/fixtures/toy_seed/` (one per generation
  tier the toy chain exercises, plus the one shared
  `review_approve.xml`) carry the right content but not, for five of
  the nine, a filename matching the `root_tag` they need to be looked
  up by (design review correction — the first draft of this entry
  claimed otherwise, and a dev pass told so would have pushed them
  under their existing names and missed the lookup on exactly the tier
  `ToySeedChainLiveTest` dispatches first). The mapping, checked against
  each tier's own `root_tag:` in `bundles/default/tiers/*.yaml` and
  each fixture's own root element:

  | fixture (as checked in) | its `root_tag` |
  | --- | --- |
  | `comparch.xml` | `comparch` |
  | `feature_expansion.xml` | `feature-expansion` |
  | `impl.xml` | `implementation` |
  | `ref.xml` | `reference` |
  | `requirements.xml` | `requirements` |
  | `review_approve.xml` | `review` |
  | `subcomparch.xml` | `subcomparch` |
  | `sysarch.xml` | `sysarch` |
  | `vocab.xml` | `vocab-entry` |

  `ToySeed.reset_files/0` pushes each fixture's *content* to the bound
  repo under a path named for its `root_tag` from this table — not
  under the fixture's own checked-in filename —
  `.catapult-stub/<root_tag>.xml` (`systems/delivery.md`'s companion
  entry names the path convention), never under `docs/raft/**` — the
  raft's own registered discovery directory
  (`Catapult.Delivery.intake_raft/2`) — so pushed stub content is never
  mistaken for raft input. `impl_ui`, `impl_backend` and `impl_screen`
  all declare `root_tag: implementation`, so `impl.xml`'s single push to
  `.catapult-stub/implementation.xml` already serves every one of the
  three — the same collapse that motivates keying by `root_tag` at all
  applies a second time inside `impl`, not only across the review
  tiers.

  **The harness gains a checkout step it does not have today, or the
  fixture above is unreachable** (design review finding, ORC-223).
  `catapult-dispatch.yml`'s recorded steps — mint an OIDC token, fetch
  the rendered context, install Claude Code, run the agent, report the
  result — never check out the bound repo, so nothing on the runner's
  filesystem holds the `.catapult-stub/<root_tag>.xml` content
  `ToySeed.reset_files/0` just pushed there: a stub-mode run's own
  report step would be reading an empty workspace. Author's decision:
  the harness runs `actions/checkout` against the repo the workflow is
  already executing in, as a new step positioned **before** "Fetch the
  rendered context" — early enough that the fixture is on disk before
  "Report the result" reads it, and ahead of the fetch because
  `actions/checkout` cleans the workspace before checking out (its own
  `clean` input, default true): placed after the fetch it deletes the
  `context.json` that fetch just wrote there, which is exactly how
  every dispatch in live-suite run 24 died, with
  `FileNotFoundError: context.json` at the report step before it could
  read anything. Anything this job writes into the workspace lands
  after this step. Not conditioned on `stub_mode` at all, because a
  non-stub run needs the identical working copy for its own commit step
  once dispatched runs write to branches (the "runner's checkout is the
  working copy" bullet at the top of this doc already assumes one
  exists). The step earns its place beyond stub mode for that reason,
  not only stub mode's. No new workflow input: the default checkout ref
  is the branch `workflow_dispatch` fired against, the same branch
  `reset_repo/2` — the only writer to this repo while a test project is
  active (`systems/delivery.md`'s "at most one active" invariant) — just
  committed the fixture to, so there is no second writer for this step
  to race.

  **Considered and rejected: returning the stub body inside the context
  response instead of pushing it to the repo**, which would have
  removed the fixture push, this checkout step and the
  `.catapult-stub/` namespace together. Rejected because the checkout
  is not a cost stub mode introduces — a real run needs one regardless
  — so a checkout-free retrieval path built for stub mode alone would
  leave two mechanisms doing the one thing the harness needs on every
  dispatch, stubbed or not.

  This is what the poll-deadline entry below means by "a checkout plus
  a report call": until this entry, that phrase named a step the
  recorded workflow did not actually have.
- **`ToySeedChainLiveTest`'s poll deadline has to fit inside ExUnit's
  own per-test timeout, and today it doesn't** (ORC-223, widened by
  ORC-225 — `systems/delivery.md`'s quiescence entry states what the
  test now waits for). `@poll_deadline` was `:timer.minutes(15)`; the
  test carried no `@tag timeout:`, so ExUnit's own default (60s) killed
  the test process first, on every run, before the deadline it wrote
  for itself ever had a chance to fire — the timeout observed in
  live-suite run 23. `after release!(...)` never ran on that kill,
  which is the reason the incident's test project stayed `:active`
  after the suite had already given up. Two figures need setting
  together, not one, and ORC-225 resets both again for a wider reason
  than ORC-223's own: under the stub-mode default this same entry
  restores above, a dispatched run skips the two steps ("Install Claude
  Code", "Run the agent") that the 15-minute figure was sized for, and
  reaches terminal in however long a GitHub-hosted runner takes to
  queue, start and run a checkout plus a report call — order of tens of
  seconds, not minutes, for one dispatch. ORC-225 widens what the test
  waits for from "one dispatch reaches terminal" to "the run set reaches
  quiescence" (`systems/delivery.md`'s entry — a quiet-since duration
  exceeding one full `GENERATION_SWEEP_INTERVAL_MS` tick plus a
  `@poll_interval` margin for that tick's own dispatch to land as a
  visible row, not a fixed poll count), each round
  bounded by one dispatch's own tens-of-seconds runner latency plus up
  to one `GENERATION_SWEEP_INTERVAL_MS` (default `10000`) tick, plus the
  `@poll_interval` (5s) row-visibility margin, for the sweeper to notice
  the round before it, with the 15-second quiescence window charged once
  per round. Under ORC-225 alone this cost up to two sequential rounds
  — a tick-0 draft round and the review round it unblocks — because
  nothing resolved the gate the second round left open. ORC-230 (below)
  widens the round count past two and drops the 15-second quiescence
  tail from the arithmetic entirely: once an actor exists to approve
  drafts, the suite has no reason to stop at two rounds rather than
  however many the raft's downward cascade actually takes, and once
  `remaining` (`systems/delivery.md`'s entry) reads readiness directly,
  `Catapult.Generation.Quiescence`'s own quiet-since margin has nothing
  left to hedge and retires with it. `TodoAppProofLiveTest` is
  unaffected: it dispatches with `stub_mode: false` and does not poll.
- **ORC-230 gives the boundary suite an actor, and the whole walk runs
  on every boundary — there is no shallower suite.** `ToySeedChainLiveTest`
  (tag `:live`) is the only toy-seed live test, and it does not stop at
  the round that first reaches quiescence. Its poll loop alternates:
  poll `runs/2` (`systems/delivery.md`'s widened entry) until it
  reports `remaining: 0`, call `Provisioning.approve_drafts/2` once, and
  poll again — stopping only when a full cycle leaves `remaining` at
  zero **and** `approve_drafts/2` reports zero approvals, which together
  mean nothing is dispatchable, nothing is running, and nothing is
  sitting `:drafted` waiting to be approved. This is deliberate, not a
  missed opportunity to cap it: the boundary pass exists to be as close
  to production as the toy chain gets without a model in the loop, so it
  runs the whole chain agentless, and a real-model run confirms the
  production case separately and strictly afterward — sequencing the
  two within one boundary run is its own design, not this ticket's
  (`systems/delivery.md`'s ORC-216 entry is why they cannot run
  concurrently regardless: at most one `:active` test project). A round
  cap, or a second, shallower test beside a full-walk one, would be
  sizing the every-milestone suite to a depth nobody has measured —
  the position design review rejected in favor of this one.

- **The assertion is that an approval produced a new dispatch, which a
  bare approval count cannot tell you.** `approve_drafts/2` dispatches
  `ApproveDraft` directly (`systems/delivery.md`'s corrected entry — it
  no longer goes through a ticket's gate at all), so unlike the
  ticket-gate design this replaces, one reported approval already means
  one node crossed into `:approved`; there is no second call needed
  per node. What still isn't proof on its own is that the approval
  *did* anything: a leaf tier's own approval unblocks nothing further
  downstream. So the suite tracks `run_key`s rather than the approval
  count alone: every `runs/2` poll is diffed against the previous one,
  and the assertion is that at least one `approve_drafts/2` call
  reporting an approval is followed, on a later poll, by a `run_key`
  that was not present before — a new dispatch, which only a node
  crossing into `:approved` (and so becoming ready for whatever tier
  reads it) can produce. `Provisioning` exposes no node-status read, so
  a new run is the fact the suite can actually observe; asserting on it
  rather than on the approval count is what makes the assertion prove
  the mechanism advanced the walk rather than merely that a compare-
  and-swap succeeded.

- **The deadline is sized from the walk's own measured depth, not left
  a bare "generous" constant.** `bundles/default/tiers/*.yaml`'s
  downward-cascade graph fixes the walk's *depth* — how many sequential
  approve-then-dispatch rounds a complete walk takes — because every
  join-target tier (`comp`, `subcomp`, `screen_coll`, `ui_coll` and the
  rest) mints straight to `:approved` at mint time (`Extraction.mints/4`)
  rather than needing its own approval, so only a tier reached through a
  `self.parent`/`all.<tier>`-style walk requiring `:approved` costs a
  round. Tracing the toy raft's longest such chain from `feature_expansion`
  gives exactly **three** gate-bearing tiers: `feature_expansion` →
  `requirements` → `sysarch` — every tier past `sysarch` (`comp`,
  `comparch`, `subcomp`, `subcomparch`/`impl_backend` on the backend
  side; `frontend_sysarch` and whatever it mints on the front-end side)
  reads either a join-target's mint-time `:approved` or `sysarch`'s own
  approval, never a fourth tier's. This is depth, not breadth: `per(comp)`/
  `child_of` fan-out still depends on what a draft itself mints, which
  the tier bundle alone cannot predict, so the number of *nodes*
  dispatched within a round stays unmeasured and the deadline still
  needs headroom for it — depth fixes how many times the suite must
  wait for an approval, not how much work each wait costs.

  Each round costs two dispatch waves (a tier's own draft, then its
  review) at the ORC-225 entry's own per-wave ceiling — one dispatch's
  tens-of-seconds runner latency under `stub_mode`, plus one
  `GENERATION_SWEEP_INTERVAL_MS` (10s) tick, plus the `@poll_interval`
  (5s) margin, call it 90 seconds generously — plus the
  `approve_drafts/2` call and the next poll that observes its effect.
  Three rounds at roughly three minutes apiece is a 9-minute floor; the
  unmeasured breadth above (several tiers' worth of siblings queueing
  behind Oban's `generation_dispatch` concurrency of 5, and whatever
  GitHub Actions' own runner queue adds under load) is the headroom a
  bare depth-based figure would not cover. `@poll_deadline` widens to
  `:timer.minutes(15)` — the 9-minute floor plus that headroom — and
  `@tag timeout: :timer.minutes(17)`, wider still so the assertion
  failure path (a real `flunk/1`) is what ends the test on a genuine
  timeout, never ExUnit's own kill, for the identical `after`-block
  reason ORC-225's own entry above already gives.

  What changes on top of the number is the failure path: a `flunk/1`
  on timeout reports the tier set that ran, every node
  `Store.list_nodes/2` still shows `:drafted` project-wide, how many
  `approve_drafts/2` calls fired and how many approvals each reported,
  and the per-run `duration_ms` `systems/delivery.md`'s widened `runs/2`
  now carries — enough to tell a genuinely stuck graph from a slow one
  without re-running it by hand, and the thing that stands against the
  pressure a tight, unexplained timeout creates to shorten the suite
  back down.

- **This is what finally exercises most of `@root_tag_fixtures`'s
  twenty previously-unreached stubs — sixteen of the twenty, not all
  of them.** Nothing before ORC-230 dispatched past two rounds, so
  twenty of the twenty-two fixtures ORC-225 built existed for tiers no
  run had ever reached. A `ToySeedChainLiveTest` run that reaches
  `remaining == 0` with zero approvals pending is the first observed
  evidence that every dispatchable `root_tag` the toy raft's downward
  cascade can actually reach resolves against its stub, rather than an
  assumed one. **Four stay unreached regardless**, for a reason outside
  this ticket: `bundles/default/edges/decomposition.yaml`'s
  `frontend_sysarch → ui_coll`/`→ screen_coll` `declared_in` paths name
  underscored element segments (`ui_collections`, `screen_collections`)
  that `bundles/default/schemas/frontend_sysarch.xsd` itself requires
  to be hyphenated (`ui-collections`, `screen-collections`) — every
  grammar-valid draft uses the hyphenated form, `Extraction.descend/2`
  matches child element names by exact string equality with no
  hyphen/underscore normalization, and the two never meet. `ui_coll`
  and `screen_coll` never mint for any project on the shipped bundle,
  so `ui_collarch`, `screen_collarch`, `ui_subcomparch` and
  `screen_subcomparch` — four of the `@root_tag_fixtures` keys — never
  get a node to dispatch against. This is bundle content
  (`bundles/**`), not a doc this pass may amend or a file this pass may
  fix, and it costs the walk no *round*: nothing downstream of
  `sysarch` needs a fourth approval either way (this entry's own
  deadline derivation above), so the four unreached fixtures change
  what the walk covers, not how long it takes to finish covering it.

- **Two stale moduledocs are corrected in the same change**, both
  design-owned prose sitting in dev-owned test files, so design records
  the finished shape here and dev writes it.
  `test/catapult/generation/todo_app_proof_live_test.exs`'s own
  comparison sentence — "unlike `ToySeedChainLiveTest`, which dispatches
  exactly one tier and can afford to poll a single run to a terminal
  status inside one test's deadline" — was already false under ORC-225
  and is doubly so now: there is no round count left to compare against,
  since `ToySeedChainLiveTest` walks the raft's full downward cascade
  with no cap. The sentence drops the comparison rather than restating
  it with a new number — `TodoAppProofLiveTest` stops at provisioning
  because its own middle spans hours or days of human review, which is
  reason enough on its own and needs no contrast to the other test's
  poll shape. `test/catapult/generation/toy_seed_chain_live_test.exs`'s
  own "What this proves for real" paragraph names `feature_expansion`
  alone as the dispatch this test proves, a claim its very next
  paragraph already supersedes even before this ticket. It states
  instead that this test proves a full downward-cascade walk of the toy
  raft against real GitHub Actions runs — `feature_expansion` as the
  walk's first dispatch, `Provisioning.approve_drafts/2` approving every
  drafted node the walk produces, and the tier set the run actually
  reached, not a fixed one, as what a passing run demonstrates.

- **A dispatch can beat provisioning itself, not only beat a release**
  (ORC-224 — `systems/delivery.md`'s companion entry states the
  mechanism and the state-machine change). ORC-216's own lifecycle
  guard closed the window after a test project stops being current;
  live-suite run 25 found the window *before* it starts current: the
  sweeper's tick interval runs independently of
  `Provisioning.reset_and_intake/2`'s own write — one Contents-API
  `PUT` per entry in the caller's `files` map
  (`HostPort.Actions.put_all_files/2`; seventeen of them for
  `ToySeed.reset_files/0`'s own map, the live suite's own seed) — so a
  tick landing inside it dispatches against a repo missing whichever
  piece hasn't landed yet: the workflow file, a stub, or the raft.
  Runs 866–869 dispatched at heads `d2e0f8cc` and `37733f90`, by which
  point eight or nine of the nine stub fixtures had already pushed —
  what was still missing was the workflow file and the seven raft
  docs. The missing workflow file is what the dispatched runs
  actually hit: they executed the pre-#144 harness and died at the
  report step with
  `FileNotFoundError: context.json`, one to two seconds before the fix
  reached the repo. `sweepable_project?/1`'s own body
  (`Catapult.Delivery.Store.sweepable_project?/1`) is already a
  catch-all — `%Project{test_project_state: :active} -> true`,
  `%Project{} -> false` — so a `:provisioning` row falls to the
  `false` clause with no edit to the function; the only code this
  needs is `:provisioning` joining the schema's own `Ecto.Enum,
  values:` list (`systems/delivery.md`'s entry above already covers
  this, and without it the row fails to load regardless). That is
  also why neither sweep site needed a second fix: both
  `Sweeper.sweep_project/2` and `DispatchWorker`'s own
  `still_sweepable/1` re-validation already read `sweepable_project?/1`
  rather than holding a cached readiness bit, so widening the schema's
  value list is the whole of it.
- **Fixture coverage is total across `@root_tag_fixtures`'s key set:
  every root_tag a dispatchable tier can produce, not only the
  root_tags one toy-chain run happens to exercise** (ORC-225 — live-suite
  run 26,
  [33930186206](https://github.com/SwaggerAllen/catapult/actions/runs/33930186206),
  the first run to clear the `:provisioning` gate above and immediately
  expose this one: four of its five dispatched runs died on a bare
  `FileNotFoundError: .catapult-stub/<root_tag>.xml`, one per root_tag
  `Catapult.ToySeed.@root_tag_fixtures` had never been given). The map's
  key set is exactly the 22 values `ContextAssembly.root_tag/1` can
  return across every dispatchable tier in `bundles/default/tiers/*.yaml`
  — the 21 distinct `draft.root_tag`s the 23 generation tiers declare
  (the three `impl_*` tiers collapsing to the one `implementation`),
  plus the single literal `"review"` every review tier collapses to:
  `bug-fix-plan`, `comparch`, `feature-expansion`, `feature-request-plan`,
  `frontend_sysarch`, `implementation`, `journeys`, `non-goals`,
  `propagation-plan`, `reference`, `refactor-plan`, `requirements`,
  `review`, `screen_collarch`, `screen_subcomparch`, `screens`,
  `subcomparch`, `sysarch`, `ui_collarch`, `ui_subcomparch`,
  `upward-propagation-plan`, `vocab-entry`.

  A missing key is not a gap the live suite tolerates by exercising a
  narrower chain — the entry above already keys the lookup by `root_tag`
  rather than by tier precisely so one fixture serves every tier sharing
  a root_tag, and that same collapse means a single missing key fails
  every tier that shares it, not just one.

  Each fixture this map is still missing is a hand-authored XML document
  whose root element is its `root_tag` and which validates against the
  schema its own tier's `grammar:` names in `bundles/default/schemas/
  *.xsd` — not an empty placeholder, since the plane validates a
  reported body against the tier's grammar exactly as it would a real
  model response, the schema a tier's own `draft:` block already commits
  it to regardless of who produces the body.

  The filename convention has two cases, not one, because a `root_tag`
  is not always owned by a single tier: of the 21 distinct generation
  `root_tag`s, twenty are declared by exactly one tier and the
  twenty-first, `implementation`, is collapsed across the three
  `impl_*` tiers — twenty single-tier `root_tag`s and two collapsed
  ones (`implementation`, plus the eighteen review tiers' shared
  `review`). For the twenty
  `root_tag`s each declared by exactly one tier, the filename is that
  tier's own bundle YAML basename
  with `.xml` in place of `.yaml` (`bug_fix_plan.yaml` →
  `bug_fix_plan.xml`, `downward_propagation_plan.yaml` →
  `downward_propagation_plan.xml`, and so on for the rest) — a filename
  namespace that tracks the bundle's own tier names, which is why it was
  never made to equal the differently-punctuated `root_tag` namespace in
  the first place; `@root_tag_fixtures`'s value side is exactly what
  translates between the two. For the two collapsed `root_tag`s —
  `implementation` (`impl_backend.yaml`, `impl_screen.yaml`,
  `impl_ui.yaml` all declare it) and `review` (all eighteen `*_review
  .yaml` tiers declare it) — no single tier basename applies, so the
  filename names the `root_tag` rather than any one owning tier:
  `impl.xml` and `review_approve.xml`, the two names already checked in,
  are read as exactly that rather than as derived from a tier that does
  not exist.
- **The "Read the stub fixture" step must itself produce a typed
  `outcome.json` when the fixture is missing, not fall through to
  "Report the result"'s own generic fallback** (ORC-225, the same run
  26 incident above). Today the step's `open()` call has no guard: a
  missing `.catapult-stub/<root_tag>.xml` raises, the step's `python3`
  process dies before writing anything, and "Report the result" (`if:
  always()`) runs anyway, finds no `outcome.json`, and reports
  `{"status": "other_failure", "reason": "run-agent step produced no
  outcome.json"}` — a reason naming a step ("Run the agent") that stub
  mode's own `if:` condition skips entirely, so the plane's one record
  of *why* the dispatch failed points a reader at code that never ran.
  The step catches the missing-file case itself and writes the same
  `other_failure` shape directly: `{"status": "other_failure", "reason":
  "no stub fixture for root_tag '<root_tag>' at
  .catapult-stub/<root_tag>.xml", "credential_used": "stub"}` — naming
  the root_tag and the exact path it looked for, the two facts a reader
  needs to find the gap the entry above closes, and the two facts the
  generic fallback has no way to know. This is `other_failure`, not a
  new `DispatchRun.outcome` value: a missing fixture is exactly as
  terminal and exactly as non-retryable as any other `other_failure` —
  nothing in the credential-failover path branches on outcome kind
  beyond `limit_class_failure` versus everything else — so the
  distinction lives in the `reason` string, which is free text already,
  rather than in a fourth enum value with a migration behind it.
  "Report the result"'s own fallback keeps its present meaning after
  this change rather than gaining a new one: once the read step cannot
  fail past this point without writing something, "no outcome.json"
  means what it always claimed to — the body-producing step (real or
  stubbed) crashed somewhere the harness gave it no chance to report.

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
