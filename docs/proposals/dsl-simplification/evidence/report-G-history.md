# Report G — History: why the DSL and default bundle grew

Scope caveat up front: the checkout is a **shallow clone** (`git rev-parse --is-shallow-repository` = true), 78 commits visible, earliest `d45af0b` dated 2026-08-31. Everything before that (ORC-5's loader, ORC-84's siege port, the ORC-105 and ORC-151 review rounds) is invisible to `git log`; the counts below are lower bounds over ten days (2026-08-31 to 2026-09-09), and the earlier history survives only as prose in `systems/core_dsl.md` and `CLAUDE.md`.

## PART 1 — What the retros say about the DSL

`docs/retros/` holds six files (`hookup.md`, `the-engine.md`, `the-authoring-loop.md`, `tech-debt-before-the-engine.md`, `tech-debt-before-the-authoring-loop.md`, `tech-debt-before-the-product-tier.md`), 96 lines total. **None contains narrative.** Each is a "Shipped (archived from the tracker; this note is what duplicate detection reads...)" ticket list. There is no sentence about bloat, overkill, overfit, or the DAG document model. The evidence is in the ticket *titles*, which are diagnostic:

- `the-engine.md`: `ORC-5 — Implement the DSL core: loader, vocabulary, extension registry`; `ORC-84 — Port the siege default bundle into bundles/default, verbatim where it survives v5`.
- `tech-debt-before-the-product-tier.md` (34 lines, the largest) is dominated by DSL/bundle defects found after the fact:
  - `ORC-181 — dsl-syntax.md §15.10 doesn't settle the derived default for a gate sitting before its own sub-array's agent step`
  - `ORC-187 — Docs coherence sweep: six places the record contradicts the tree or itself after ORC-141/148/151/155`
  - `ORC-200 — Docs coherence after ORC-177 and ORC-184: retired symbols still referenced live, two stale kind counts, unqualified feature.yaml citations, and no check that relocated reasoning lands`
  - `ORC-134 — Five default-bundle prompts guard on {% if feedback %}, which Liquid/Solid truthiness will never treat as an empty list as false`
  - `ORC-184 — partials/_architecture_framing.md.liquid's own feedback-revision block never renders — {% render %} isolates scope from every one of its 9 call sites`
  - `ORC-193 — No prompt in the default bundle ever renders {{ feedback }} or {{ draft }} — both live only inside a partial unreachable from all 13 render call sites`
  - `ORC-179 — Which generation kind (design/architecture) each bundle chain tier picks is still undecided — deliberately deferred`
  - `ORC-172 — @ticket_status_names rejects most of the fixed vocabulary a ticket-skeleton array is documented to legally hold`
  - `ORC-171 — Runtime position-tracking resolves a bare kind/gate name with no namespace awareness — a bundle the loader now permits can silently corrupt a live instance`
  - `ORC-177 — ContainerLifecycle's repopulation/backward-move semantics still implement the design's own retired reading`
- `the-authoring-loop.md`: `ORC-117 — Synthesis join targets can never reach :approved, and the chain test hides it`.

Pattern: three separate "the prompts never showed the model its feedback" tickets (134, 184, 193) on the same partial; two "docs coherence sweep" tickets whose whole content is the record contradicting itself; one ticket whose title is that the syntax doc "doesn't settle" its own rule.

## PART 2 — platform_content.md: the decisions that size the chain bundle

`systems/platform_content.md` (1135 lines) has three h2s: `#1 Standing decisions` (lines 33–1125, sixty bullets `#2`–`#61`), `#62 Initial vs target`, `#63 Depends on`. It cites **22 distinct ORC tickets** (ORC-5, 7, 16, 50, 84, 92, 105, 106, 107, 109, 110, 111, 114, 134, 153, 179, 193, 201, 223, 232, 235, 236). Current bundle: 143 files / 8013 lines (`tiers` 1619, `prompts` 3779, `schemas` 1598, `edges` 673, `flows` 301, `default-flow` 286); **51 tier files, 17 of them `_review`**.

Size-shaping rules, with ids:

- **#9** — the architecture chain is the *full* backend family, mint-then-articulate at every fan-out: `feature_expansion → requirements → resp → sysarch → comp → comparch → subcomp → subcomparch → impl` plus pools `policy`, `vocab`, `ref`. `sysarch` is its own tier because "folding it into resp asks one prompt to do two jobs (a previous ORC-7 pass made exactly this mistake)". `resp` is restored as a real tier (v4 had it as fields).
- **#13** — this chain is *one of four families* sharing the shape: UI, screen, client each fan out "behind their own tier files". `impl` becomes `impl_backend` once siblings exist (#47).
- **#14** — fragment ownership: 5 kinds at `comp`, 3 at `subcomp`; vocabulary stays a closed set of 5.
- **#15** — `ref`/`vocab`/`policy` are flat pools, not singletons.
- **#11/#12** — a second intake root `non_goals` (+ `non_goals_review`) mints into the policy pool.
- **#21** — five flows ship (v4's `plan_change` voided); **#22** — *each flow has its own planning tier* using a new scope kind `cascade_visit` ("a missing scope kind is a `dsl-syntax.md` proposal … not a reason to ship without the capability"); **#27** every `<flow>_plan` declares `fields: argument`.
- **#23** — `modify_*` prompts fold into each tier's prompt as a `{% if feedback %}` section because "§3's tier grammar has exactly one `prompt:` slot per tier … inventing one would be new DSL surface a content-porting ticket has no mandate to add" (the same section later turned out never to render, ORC-134/184/193).
- **#25** — **a review is a tier, not a nested `review:` block**: every `generator: llm` tier gets a sibling `tiers/<name>_review.yaml` with `reviews:` and a `context:` "restated verbatim and checked at load time". This is the single rule that doubles the tier count. **#26** — gates read `depth: 0`, `critique` reads `[2, 0]`.
- **#35** — `platform-elixir` folds in, `extends:` retires (ORC-153): the bundle is one directory.
- **#36** — `journeys/journey` and `screens/screen` land as two more spine-plus-projection pairs "the identical shape `requirements`/`resp` already has"; **#40–#42** they gain `input.mocks`.
- **#44/#45** — `frontend_sysarch` (singleton, four `all.<tier>` walks) plus UI and screen families, each `<coll> → <collarch> → <subcomp> → <subcomparch> → impl_<family>` — "the backend shape renamed per family" — each LLM tier again with a `_review` sibling (seven more review tiers enumerated).
- **#48** — join-target tiers are minted via one `decomposition` edge with thirteen enumerated `instances:` (`sysarch→comp`, `comparch→subcomp`, `feature_expansion→vocab`, `requirements→resp`, `sysarch→policy`, `comparch→policy`, `non_goals→policy`, `journeys→journey`, `screens→screen`, `frontend_sysarch→ui_coll`, `frontend_sysarch→screen_coll`, `ui_collarch→ui_subcomp`, `screen_collarch→screen_subcomp`).
- **#61** — `mint.parent.<name>` (ORC-236) after discovering "four of those five fragments' own `authored:` sources were misspelled against their schema … each named an empty fragment".

The recurring justification is *symmetry*: "the same shape X already has", "that existing rule applied, not a fresh choice". Nothing in #2–#61 argues from cost or asks whether a family needs the full shape; `platform_content.reasons.md #21` is the one place proportionality appears ("kept proportionately small rather than padded to match `feature_request`'s length").

## PART 3 — Git history pattern

- `git log --oneline -- docs/dsl-syntax.md | wc -l` = **10** (also 10 with `--follow`); `-- bundles/` = **12**; comparison: `systems/core_dsl.md` 10, `docs/v5-design-decisions.md` 12, `systems/delivery.md` 19. Regex count (`round|correct|revis|amend`) = **1** (`93908b2 ORC-106: address design review — reground …`); the regex undercounts, since subjects here phrase corrections as defect statements.
- Reading the 10 subjects: **corrective/defect-driven: 7** (ORC-181 "§15.10 doesn't settle…", ORC-198, ORC-106 "fix Phase 5's record — … recorded wrong, inconsistently, or not at all", ORC-106 "address design review", ORC-232 "can never mint … spell with underscores what … spells with hyphens", ORC-236 "declared and none is wired", paring pass); **additive: 2** (ORC-107 input raft, ORC-110 mocks); **subtractive: 1** (ORC-153 retire `extends:`). Ratio roughly 7:2 corrective to additive.
- `bundles/` 12 subjects: defect fixes 5 (ORC-193, 201/202 ×2, 232, 235, 236 — six commits), additive 4 (ORC-108, 109, 110, 111), subtractive 1 (ORC-153), plus the base merge.
- Dates: earliest visible `d45af0b` 2026-08-31, latest `e767c51` 2026-09-09.
- Line count of `dsl-syntax.md` per commit (oldest→newest): 3691, 3691, 3712, 3718, 3702, 3726, 3737, 3766, **4041** (ORC-236), **3750** (paring pass). The paring commit's diffstat: `docs/dsl-syntax.md | 3041 +-`, `v5-design-decisions.md | 2597 +-`, `platform_content.md | 1634 +-`, `core_dsl.md | 1407 +-`; 46 files, 11092 insertions / 12715 deletions — i.e. it moved reasons into `.reasons.md` siblings (321 + 396 new lines) and netted only ~1600 lines off across the whole record. `v5-design-decisions.md` is 4750 lines today.

## PART 4 — Evidence the pipeline struggled specifically with designing the DSL

This is the strongest signal, and it is written into the record by the passes themselves:

1. **Review rounds counted in decision titles.** `systems/core_dsl.md`: `#14 A fourth ORC-105 pass unified …`; `#15 A fifth ORC-105 pass corrected two errors the fourth pass's own three-valued skeleton: field had baked in`; `#16 A sixth ORC-105 pass … corrected singleton:'s own semantics, both gaps the fifth pass's own record left open`; `#17 ORC-115 (design pass, corrected on two later design reviews)`; `#20 ORC-148 (design pass) reverses the fourth pass's own governing sentence … and retires singleton: outright`; `#27 A design review on ORC-148 corrected two things the pass above got wrong`; `#21`–`#25` are ORC-151's design pass and its **third, fourth, fifth and sixth** design reviews, each titled with what the previous one left standing ("fixes five worked-example defects the third pass's own draft left standing", "fixes three defects the fourth pass's own worked examples and lifecycle mapping left standing", "closes one gap the fifth pass's own fix left open"). `systems/delivery.md #22, #27, #76, #77` carry the same shape ("A sixth ORC-105 pass corrected the fifth pass's own singleton…").

2. **The sibling-statement failure, named.** `core_dsl.md #24`: the critique-adjacency rule "is stated at five sites … six consecutive rounds on ORC-151 each corrected one statement and left a sibling statement stale — `merge`, the reconcile count, `checks`'s position, the child lifecycle, `pending`, and `critique`'s own adjacency rule against itself." `#25`: "The mapping and the worked example describe one type and are edited together: five consecutive corrections had fixed one and left the other disagreeing." `CLAUDE.md` generalizes it: "`docs/dsl-syntax.md` states each load-time rule at least twice by construction … Six consecutive design-review rounds each corrected one statement and left its siblings … that last pair written by one pass, in one document, minutes apart."

3. **Grammar grew inside content tickets, against its own rule.** `core_dsl.md #2` says "The core is frozen; growth happens in extensions"; `#8` records "Four core-grammar growth events landed directly, not through the extension registry (ORC-84)" (`cascade_visit`, multi-hop walks with `~`, `all.<tier>`, edge `instances:`) and `#9` a fifth (`reviews:`); `core_dsl.reasons.md #8` concedes the frozen-core rule "doesn't route these anywhere — there is no extension shaped to hold a scope kind" and that "a missing DSL construct is a `docs/dsl-syntax.md` proposal, not a reason to ship the bundle without the capability". Later additions follow: `#10` depth generalizes to a pair, `#30` a new generator type `supplied`, `#33–#38` declared_in/schema cross-validation (ORC-232/236), `#40` `mint.parent`, `#42` `.synthesis` retires.

4. **Declared-but-inert content that no review caught.** ORC-134 → ORC-184 → ORC-193 (three tickets on one partial); `platform_content.reasons.md #28`: guards "emitted static prose … without ever interpolating `{{ feedback }}`, never showing the model what the feedback said"; ORC-236's title: "mint fields, six reference edges, supplied tiers and walk projections are all declared and none is wired"; ORC-235: "a join target is :approved at mint and an empty all.<tier> walk is vacuously satisfied"; ORC-232: hyphen/underscore mismatch between `decomposition.yaml` and `frontend_sysarch.xsd`. Each is a case of the DSL's declarative surface outrunning what the loader checked.

5. **Coherence sweeps as tickets.** ORC-187 ("six places the record contradicts the tree or itself"), ORC-200 ("retired symbols still referenced live, two stale kind counts"), ORC-106 ("Four decisions Phase 5 builds on were recorded wrong, inconsistently, or not at all"), and its follow-up `93908b2` regrounding a rule that had been justified on a mechanism (`extends:`) the same ticket was about to retire. `CLAUDE.md`'s "A number in prose is a claim no later pass re-derives" lists eight miscounts from one milestone's design reviews.

Net: the record documents, in its own rule ids, at least eleven design-review rounds across ORC-105/115/148/151/155 on the status-sequence grammar alone, each fixing the previous round's residue; the retros carry no reflection on this, only the tickets it generated.
