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
  only its identity** (ORC-117). Building a mint entry
  already means resolving the target tier's own declaration out of
  `chain`; that same lookup also reads whether the target
  declares a `draft:` block and carries the answer on the entry
  (`:approved` for a join target, `:absent` otherwise), rather than
  the reducer inferring it from bundle content it isn't supposed to
  read. The decision this answers to — what a join target's status
  means — is `systems/engine.md`'s; this entry only records that the
  computation sits here. The value written here is necessary but not
  sufficient: readiness also asks whether the node that minted a join
  target is itself settled, recursively (`systems/engine.md`).
- **The gate `Extraction` applies is source-identity, not `edge.type`
  — and it cuts out more than the `dependency`/`policy_application`
  family** (ORC-235).
  `Catapult.Generation.CommitPath.commit_draft/3` feeds `mints:` from
  `Extraction.mints/4` (`edge.type == "fanout"`) and `edges:` from
  `Extraction.references/5` (`edge.type == "reference"`, which also
  covers `fulfills` — `type: reference` under the hood), and nothing
  else feeds either field. Both functions gate every candidate
  instance on two conditions together — `instance.source == tier_name`
  *and* `self_sourced_path`/`self_sourced_attr_path` requiring
  `declared_in`'s own leading segment to equal that same `tier_name`
  — before extracting it at all, and the first of the two is
  **type-independent**. `Extraction`'s own moduledoc frames the gap it
  leaves as "a `declared_in` path whose leading tier differs from the
  tier being committed," naming only the second condition, when the
  first already excludes a whole further class on its own: for an
  instance whose `source` names a join-target node type — one that
  never commits a `DraftCommitted` under its own name at all — no
  choice of `tier_name` can satisfy `source == tier_name`, so the
  instance is unextractable regardless of where `declared_in` points
  or what the edge's type is. The two conditions coincide in
  `bundles/default` for every `<arch> → ref` citation — a tier names
  itself as both the edge's `source` and `declared_in`'s leading
  segment — which is exactly why that shape reads as "the" shape and
  the join-target-`source` class went unnamed. Fifteen `reference`/
  `fulfills` instances exist in `bundles/default`, and six fall into
  the unnamed class, each because its `source` names a join-target
  node type: `fulfills comp → resp`
  (`source: comp`, declared in `sysarch`), `fulfills screen_coll →
  screen` (`source: screen_coll`, declared in `frontend_sysarch`),
  `reference journey → screen` (`source: journey`, declared in
  `screens`), `reference resp → journey` and `reference resp →
  screen` (`source: resp`, both declared in `requirements`), and
  `reference screen_coll → journey` (`source: screen_coll`, declared
  in `screen_collarch`). Only the nine `<arch> → ref` instances
  (`comparch`, `subcomparch`, `impl_backend`, `ui_collarch`,
  `ui_subcomparch`, `impl_ui`, `screen_collarch`, `screen_subcomparch`,
  `impl_screen`) satisfy both conditions and are extracted.

  Every `type: dependency` instance `bundles/default` declares — seven
  in total: `comp↔comp`, `subcomp↔subcomp`, `ui_coll↔ui_coll`,
  `ui_subcomp↔ui_subcomp`, `screen_coll↔screen_coll`,
  `screen_subcomp↔screen_subcomp` and `ui_coll → design_system` — fails
  the identical `source`-identity gate, for the identical reason: none
  of `comp`, `subcomp`, `ui_coll`, `ui_subcomp`, `screen_coll` or
  `screen_subcomp` ever commits a `DraftCommitted` of its own. So every
  context walk reading one of these (`comparch`'s, `subcomparch`'s,
  `ui_collarch`'s, `ui_subcomparch`'s, `screen_collarch`'s and
  `screen_subcomparch`'s own `dependency` entries — `impl_backend`,
  `impl_ui` and `impl_screen` walk the identical sibling-dependency
  entry their own `*subcomparch`/`*collarch` counterpart declares
  (`self.parent.dependency -> subcomp.handle.fragments[pubapi]` and the
  `ui_subcomp`/`screen_subcomp` equivalents), not a different one, so
  the same emptiness reaches them too — and `comparch`'s and
  `screen_collarch`'s own `fulfills` walks too) resolves to `[]` and
  stays vacuously satisfied regardless of tier ordering.
  `systems/platform_content.md`'s ORC-232 entry records the
  `subcomp↔subcomp` instance of this as live and broken; the same
  `source`-identity gate excludes every instance above, not only the
  ones typed `dependency`.

  The two `type: policy_application` instances
  (`bundles/default/edges/policy_application.yaml:24,35`) are a third
  shape, not a second instance of the class above. Their `declared_in`
  values are `policy.structural` and `policy.required` — not a
  `<tier>.draft....` path at all, so `self_sourced_path/2` has nothing
  to navigate: it returns `:skip` on the shape mismatch before
  `instance.source == tier_name` is even asked. Both are set at mint
  time off a marker the minting draft itself carries (a `<policy>`
  element's `<structural/>` vs. `<required>` child — that edge file's
  own comments), never extracted from any committing tier's draft body
  at all.

  ORC-235 is tier ordering; this is extraction coverage, and it is a
  ticket of its own. **Closing it takes two separate mechanisms, not
  one:**

  - Reading an edge instance declared by a tier that is not its own
    `source` — the harder case `Extraction`'s own moduledoc already
    names, needing per-edge-type knowledge of which child element
    names source vs. target that the generic self-sourced navigator
    cannot infer. This is what the seven `dependency` instances and the
    six `reference`/`fulfills` instances above both need, and it is
    also what relocating `uses_shapes`/`calls`/`renders` to
    `frontend_sysarch`'s own draft (`systems/platform_content.md`'s
    ORC-235 entry, below) still needs afterward: their `source` is
    `ui_coll`/`screen_coll` whether declared in `ui_collarch`/
    `screen_collarch` or in `frontend_sysarch`, and neither tier name
    is the edge's `source` either way, so `instance.source ==
    tier_name` fails identically before and after the relocation.
    These three are not "correctly declared
    and inert until extraction adds a type" — no relocation makes them
    extractable, because the gate they fail is never edge-type.
  - Synthesizing an edge instance at fanout-mint time from a marker the
    minting draft itself carries, with no `declared_in` path to
    navigate at all — what both `policy_application` instances need
    instead, since their `declared_in` names no tier's draft body for
    any navigator to read.

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
  system stands up** (ORC-9): `systems
  /foundation.md` records where context-fetch and result-report are
  actually served — a second path on the existing health listener,
  composed from generation's and delivery's `api_surface/0`
  declarations, ahead of the general router that will eventually
  absorb them — and why it isn't dashboard's router yet. The handler
  logic (OIDC validation, run correlation, context/result payloads)
  stays here and in delivery's file map; foundation owns only the
  listener it answers on.
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
- **Catapult owns its generation runner harness, built here** (ORC-215).
  v5 §1.2's third reason — "one execution path... extended rather
  than duplicated" — is no mandate to consume orchestration's own
  harness as a pinned dependency, and `docs/non-goals.md`'s
  no-self-bootstrap entry does not support one: §1.2's reason is
  proven-*pattern*, not proven-*code*, and no-self-bootstrap is about
  consuming the shared components (`components/**`) as an ordinary
  library user — a different question from which repo authors a
  `workflow_dispatch` file this repo already pushes into a bound
  project's own repo (`systems/delivery.md`'s ORC-10 entry).
  Orchestration builds Catapult; it participates in none of Catapult's
  own mechanisms, this one included.

  The contract is v5 §7.12.1's (fetch rendered context, run agent,
  commit, report) and so is the seam: the run-agent step is the only
  implementation-specific piece, so a second agent implementation is a
  bindings entry, never a rewrite of the steps around it (the entry
  below settles which one).

  **Where the run-agent step's code lives: inline in the dispatched
  workflow content, the same fixture-content mechanism `reset_repo/2`
  pushes into a bound repo** (`systems/delivery.md`'s ORC-10 entry) —
  no new mechanism. A composite action under this repo's own
  `.github/actions/**`, referenced cross-repo from every bound
  project's workflow (`uses: <this repo>/…@ref`), would tie every
  dispatched run forever to this repo's own git history instead of to
  the reviewed commit its own bound-repo workflow file already pins —
  the mirror image of the coupling §1.2's reason closes off, one hop
  later — and `.github/actions/**` has no owner in this repo
  (`systems/README.md`'s unowned-paths list doesn't carry it), so
  creating one is the author's call, not a ticket's. A script fetched
  from the plane at run time would give the plane a live code-serving
  role beyond its two settled dispatch endpoints (context-fetch,
  result-report), a new authenticated surface bought for no protocol
  gain, and it ties an in-flight run's behavior to whatever the
  plane's *current* deploy happens to serve rather than to the commit
  its own workflow file pinned when the run started.

  **The classified outcome vocabulary is
  `Catapult.Delivery.ResultHandler`'s** — `payload().status` is the
  closed `:success | :limit_class_failure | :other_failure` union, and
  `Catapult.Generation.CommitPath`/`Catapult.Delivery.Dispatch` branch
  on it; the harness computes which one applies. `claude -p
  --output-format json`'s terminal
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
  three-way split, and the harness implements it in that
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
  `other_failure` for that reason.

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

  **Failover is live, not deferred to a future date**:
  `HostPort.request`'s `credential_name` is the bindings tunable's
  full ordered pair, not its head (`systems/delivery.md`'s own entry),
  and `Actions.dispatch_run/1` sends it whole — the contract was built
  for two.
- **The bindings entry is `:generation`, one kind in the same kind →
  runtime map v5 §7.10 already describes for ticket-delivery agent
  kinds** (design, dev, reconcile, validation, retro, setup — Phase
  7), not a second, generation-only mechanism:
  Catapult's own chain has exactly one kind, and reusing the one
  map is what makes "supporting a second agent implementation is a new
  bindings entry and zero protocol or bundle change" (v5 §7.10) literal
  rather than aspirational the moment Phase 7 lands its own kinds
  beside this one. Per-tier executor-profile routing (model, effort,
  harness requirements) stays Target — one runtime serves every
  generation dispatch project-wide, never per tier.

  `Catapult.Generation.cast_credential_order/1`'s closed two-name set
  (`claude_code_oauth_token`, `anthropic_api_key`) is Claude-Code-
  specific and lives in bindings, keyed by whichever runtime is bound
  to the `:generation` kind — a second implementation's own credential
  names arrive as a new bindings entry, never a rewrite of this
  validator. Until the general bindings-as-plane-entities store
  (v5 §7.10) exists, the credential-order and kind→runtime tunables
  carry the "accepted-for-now" env-var-config shape
  `Catapult.Generation`'s own `config/0` uses for exactly this reason,
  keyed by implementation rather than hardcoded to Claude Code's two
  names — a fact that holds however long the real store takes to land.
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
  **the count is derived from the log, never held** (ORC-9). Every
  limit-class run failure is its own event, on the scope's node, in
  generation's own `events/0`, landing in the same per-project stream
  engine's `draft_committed` already writes to — one aggregate per
  project, not one per system. The derivation walks the log backward
  from now to
  the node's most recent `draft_committed` (or the log's start, if
  none), counting limit-class failure events since. `Blocked` fires
  once that count repeats past one. This satisfies the invariant
  rather than contradicting it: "no memory across dispatches" is a
  claim about the *dispatched run*, which still re-renders its context
  walk and starts clean every time — the count lives once, in the
  plane's log, the same place every other derived answer in this
  system already lives (`systems/engine.md`'s "no in-memory
  pending-set" doctrine, one layer down), not in a table row or an
  Oban attempt counter. An Oban attempt counter is the wrong home for
  a concrete reason: an Oban attempt count is scoped to one
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

  Two decisions are recorded where they would be edited rather than
  here: `since_sequence` is caller-supplied rather than computed
  inside `execute/2` (`Catapult.Engine.Commands.DeclineGate`, on this
  system's purity floor), and the reset boundary is neither
  `DraftCommitted` nor a position in the resolution sequence —
  `CommentFeedback`'s own moduledoc names both alternatives, their
  failure modes, and the shipped bundle that breaks the second.

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

  The assertion most likely to be quietly skipped is bucketing, not
  occurrence: the test must post its comment
  against one named node, decline that node's gate, and assert that
  the *regenerated context for that node* —
  `ContextAssembly.build_variables/5`'s `feedback` entry — carries the
  comment's body, **and** that a sibling node minted off the same
  parent, never declined, regenerates with no such feedback.
  `CommentFeedback.since_last_resolution/2` is a per-`node_id` fold
  (`systems/engine.md`); a test asserting only "regeneration happened"
  cannot tell that fold apart from one bucketed by project or by gate
  — which is exactly the class of bug this same fold's history already
  produced once (the position-based `since_sequence` inference broke
  the moment a workflow declared more than one gate). Two nodes, one
  declined, is the cheapest fixture that makes the two hypotheses
  disagree, and the reasoning is orchestration's own: assert the thing
  that would go wrong, not a side effect every wrong implementation
  produces too.

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
  prompt reflects an `input.<role>` document, offline** (ORC-107 —
  see the entry above for the mechanism). `ContextResolver.resolve/2`
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
  evidence, not a prop. What the toy seed already
  proves — the graph-native chain, `self`/`self.parent`/`all.*` walks,
  every tier reachable from `comparch` down through `impl`, at least
  one instance of every edge type, which is the whole of what
  `ContextResolver` resolves — needs no input-role content; the
  input-role assertion above is additive coverage for the direct-read
  path, not a replacement for it.

- **The sweeper honours the test-project lifecycle, at both sites
  that can dispatch** (`systems/delivery.md`'s ORC-216 entry).
  `Sweeper.sweep_project/2` skips a project id `Catapult.Delivery
  .sweepable_project?/1` answers `false` for, checked once per project
  per tick rather than scope-by-scope after the fact: a released or
  deleted test project's whole tier loop is skipped outright, upstream
  of the tier walk. That alone would leave a gap: a job already
  enqueued on the tick before a project releases would dispatch after
  it if `DispatchWorker.perform/1`'s own re-validation checked only
  `still_ready` and `not_blocked` (`DispatchWorker`'s own moduledoc,
  §7.1's validate-or-revert discipline). `sweepable_project?/1` is a
  third check there, run alongside those two. `sweepable_project?/1`
  answers `true` for a project id naming no row in `delivery_projects`
  at all (an ordinary, non-test project) and for a test project whose
  recorded state is `:active`; `false` for `:provisioning`, `:released`
  or `:deleted` (ORC-224, below: a test project reads unsweepable from
  the moment it is minted, not only once released or deleted).
  This is a read, not new sweeper state — neither process holds any
  memory of what it last enqueued, and `Catapult.Delivery` stays the
  one state of record for the lifecycle.

  **The sweep's own project enumeration has to reach a project bound
  but not yet drafting, or a freshly provisioned test project is never
  swept at all.** `Catapult.Engine.Store.list_project_ids/0` alone —
  every project id with a node, a flow or an active bundle version —
  misses a project the provisioning surface has only just minted,
  bound and intake-pinned, which has none of the three until its first
  tier ever drafts. `feature_expansion`'s own singleton candidate is
  organically ready the moment a project id exists at all (this
  file's own ORC-107 entry), so readiness is never the missing piece —
  a sweep walking only that list never asks the question for a
  project id it has not yet heard of. `Sweeper.sweep/0` walks the
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
  re-checked. `DispatchWorker.perform/1`'s fourth check is placed
  first — it needs nothing `still_ready/4` and `not_blocked/3` resolve
  a node to answer, only the job's own `project_id`/`tier`/`scope_key`
  args: skip if `delivery_dispatch_runs` already holds a
  **non-terminal** row (`status` in `:dispatched`/`:context_fetched`)
  for this `(project_id, tier, scope_key)`, dispatched within the last
  `dispatch_stale_after_ms` — a `tunable`, the same
  accepted-for-now config-constant shape `sweep_interval_ms` above
  carries (`GENERATION_DISPATCH_STALE_AFTER_MS`, default
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
  open-ended. The run-agent
  step tries up to two credentials, each bounded at the 1800s
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
  always reaches terminal** (ORC-223; this is the "further
  `report_result/2` call for the same `run_key`" that
  `Dispatch.simulate_result/2`'s own comment says "is expected next").
  Only a `:success` report that the grammar rejects stays in flight
  (`Catapult.Delivery.Dispatch`'s own `mark_failure/3` clauses — a
  `:limit_class_failure`/`:other_failure` report always completes);
  the four reasons `report_result/2`
  answers 422 for are exactly the grammar-class failures named in
  `Catapult.Delivery.Dispatch`'s `status_for/1` (`schema_invalid`,
  `malformed_xml`, `root_tag_mismatch`, `schema_not_found`), and none
  of the others (`missing_bearer`, `run_not_found`, a repository/run-id
  mismatch) is fixable by asking the agent to resubmit — the harness
  does not retry those, and a run that fails one of them ends
  non-terminal, which is what the in-flight guard
  above exists to bound regardless of cause.

  On a 422 whose body decodes to one of the four grammar reasons, the
  report step re-invokes the agent — same credential, no failover
  (grammar rejection is not a usage signal), the same 1800s subprocess
  timeout as the original call, prompted with the original rendered
  prompt plus the decoded error appended as a corrective turn — and
  reports again. Bounded at two such retries (three submission attempts
  total): enough for a shape mistake to self-correct without turning
  one rejected report into an open-ended loop. Exhausting the bound
  reports `other_failure` with
  `reason: "grammar_retries_exhausted"`, the same shape every other
  classified outcome already reports in — no new status on
  `DispatchRun`, no new branch in `Dispatch.simulate_result/2`, because
  `other_failure` is already a terminal report.
- **Stub mode is a per-dispatch workflow input, tied to test-project
  state — never a repository variable on the fixture repo** (ORC-223,
  author's decision). A `vars.STUB_MODE` set once on
  `SwaggerAllen/catapult-test` is out-of-band state the plane doesn't
  control per dispatch: it would apply to every future dispatch to that
  repo regardless of which run needs it, and reading it back to know
  whether a given run *was* stubbed would mean a second source of truth
  beside `delivery_dispatch_runs`. A `workflow_dispatch` input costs
  nothing new: `run_key` and `credential_order` already ride this
  channel, and stub mode is exactly the same shape — plane-decided,
  per-dispatch, visible in the run's own log.

  **`stub_mode` is a per-project opt-in, not a fact of being a test
  project**: read off `delivery_projects` row existence alone, it
  would stub every test-project dispatch unconditionally, Waypoint's
  Phase-5 proof run included, defeating the one proof
  `docs/build-plan.md`'s Phase 5 exit criterion needs to run for real.
  Test-project status and stub status are two different questions —
  "is this project reclaimable by the milestone cadence" and "should
  its dispatches skip the model" — and the lifecycle record answers
  both, as two independent fields rather than one collapsed into the
  other: `delivery_projects` carries `stub_mode` (boolean, not null,
  default `true` at the column). `POST /dispatch/test-project` (the
  provisioning surface's mint operation, above) takes an optional
  `stub_mode` field in its JSON body and `Store.mint_test_project/1`
  accepts and persists it; omitting it takes the column default.
  `ToySeedChainLiveTest` sends no such field and
  gets stub dispatches by the column default;
  `TodoAppProofLiveTest` sends `stub_mode: false` and its dispatches run
  the real model. `Catapult.Delivery.stub_mode?/1` reads this column,
  not row presence — and, for a project id holding no `delivery_projects`
  row at all, answers `false`. That is the deliberate mirror of
  `sweepable_project?/1`'s own no-row answer (`true`, above): no row is
  the ordinary-project case for both predicates, but the two questions
  they answer point opposite ways on it — an unbound project is
  trivially sweepable (nothing exempts it) and must never dispatch
  stubbed (nothing opts it in), so the same absence reads as `true` on
  one and `false` on the other.

  When set, the harness skips "Install Claude Code" and "Run the
  agent" entirely and reports the fixture matching the context
  response's own `root_tag` field — a field `fetch_context/2` already
  returns (`Catapult.Delivery.Dispatch`) — as a `:success` outcome,
  `credential_used: "stub"` (a plain string column,
  `DispatchRun.credential_used`; no enum to widen). **Keyed by
  `root_tag`, not by tier**, because `ContextAssembly.root_tag/1`
  already collapses every reviewed tier's root_tag to the literal
  `"review"` — the nine fixtures checked into
  `test/catapult/generation/fixtures/toy_seed/` (one per generation
  tier the toy chain exercises, plus the one shared
  `review_approve.xml`) carry the right content but not, for five of
  the nine, a filename matching the `root_tag` they need to be looked
  up by — pushed under their checked-in names, they would miss the
  lookup on exactly the tier `ToySeedChainLiveTest` dispatches first.
  The mapping, checked against
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

  **The harness has a checkout step, or the fixture above is
  unreachable** (ORC-223). `catapult-dispatch.yml`'s other steps —
  mint an OIDC token, fetch the rendered context, install Claude Code,
  run the agent, report the result — never check out the bound repo,
  so without one nothing on the runner's filesystem holds the
  `.catapult-stub/<root_tag>.xml` content `ToySeed.reset_files/0`
  pushed there: a stub-mode run's own report step would be reading an
  empty workspace. Author's decision: the harness runs
  `actions/checkout` against the repo the workflow is already
  executing in, as a step positioned **before** "Fetch the rendered
  context" — early enough that the fixture is on disk before
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

  **The stub body is pushed to the repo, not returned inside the
  context response.** Returning it would remove the fixture push, this
  checkout step and the `.catapult-stub/` namespace together, but the
  checkout is not a cost stub mode introduces — a real run needs one
  regardless — so a checkout-free retrieval path built for stub mode
  alone would leave two mechanisms doing the one thing the harness
  needs on every dispatch, stubbed or not.

  This checkout is what the poll-deadline entry below means by "a
  checkout plus a report call".
- **`ToySeedChainLiveTest`'s poll deadline has to fit inside ExUnit's
  own per-test timeout, and today it doesn't** (ORC-223, widened by
  ORC-225 and ORC-230 — `systems/delivery.md`'s quiescence entry
  states what the test waits for). A `@poll_deadline` of
  `:timer.minutes(15)` with no `@tag timeout:` let ExUnit's own default
  (60s) kill the test process first, on every run, before the deadline
  it wrote for itself ever had a chance to fire — the timeout observed
  in live-suite run 23. `after release!(...)` never ran on that kill,
  which is the reason the incident's test project stayed `:active`
  after the suite had already given up. Two figures need setting
  together, not one, and the per-dispatch cost they are sized from is
  small: under the stub-mode default above, a dispatched run skips the
  two steps ("Install Claude Code", "Run the agent") that a 15-minute
  figure would be sized for, and reaches terminal in however long a
  GitHub-hosted runner takes to queue, start and run a checkout plus a
  report call — order of tens of seconds, not minutes, for one
  dispatch. What the test waits for is not "one dispatch reaches
  terminal" but the run set reaching `remaining: 0`
  (`systems/delivery.md`'s entry — the plane's own readiness read, not
  a fixed poll count), each round bounded by one dispatch's own
  tens-of-seconds runner latency plus up to one
  `GENERATION_SWEEP_INTERVAL_MS` (default `10000`) tick, plus the
  `@poll_interval` (5s) row-visibility margin, for the sweeper to
  notice the round before it. The round count is not capped: with an
  actor to approve drafts (ORC-230, below), the suite has no reason to
  stop at two rounds — a tick-0 draft round and the review round it
  unblocks, which is where a walk with nothing resolving the gate the
  second round leaves open stalls — rather than however many the
  raft's downward cascade actually takes. And because `remaining`
  reads readiness directly, no quiet-since margin is charged per
  round: `Catapult.Generation.Quiescence`'s quiet-since arithmetic had
  nothing left to hedge and is retired. `TodoAppProofLiveTest` is
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
  two within one boundary run is its own design
  (`systems/delivery.md`'s ORC-216 entry is why they cannot run
  concurrently regardless: at most one `:active` test project). A round
  cap, or a second, shallower test beside a full-walk one, would be
  sizing the every-milestone suite to a depth nobody has measured.

- **The assertion is that an approval produced a new dispatch, which a
  bare approval count cannot tell you.** `approve_drafts/2` dispatches
  `ApproveDraft` directly (`systems/delivery.md`'s entry — it goes
  through no ticket's gate), so one reported approval means one node
  crossed into `:approved`; there is no second call needed per node.
  What isn't proof on its own is that the approval
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
  a bare "generous" constant — but depth only counts *approvals*, and
  the suite's own stop condition (`remaining == 0` and zero approvals
  pending) is priced on waves, not approvals, so the tiers past the
  last approval still have to be counted rather than assumed free.**
  `bundles/default/tiers/*.yaml`'s downward-cascade graph fixes the
  walk's *approval depth* — how many sequential approve-then-dispatch
  rounds a complete walk takes — because every join-target tier
  (`comp`, `subcomp`, `screen_coll`, `ui_coll`, `ui_subcomp`,
  `screen_subcomp` and the rest) has no `draft:` block at all, so
  `Extraction.mint_status/2` returns `:approved` for it at mint time
  rather than `:absent`, and it never dispatches or needs a human (or
  `approve_drafts/2`) to move it. Every context walk this bundle writes
  — `self.parent`, `self.reference`, `all.<tier>` alike — folds the
  identical `status == :approved` requirement over whatever it
  resolves to (`walk_ready?/2`); the two kinds of tier differ only in
  *how* a target reaches `:approved` — instantly at mint for a
  join target, or through its own generate-then-review-then-approve
  cycle for one that carries a `draft:` block — not in whether the
  requirement applies. So a tier costs an **approval round** only when
  it carries a `draft:` block *and* something has to wait on that
  approval to become ready; it still costs **dispatch waves** — a
  draft and a review, each a real run the sweeper has to find and the
  suite has to poll for — whenever it carries a `draft:` block at all,
  approval-gated or not. Tracing the toy raft's longest approval-gated
  chain from `feature_expansion` gives exactly **three** gate-bearing
  tiers: `feature_expansion` → `requirements` → `sysarch` — every tier
  past `sysarch` reads either a join-target's mint-time `:approved` or
  `sysarch`'s own approval, never a fourth tier's *approval*. But most
  of those tiers still carry their own `draft:` block, and the suite's
  loop does not stop at the last approval: it stops at `remaining == 0`
  with nothing left `:drafted`, which means every one of those tiers'
  drafts and reviews still has to dispatch and settle. This is depth,
  not breadth: `per(comp)`/`child_of` fan-out still depends on what a
  draft itself mints, which the tier bundle alone cannot predict, so
  the number of *nodes* dispatched within a wave stays unmeasured and
  the deadline still needs headroom for it — depth fixes how many
  waves the suite must wait through, not how much work each wait
  costs.

  **Under `settled?`/`drained?` (ORC-235), no walk in the raft costs
  more than this floor prices.** `comp` mints at `sysarch`'s
  `DraftCommitted` (`CommitPath`'s own private `commit_draft/3` calls
  `Extraction.mints/4` at commit time, before `sysarch`'s own review or
  approval), but `comparch`'s `self.parent.handle` walk onto it does
  not read that mint-time `:approved` bare: `settled?/2`
  (`systems/engine.md`'s ORC-235 entry) resolves a join target by
  deferring to its minting parent, so `comp` is `settled?` only once
  `sysarch` itself is approved — exactly the wait this entry costs for
  a tier reached through a `draft:`-carrying ancestor: that ancestor's
  own approval, not merely its draft. Tracing every walk in the raft
  against `settled?`/`drained?` finds no site where the derived graph
  waits on more than that: `frontend_sysarch`'s `all.comp.handle`
  (`systems/platform_content.md`'s ORC-235 entry) reduces, via
  `drained?(comp)`'s own recursion through `sysarch`, to the identical
  `sysarch`-approved condition `all.sysarch.handle` already required,
  so the front-end and back-end branches land on the same wave rather
  than one gating the other — the "run alongside each other" claim
  below holds. Nor is there a second, stronger mechanism to price
  separately: `systems/engine.md`'s own ORC-235 entry rejects a
  declared tier sequence and derives order purely from `context:`
  walks, so "no parallelism between tiers" is exactly the per-tier,
  per-walk waiting `settled?`/`drained?` produce — never a blanket
  ordering over tiers with no read relationship between them, which is
  what would be needed to exceed this floor. The same reasoning is why
  `non_goals`, `ref` and `vocab` cost nothing added here:
  `drained?(vocab)` requires every existing vocab entry `settled?`
  rather than reading an empty list as vacuously satisfied, but vocab's
  own draft-and-review (2 waves) lands well before `comparch`'s walk
  onto `all.vocab.handle` is first checked (15-plus minutes in), so
  that wait is already spent by the time anything asks for it.

  A single dispatch wave (a tier's own draft, or its review) costs the
  ORC-225 entry's own per-wave ceiling — one dispatch's tens-of-seconds
  runner latency under `stub_mode`, plus one
  `GENERATION_SWEEP_INTERVAL_MS` (10s) tick, plus the `@poll_interval`
  (5s) margin, call it 90 seconds generously. Not every one of the
  three approval-gated rounds costs the same number of waves, because
  the middle one is not one tier but three run in sequence.
  `feature_expansion`'s approval unlocks `journeys`, `screens` and
  `requirements` together, but `screens`'s context reads
  `all.journey.handle` and `requirements`'s reads `all.screen.handle`
  (`bundles/default/tiers/screens.yaml`, `requirements.yaml`), and both
  are populated by `journey`/`screen` child nodes minted from the
  upstream tier's own **draft**
  (`bundles/default/edges/decomposition.yaml:70,78`) — so `screens`
  cannot dispatch until `journeys` has drafted, and `requirements`
  cannot dispatch until `screens` has, whatever a reviewer's own
  wall-clock happens to overlap with the next tier's draft. Costed
  conservatively — draft and review both waited on for each of the
  three, rather than assumed to overlap with the next tier's draft —
  that round is six waves, not two:

  - `feature_expansion`'s own draft and review, before the first
    approval: 2 waves, ~3 minutes.
  - `journeys` → `screens` → `requirements`, each tier's draft and
    review before the next tier's draft is even ready: 6 waves,
    ~9 minutes.
  - `sysarch` alone, after `requirements`'s approval — its other
    context source, `self.parent.decomposition -> resp.handle`, mints
    at `requirements`'s own draft time and costs no separate wave: 2
    waves, ~3 minutes.

  15 minutes is the floor for the three approval-gated rounds alone,
  plus the `approve_drafts/2` call and the next poll that observes its
  effect at each of the three approvals. It is not the floor to
  `remaining == 0` — the suite's actual stop condition — because most
  of the tiers past `sysarch` still carry a `draft:` block and still
  cost waves, even though none of them costs another approval. Named
  by branch, costed the same conservative way as the three rounds
  above (draft and review both waited on, no overlap with the next
  tier's draft assumed):

  - Backend: `comparch` (`per(comp)`, `comp` already `:approved` at
    `sysarch`'s draft) drafts and reviews — 2 waves — then
    `subcomparch` (`per(subcomp)`, `subcomp` already `:approved` at
    `comparch`'s draft) drafts and reviews — 2 waves — then
    `impl_backend` drafts and reviews — 2 waves, not alongside
    `subcomparch`: the only thing `impl_backend` reads that
    `subcomparch` writes is `self.parent.dependency ->
    subcomp.handle.fragments[pubapi]` (`impl_backend.yaml:27`) — its
    other context entries are its parent's own `mint.*` fields, `ref`
    and `feature_expansion`, none of which `subcomparch` touches. That
    `pubapi` fragment is authored by `subcomparch`'s own `produces:`
    (`subcomparch.yaml:33`), and `subcomp` itself carries only `mint.*`
    copies, no fragment content of its own. 6 waves, ~9 minutes.
  - Front end: `frontend_sysarch` (`scope: singleton`, its three
    `all.<tier>` walks all already `:approved`) drafts and reviews — 2
    waves — then `ui_collarch`/`screen_collarch` (`ui_coll`/
    `screen_coll` already `:approved` at `frontend_sysarch`'s draft)
    together — 2 waves — then `ui_subcomparch`/`screen_subcomparch`
    (their own subcomps already `:approved` at the collarch tiers'
    drafts) together — 2 waves — then `impl_ui`/`impl_screen` together
    — 2 waves, not alongside the `*subcomparch` pair, for the same
    reason `impl_backend` isn't alongside `subcomparch`: `impl_ui`
    reads `ui_subcomp.handle.fragments[pubapi]` (`impl_ui.yaml:24`),
    authored by `ui_subcomparch`'s own `produces:`
    (`ui_subcomparch.yaml:27`), and `impl_screen` reads
    `screen_subcomp.handle.fragments[pubapi]` (`impl_screen.yaml:22`),
    authored by `screen_subcomparch`'s own `produces:`
    (`screen_subcomparch.yaml:26`). 8 waves, ~12 minutes.

  The two branches run alongside each other, not in sequence, so they
  do not add on top of each other — but fragment-authorship, a third
  relationship distinct from mint-ancestry and approval-ancestry, does
  not move the count everywhere it applies the same way, and it applies
  in three places above, not one.

  At the `ui_collarch`/`screen_collarch` step, it happens not to move
  the count. `ui_collarch` walks `self.parent.uses_shapes -> comp
  .handle.fragments[pubapi]` and `screen_collarch` walks
  `self.parent.calls -> comp.handle.fragments[pubapi]`
  (`bundles/default/tiers/ui_collarch.yaml:38`,
  `screen_collarch.yaml:45`), and `comp`'s `pubapi` fragment is
  authored by `comparch`'s own `produces:` (`comparch.yaml:58`), not by
  `sysarch` — so `comp` reaches `:approved` at `sysarch`'s mint
  (mint-ancestry) and needs no wait on `comparch`'s own approval
  (approval-ancestry), but the *content* the front end actually reads
  is written by `comparch`'s draft (fragment-authorship). It does not
  move the count *at this one step* because both branches finish their
  first tier two waves after `sysarch`'s approval regardless of which
  relationship governs `ui_collarch`'s wait — they land in the same
  wave either way. It is exactly the gap ORC-235's own second defect is
  about — a context walk's readiness check passes at `comp`'s mint-time
  `:approved` while the fragment content it reads is still being
  written by `comparch` — and this entry does not depend on that gap
  being closed.

  It does move the count at the `impl_*` step, in both branches, which
  is why the waves above cost `impl_backend` after `subcomparch` and
  `impl_ui`/`impl_screen` after `ui_subcomparch`/`screen_subcomparch`
  rather than alongside them. `subcomp`/`ui_subcomp`/`screen_subcomp`
  are join targets with no fragment content of their own — every field
  they carry is a mint-time copy — so unlike the `comp`/`comparch`
  step above, there is no mint-ancestry route into an `impl_*` tier
  that bypasses the tier that writes the content it reads: fragment-
  authorship is the *only* relationship in play, not one of two that
  happen to agree. Costing `impl_backend`/`impl_ui`/`impl_screen` as
  concurrent with their `*subcomparch` sibling would let the suite call
  the walk complete while an `impl_*` draft was rendered against an
  empty `pubapi` fragment — precisely the class of failure a full walk
  exists to surface, so the wave count above prices it as sequential.

  **That wait is priced, not enforced.**
  `impl_backend`'s `self.parent.dependency ->
  subcomp.handle.fragments[pubapi]` (`impl_ui`'s and `impl_screen`'s
  own reads are the identical shape one tier over) is the same
  `subcomp↔subcomp` `dependency` walk `subcomparch`'s own context
  entry already is, and the extraction-gate entry above covers it: no
  `dependency` instance is extracted regardless of which tier's
  context declares the walk, so it resolves to `[]` and is vacuously
  satisfied whether or not `subcomparch` has run.
  `impl_backend`/`impl_ui`/`impl_screen` are therefore ready the same
  wave as their `*subcomparch`/`*collarch` sibling — once
  `subcomp`/`ui_subcomp`/`screen_subcomp` is `settled?`, i.e. once
  `comparch`/`ui_collarch`/`screen_collarch` is approved — not one wave
  after it. Pricing them as sequential anyway does not undercount: it
  charges a wait the graph does not enforce, which only widens this
  floor's own margin, and it stays priced this way on purpose, since
  closing the extraction gap would reintroduce the wait for real and a
  floor that assumed otherwise would need re-deriving the moment it
  does.

  The front end's 8 waves is the longer of the two branches and is
  what the walk actually waits on after `sysarch`'s approval. The
  floor to `remaining == 0` is 15 (the three approval-gated rounds)
  plus 12 (the front-end branch) — 27 minutes — before the
  breadth headroom below is added on top.

  The unmeasured breadth named above (several tiers'
  worth of siblings queueing behind Oban's `generation_dispatch`
  concurrency of 5, and whatever GitHub Actions' own runner queue adds
  under load) is still the headroom a depth-based floor alone would not
  cover. It is 6 minutes, and it
  belongs on top of the 27-minute floor rather than folded into it: a
  floor that spends the headroom on waves instead leaves nothing for
  the breadth it exists to cover, and a passing walk plausibly
  `flunk`s on a tight, unexplained timeout. `@poll_deadline` is
  `:timer.minutes(33)` — the 27-minute floor plus the 6-minute headroom
  — and `@tag timeout: :timer.minutes(35)`, wider still so the
  assertion failure path (a real `flunk/1`) is what ends the test on a
  genuine timeout, never ExUnit's own kill, for the identical
  `after`-block reason the poll-deadline entry above gives.

  On top of the number, the failure path: a `flunk/1`
  on timeout reports the tier set that ran, every node
  `Store.list_nodes/2` still shows `:drafted` project-wide, how many
  `approve_drafts/2` calls fired and how many approvals each reported,
  and the per-run `duration_ms` `systems/delivery.md`'s `runs/2`
  carries — enough to tell a genuinely stuck graph from a slow one
  without re-running it by hand, and the thing that stands against the
  pressure a tight, unexplained timeout creates to shorten the suite
  back down.

- **A full walk is the first exercise of `@root_tag_fixtures`'s
  previously-unreached stubs.** A walk capped at two rounds leaves
  most of `@root_tag_fixtures` unreached by any run. A
  `ToySeedChainLiveTest` run that reaches `remaining == 0` with zero
  approvals pending is observed evidence that the `root_tag`s the toy
  raft's downward cascade actually reaches resolve against their
  stubs, rather than an assumed one.

- **Two stale moduledocs are corrected in the same change**, both
  design-owned prose sitting in dev-owned test files, so design records
  the finished shape here and dev writes it.
  `test/catapult/generation/todo_app_proof_live_test.exs`'s moduledoc
  draws no comparison to `ToySeedChainLiveTest`'s round count or poll
  shape — there is no round count to compare against, since
  `ToySeedChainLiveTest` walks the raft's full downward cascade with
  no cap — and says instead that `TodoAppProofLiveTest` stops at
  provisioning because its own middle spans hours or days of human
  review, which is reason enough on its own.
  `test/catapult/generation/toy_seed_chain_live_test.exs`'s own "What
  this proves for real" paragraph states that this test proves a full
  downward-cascade walk of the toy raft against real GitHub Actions
  runs — `feature_expansion` as the walk's first dispatch, never
  `feature_expansion` alone, `Provisioning.approve_drafts/2` approving
  every drafted node the walk produces, and the tier set the run
  actually reached, not a fixed one, as what a passing run
  demonstrates.

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
  (`Catapult.Delivery.Store.sweepable_project?/1`) is a
  catch-all — `%Project{test_project_state: :active} -> true`,
  `%Project{} -> false` — so a `:provisioning` row falls to the
  `false` clause; the only code the guard needs is `:provisioning` in
  the schema's own `Ecto.Enum, values:` list (`systems/delivery.md`'s
  entry above covers this, and without it the row fails to load
  regardless). Neither sweep site needs a check of its own: both
  `Sweeper.sweep_project/2` and `DispatchWorker`'s own
  `still_sweepable/1` re-validation read `sweepable_project?/1`
  rather than holding a cached readiness bit, so the schema's value
  list is the whole of it.
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
  `frontend-sysarch`, `implementation`, `journeys`, `non-goals`,
  `propagation-plan`, `reference`, `refactor-plan`, `requirements`,
  `review`, `screen-collarch`, `screen-subcomparch`, `screens`,
  `subcomparch`, `sysarch`, `ui-collarch`, `ui-subcomparch`,
  `upward-propagation-plan`, `vocab-entry` — every multi-word entry
  hyphenated, the same spelling every schema under
  `bundles/default/schemas/**` uses for a multi-word element name
  (`systems/platform_content.md`'s ORC-232 entry: `frontend-sysarch`,
  `screen-collarch`, `screen-subcomparch`, `ui-collarch` and
  `ui-subcomparch` were the bundle's only underscored root_tags,
  standardized to match the rest).

  A missing key is not a gap the live suite tolerates by exercising a
  narrower chain — the entry above keys the lookup by `root_tag`
  rather than by tier precisely so one fixture serves every tier sharing
  a root_tag, and that same collapse means a single missing key fails
  every tier that shares it, not just one.

  Each fixture is a hand-authored XML document
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
  namespace that tracks the bundle's own tier names, which is why it
  does not equal the differently-punctuated `root_tag` namespace;
  `@root_tag_fixtures`'s value side is exactly what
  translates between the two. For the two collapsed `root_tag`s —
  `implementation` (`impl_backend.yaml`, `impl_screen.yaml`,
  `impl_ui.yaml` all declare it) and `review` (all eighteen `*_review
  .yaml` tiers declare it) — no single tier basename applies, so the
  filename names the `root_tag` rather than any one owning tier:
  `impl.xml` and `review_approve.xml` are read as exactly that rather
  than as derived from a tier that does not exist.
- **The "Read the stub fixture" step must itself produce a typed
  `outcome.json` when the fixture is missing, not fall through to
  "Report the result"'s own generic fallback** (ORC-225, the same run
  26 incident above). With no guard on the step's `open()` call, a
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
  "Report the result"'s own fallback keeps one meaning rather than
  gaining a second: since the read step cannot fail past this point
  without writing something, "no outcome.json" means what it claims
  to — the body-producing step (real or stubbed) crashed somewhere the
  harness gave it no chance to report.

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
