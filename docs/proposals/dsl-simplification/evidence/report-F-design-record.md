# Report F — the design record on the DSL

Sources read: `docs/v5-design-decisions.md` (§1, §3.1–3.4, §4.5, §5.1–5.5, §6, §7.10, §7.16, §7.18, §7.19, §8, §9, §10; rest by heading), `docs/non-goals.md` (full), `systems/core_dsl.md` (full), `systems/core_dsl.reasons.md` (headings; it has entries only for #8–#41), `systems/platform_content.md` (header, #62/#63), `docs/build-plan.md` (Phases 3–6). `docs/dsl-syntax.md` deliberately not read.

## PART 1 — Where the record states the DSL's purpose

**The record almost never says why the DSL exists.** One sentence does, and it sits in a parked item, not a decision:

- **v5 §8, "A bundle-authoring surface"**: *"The rationale is the DSL's own premise. Customization is why the DSL exists rather than hard-coded chain logic. If customizing requires learning YAML, that premise is half-delivered — the capability ships and the audience for it doesn't. People will hand-edit prompts to build their own differentiation whether or not it is advisable, and that demand is the demand the DSL was built to serve."* Revisit condition: "the first customer … mandatory the moment non-engineers are expected to participate in workflow construction."

Everything else is inherited or indirect:

- **v5 header + §1.2**: the v4 spec is "still authoritative wherever this document is silent"; "What survives the inversion untouched: the bundle DSL, reducer/projection machinery, context walks, grammars, the `ready_scopes` projection." The DSL's existence is *carried forward*, not re-argued.
- **v5 §7.10** gives the purpose of *declarations* (delivery side): "Declarations exist so the plane is generic over projects and target layers, so the protocol is inspectable … and so the sim ring is configured from the same declarations production reads."
- **v5 §7.18**: the two-axis split exists for "an organization whose two projects need different decompositions under one shared workflow … decomposition tracks the target stack, while review and deployment track the organization."
- **v5 §5.1**: "tiers are cheap by the DSL's own design ('adding a tier is a bundle edit')."
- **v5 §1.3 (3)**: Catapult's "biggest parts are the default bundle + prompts (refs anyway)."

**Phrases the task asked me to find and that are NOT in the record** (grepped v5, non-goals, core_dsl, platform_content, build-plan, conventions, ui-spec, README, seed-docs README, v4 spec): "community iterating the SDLC model independently from the engine" — absent ("community" appears only for the registry tier and the hosted tier's "community default" runner). "Opinionated default" — absent (only §1.4 "Target opinionation", about Elixir/Phoenix). "Realistic test target" — absent; the nearest is build-plan Phase 5 ("a small todo application … the claim under test is mechanism") and v5 §10.2 ("protocol correctness and content quality are different axes, tested by different instruments"). "Don't overfit the default" — absent; the nearest is v5 §7.19: "component/subcomponent is the sweet spot and the default chain's shape, but nothing hard-codes it. So a workflow declaring depth `2` against a chain that fans out once applies at the two levels that exist, silently. It must *not* be a load error."

## PART 2 — Recorded decisions a restructuring must argue with

| Decision | Where | What it decides | Reason given? |
|---|---|---|---|
| Frozen core, growth by extension | v5 §9; core_dsl #2 | Core = "tiers, scopes, edges, fragments, handles, context walks, grammars, readiness, generators, the predicate language, bundle layout". New vocabulary is a platform-shipped extension registering with the loader. | Yes: "no dialect forks … each need becomes a fork and the dialects drift apart." |
| No bundle-side code, closed vocabularies, non-Turing predicates | v5 §6 (design-stance note), §7.10, §9; non-goals "No workflow interpreter…"; core_dsl #3 | Scope expressions, predicate operators, options, fragment kinds are closed sets; "no escape hatches into Turing-completeness". | Yes: "a correctness property the scheduler, audit, and security posture lean on"; "a second Turing tarpit". |
| Declare the shape, implement the semantics | v5 §7.10, §7.16 ("a gate declaration is not a program") | Commanded aggregates are the semantics; YAML configures them. | Yes: genericity over projects, inspectability, sim ring reads the same declarations. |
| Fork-not-layer; `extends:` retired | v5 §3.1, §5.5, §6, §7.18; core_dsl #14, #29 (ORC-153) | Each bundle is one directory; loader composes nothing; `extends:` is an unknown manifest key on both axes; `platform-elixir` folded into `bundles/default/`. | Yes: git gives "fork, tailor, and merge upstream later. Hex has no merge story"; `extends:` "loses its last shipped user". Traversal guard survives independently (#29). |
| Chain bundle ≠ workflow bundle; neither references the other | v5 §7.18; core_dsl #11 | Two bundles per project; both reference only platform system statuses; "any workflow bundle composes with any chain bundle". | Yes: decomposition tracks stack, workflow tracks org; "welding them … forces a fork of the workflow per stack". Cost stated: "review granularity is bounded by the fixed vocabulary". |
| One chain bundle per project, no per-language split | v5 §5.5; non-goals "No per-language chain bundle splitting" | `catapult.yaml` `chain:` names exactly one bundle. | Yes: polyglot components share one graph. |
| Platform-fixed protocol; projects bind, never restructure | v5 §7.10, §7.16; non-goals first entry | Agent/queue states and the automation graph are fixed; a state is declarable iff no plane logic branches on it. | Yes: prompts, plane logic and vocabulary are written against them. |
| Fixed system-status table | v5 §7.19; core_dsl #21–#27 | `pending`, generation (+`design`/`architecture`/`implementation`), `checks`, `reconcile`, `merge`, `deploy`, `setup`, `retro`, `terminal`; platform-grown, never bundle-authored. | Yes: it is the anchor set for blocked-ticket re-resolution across a cutover. |
| Review-as-tier (`reviews: <tier>`) | core_dsl #9 (ORC-84, revising v5 §7.19); v5 §7.16 last para | A chain tier may declare itself the review of another, 1:1, same context walks. Distinct from a workflow gate; has no throwback semantics. | Partial: obligates a load check; the *why* is in the reasons sibling, not in v5. |
| Named predicates in `predicates.yaml`, four slots | core_dsl #12; v5 §3.4 | `scope_filter`, `cardinality.when`, edge `constraint`, flow `completion` reference named predicates; `Chain.t()` carries the resolved map. | Yes for the field ("re-parsing … would double-implement"); the file itself is inherited from v4, unargued here. |
| Closed generator set, grown platform-side | v5 §6, §9; core_dsl #30, #41 | `external`, `template` added in v5; `supplied` added at ORC-110; `synthesis` is a join target with no prompt (v5 §5.1). | Yes per addition; the closedness itself rides #3. |
| Closed scope set, grown directly in core | core_dsl #8 | Fourth scope kind `cascade_visit`, multi-hop walks, `~`, `all.<tier>.<projection>`, edge `instances:` — "landed directly, not through the extension registry". | Stated as fact; #2 says "when in doubt, it's an extension", so #8 is a recorded exception without an argument in core_dsl.md. |
| XSD grammars | v5 §6 ("grammar growth"), §5.5 (`schemas/review.xsd`); core_dsl #6, #33–#36 | Draft grammars are XML schemas; validators derive from bundle declarations; loader walks `complexType`, punts on `xs:group`/`xs:extension`. | Assumed from v4, never argued. #6's reason: one validator source so engine and generation "agree byte-for-byte". |
| Liquid prompts and partials | v5 §6, §10.1; platform_content #2, #3 | Prompts are `.md.liquid` content; `{% include %}` partials share framing per family. | Yes: "one source for shared prompt framing"; prompts reviewed as diffs. |
| Per-tier YAML files | v5 §5.1, §6; implied by §9's "bundle layout" | "per-tier files for what differs"; tiers/edges/flows/prompts/schemas directories. | Weak: only "adding a tier is a bundle edit" and the partials bullet. |
| All validation at load | core_dsl #4 | "A bundle that loads is a bundle the engine can run." | Yes. |
| Destructive bundle change = cutover | v5 §6, §7.19; core_dsl #5 | Drain (per axis), reviewed transform list, migrate, flip-as-event. | Yes. |
| `catapult.yaml` is loader input, not bundle content | core_dsl #7 | Names one bundle per axis. | Yes. |
| Store test | v5 §7.10, §7.18 | Anything changing generation/validation/enforcement is repo content; connectivity is bindings. | Yes: replay determinism. |
| Refs stay general; policies carry non-goals; no new node kinds | v5 §4.5 | One escape hatch; non-goals are negative policies. | Yes. |
| Unphased impl; phase machinery dropped | v5 §6, §7.9 | `phased:`, `phase_plan`, `/run_phase` gone. | Yes. |

**"The whole graph as a single adjacency-list file"** — not discussed anywhere in the four sources. No section argues for or against file granularity on the chain axis. The only recorded stance on granularity is on the *workflow* axis: core_dsl #14 unified three file shapes into one `types/<name>.yaml` whose ordered `statuses:` array carries position inline ("position is the array index, full stop; no declaration in this grammar carries an `after:` field"), and #20 calls the old shape "the three-file format's residue, the same kind of accidental coupling the one-file unification above removes". That is a precedent for "put the relationship where it is read, not in a side file", not a decision about the chain graph.

**"Pipeline in code rather than data"** — discussed and decided, but as a *split*, not a binary. v5 §7.10: "there is no YAML-programmable workflow interpreter"; semantics are code, shape is data. v5 §8: "Customization is why the DSL exists rather than hard-coded chain logic." Non-goals: "No workflow interpreter in the DSL, no bundle-side code". The question "should the *chain graph* be Elixir modules instead of YAML" is not asked; §1.2 carried the bundle DSL across the inversion untouched and §1.3 rules out self-hosting, so the chain-as-data decision is v4's, reaffirmed by silence.

## PART 3 — core_dsl.md standing decisions, one line each

- #1 heading only ("Standing decisions").
- #2 Core frozen; growth is extensions; "when in doubt, it's an extension".
- #3 No bundle-side code, ever; predicates non-Turing-complete.
- #4 Validate at load where possible; a loading bundle is a runnable one.
- #5 Destructive change over a populated graph is a cutover; drain is per axis; flip is an event.
- #6 Grammar validators live here, one source for engine and generation.
- #7 `catapult.yaml` belongs to the loader, names one bundle per axis.
- #8 Four core growths landed directly (ORC-84): `cascade_visit`, multi-hop/`~` walks, `all.<tier>.<projection>`, edge `instances:`.
- #9 Fifth growth: `reviews: <tier>` marks a review tier, 1:1, same context set (load-checked).
- #10 `depth:` widens to `[first, rest]`; `critique.yaml` added (later retired by #14).
- #11 No named-pass selector for the pair — positional only, to avoid a cross-axis leak.
- #12 `Chain.t()` carries the resolved `predicates.yaml` map.
- #13 Queue sequence vs container sequence were two shapes; types became a registry (superseded).
- #14 One declaration shape `types/<name>.yaml` with inline `statuses:` array; `after:` retired; `critique.yaml` retired; `extends:` never on workflow bundles.
- #15 `skeleton:` optional; rootness derived; gates/environments legal on skeleton-less types; `singleton:` added (later retired).
- #16 `entry:` required on workflow `bundle.yaml`, names the dispatch root.
- #17 Bare sub-arrays group entries; flat only; one agent-balled anchor each; decline defaults to the sub-array's earliest entry.
- #18 Decline targets never narrower than "any earlier status in the effective sequence".
- #19 `throwback:` narrows to one optional landing-point override.
- #20 Skeleton fixes a backbone, not exclusive membership; `singleton:` retired; `setup`/`retro` fold inline; a container instance is a dispatch target.
- #21 `merge` split: `reconcile` (agent, review-shaped, required before `merge`) and `merge` (plane-balled); gate scope derived from position relative to `reconcile`.
- #22 `fanout` status retired; architecture fan-out is recursive child tickets; `merge` fires only at root.
- #23 `implementation` is a third generation kind; `pending` recurs per sub-array; two type declarations (feature, child), not one depth-filtered.
- #24 `critique` adjacency rule stated at five sites, edited together.
- #25 `checks` sits between generation and `critique`; `reconcile` declared once unconditionally.
- #26 `status:` entries get bundle-authored `name:`; positions namespaced by sub-array; gate names may not collide with status names.
- #27 `blocks:` is an entry guard checked once; `terminal` has an undeclarable all-queues-empty guard; `design`/`architecture` kinds; sub-arrays referenced by containment.
- #28 Reference-ambiguity and runtime-kind-collision are two computations (`kind_ambiguous`).
- #29 `extends:` retired entirely; single-directory lookup; traversal guard stays.
- #30 `design_system` is generator `supplied`, `source: input.<role>`, no draft/review.
- #31 The `design_system` tier is declared here: no scope parent, mints at most one.
- #32 The `ui_coll → design_system` edge is `ui_coll`'s to declare.
- #33 `declared_in` path segments are load-checked against the tier's XSD.
- #34 The check follows same-file `type="Name"` references.
- #35 Unresolvable segments (`xs:group`, imports) pass unverified; only positively-wrong ones fail.
- #36 Attribute segments checked like element segments.
- #37 Five endpoint locator kinds (`self`, `self.parent`, `fanout(<edge>)`, singleton endpoint, explicit `@attr`); no inference beyond them.
- #38 `produces:`/`fields:` `draft.<path>` sources get the same schema cross-check (21 of 24 were wrong).
- #39 `policy_application` is a different mechanism and gains none of #37.
- #40 `mint.parent.<name>` names the inherited half of a join target's field source.
- #41 `supplied` mint is a scaffold-time write, not a swept dispatch.
- #42 `.synthesis` retired from the projection vocabulary (no consumer in `bundles/default`).

**#43 Initial vs target** (verbatim): "Initial (Phase 3): core vocabulary, loader, design-dialect extension set (delivery annotations arrive with delivery). Target: full extension registry with delivery + runtime dialects registered; bundle-diff support for the registry's handle machinery."

**#44 Depends on** (verbatim): "substrate. Content it loads lives in platform_content."

Neither has a `.reasons.md` entry; nor do #1–#7.

## PART 4 — Default-bundle-driven vs platform-level

**Overfitting candidates (decision shaped by what `bundles/default` or `default-flow` happened to need):**

- core_dsl #8 — four core growths for the planning tiers (`refactor_plan`, propagation plans), added to core rather than as an extension, against #2's own rule.
- #9 — `reviews: <tier>`, for the default's `*_review.yaml` tiers.
- #23, #27 — `implementation`, `design`, `architecture` as fixed system-status kinds: the platform table grows to match the default chain's phases. v5 §7.18 concedes this coupling: "the fixed vocabulary has to be rich enough to carry the gates people actually want — §7.6's lifecycle already separates product-tier from architecture-tier generation, which is what makes the two default gates expressible."
- #14–#26 as a body — the `types/<name>.yaml` grammar (sub-arrays, `pending` per sub-array, `reconcile` recurrence, merge-at-root, twice-cited gates then `name:`) was iterated against `feature.yaml`/`component.yaml`/`milestone.yaml` worked examples across six review rounds; each rule cites the example that forced it.
- #30–#32, #41 — a generator type and a tier for one input role (`design_system`).
- #37 — the locator vocabulary was derived by tracing the default's 17 third-party edge instances and closed to exactly what they need ("a closed form … since the resolver implements only this one").
- #38 — check added because 21 of 24 `produces:` entries in the default were wrong.
- #42 — `.synthesis` removed because no default tier uses it ("a projection with no consumer is not designed").
- v5 §5.1 four families as separate tiers, and §7.19's depth `0/1/2` — the depth rule explicitly guards against hard-coding ("nothing hard-codes it"), but the number scale is the default's.
- v5 §6 grammar growth (`<permissions>`, process inventory, `enforcement:`) — Elixir-target content in what §9 calls core grammars.
- #22 `fanout` retired because of what a subcomparch `critique` bounce needs in the default chain.

**Explicitly platform-level (protocol):** #2, #3, #4, #5, #6, #7, #29; v5 §9 core list; §7.10 shape/semantics and the store test; §7.16 admission rule; §7.18 axis split, no cross-axis reference, "topology is content, attachment is a binding"; §7.19 fixed system statuses as re-resolution anchors, depth as a number not a name; §6 closed vocabularies and cutover; §3.1 fork-tailor-merge; non-goals' two DSL entries; the content-path traversal guard.

## PART 5 — Does the record distinguish protocol from implementation?

**Not by name, and not as a bundle-author contract.** "Protocol" in the record means the *delivery/automation* protocol (fixed states, mutex, writer matrix — v5 §7.10, §7.16, non-goals), never "what a bundle must satisfy for the loader".

The nearest statements of the split:

- core_dsl #4: "A bundle that loads is a bundle the engine can run" — load-time validation *is* the contract, unnamed.
- v5 §7.10: "declare the shape, implement the semantics" — data declares, aggregates implement.
- v5 §9 / §7.18: "Vocabulary is an extension … Instances are content"; "What vocabulary a bundle may use is a platform decision (extensions); what a project's bundle actually contains is that project's own git history."
- platform_content #63: "core_dsl defines what these files may say; generation renders them."
- v5 §10.2: "protocol correctness and content quality are different axes, tested by different instruments."

Against that, `systems/core_dsl.md`'s standing decisions mix grammar rules ("a `statuses:` entry must carry exactly one of…") with loader internals ("`Chain.t()` gains `predicates:`", "`Status.parse/4`'s `queue_shaped?`", "`workflow.ex`'s backbone and sub-array checks") in the same bullets, and the normative grammar lives in `docs/dsl-syntax.md` §13's checklist rather than in a document that names itself the author-facing contract. So: the split is implied by three separate doctrines (shape/semantics, vocabulary/content, load-time-validation-as-contract) but nowhere stated as "protocol vs implementation", and the standing-decision log does not observe it.
