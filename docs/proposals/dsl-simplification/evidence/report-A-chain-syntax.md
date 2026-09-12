# Report A — `docs/dsl-syntax.md` §1–§14 (lines 1–1460), chain-bundle syntax

Section spans (lines): §1 16–53 · §2 54–105 · §3 106–230 · §3.1 231–276 · §3.2 277–322 · §3.3 323–381 · §4 382–433 · §4.1 434–496 · §4.2 497–593 · (§5 absent) · §6 594–612 · §7 613–640 · §7.1 641–671 · §7.2 672–725 · §8 726–747 · §9 748–807 · §10 808–823 · §11 824–872 · §12 873–892 · §13 893–1400 · §14 1401–1460.

## PART 1 — Vocabulary inventory

R = doc marks required; O = optional; — = unstated. "Closed" members are enumerated exactly as the doc gives them.

### File kinds (§1, lines 25–44)
| File | Meaning | Req |
|---|---|---|
| `catapult.yaml` | repo root; keys `chain:`, `workflow:` (directory names under `bundles/`) | R |
| `bundles/<n>/bundle.yaml` | manifest (§2) | R |
| `tiers/<tier>.yaml` | one tier declaration per file (§3) | — |
| `edges/<edge>.yaml` | one named edge per file (§4) | — |
| `predicates.yaml` | named predicates (§8) | O ("optional") |
| `prompts/<tier>.md.liquid`, `prompts/review/<tier>.md.liquid`, `prompts/partials/<n>.md.liquid` | generation / review / shared fragments (§9) | — |
| `schemas/<n>.xsd` | body grammars (§10) | — |
| `flows/<flow>/flow.yaml`, `flows/<flow>/<prompt>.md.liquid` | one dir per flow (§6) | — |
| (workflow axis) `gates/`, `environments/`, `types/` | §15 material, listed here only | — |

### `bundle.yaml` (§2)
| Key | Meaning | Req |
|---|---|---|
| `name`, `version` | identity | — |
| `kind` | closed: `chain` \| `workflow` | R |
| `tiers`, `edges`, `flows` | glob lists; loaded bundle is the union (chain only) | — |
| `fragments` | closed per-bundle vocabulary of fragment kinds; any `handle:`/`produces:` kind must appear | R (by rule, l.103–104) |
| `gates`, `environments`, `types` | workflow-kind globs | — |
| `entry` | workflow only; names root type the plane instantiates; loader checks 3 things | R (§13 l.1181) |
| `extends` | **forbidden** on either axis (l.63, 99–102, 826–830, 1057) | banned |

### Tier declaration (§3, lines 108–142 block + prose)
| Key | Meaning | Req |
|---|---|---|
| `tier` | name, unique in union | R |
| `scope` | §3.1 closed set | R (absent on review tiers) |
| `scope_filter` | predicate (§8 slot 1) | O |
| `identity` | closed: `id` \| `alias` \| `name` | — |
| `fields` | scalar projections; sources below | — |
| `handle` | `fields: [..]`, `fragments: [..]` — public surface walks read | — |
| `draft` | `root_tag`, `grammar` (XSD path); "omit entirely for join-target tiers" | O |
| `generator` | §3.2 closed set; default `llm` | O (default) |
| `prompt` | Liquid path | — |
| `executor` | `effort:` hint (`max`); "optional; how the generation runs" | O |
| `context` | ordered walk list (§7) | — |
| `produces` | list of `fragment: {owner, kind, authored}` | — |
| `delivery` | extension namespace (§12): `phase`, `agent_step` — values from platform-fixed vocabulary only | — |
| `enforcement` | extension profiles, e.g. `[codegen: restricted]` | — |
| `reviews` | §3.3: marks a review tier for `<tier>` | R on review tiers |
| `grammar` | **top-level** on a review tier only (§3.3 l.331) | — |
| generator-specific (§3.2 prose only): `code_repo_url`, `path_from_handle` (git_commit); `package` (R), `options` (O) (external); `template` (R) (template); `source: input.<role>` (R) (supplied) | | |

**Field sources (closed, 4 — l.144–214):** `draft.<path>` (checked vs schema, §13), `mint.<name>` (row-local, unvalidated), `mint.parent.<name>` (inherited from committing tier's `fields:`/`produces:`, checked), `reference.<name>` (only on `scope: reference`, unvalidated). **Reserved field name:** `argument` (entry tier, never enforced, l.203–214). **Body-declared attrs (not tier keys, l.222–229):** `implementation: stubbed|real`, `swap: transparent|migration|reset`.

**§3.1 Scope — closed (5):** `singleton`, `per(X)`, `child_of(X)`, `cascade_visit`, `reference`. Removed: `per(X) × phase`, `scope_filter: in_cascade_visit_set`.

**§3.2 Generator — closed, extension-growable (8):** `llm` (default), `git_commit`, `synthesis`, `webhook`, `external`, `template`, `supplied`, `reference`. Pairing rule: `scope: reference` ⇔ `generator: reference`.

**§3.3 Review tier:** allowed keys `tier`, `reviews`, `generator`, `prompt`, `grammar`, `context` (must equal reviewed tier's), `delivery`. Forbidden: `scope`, `identity`, `handle`, `fields`, `draft`, `produces`.

### Edge declaration (§4, §4.1, §4.2)
| Key | Meaning | Req |
|---|---|---|
| `edge` | unique name | R |
| `type` | closed (5): `fanout` \| `reference` \| `dependency` \| `policy_application` \| `synthesis` | R |
| `source`, `target` | tier names (inline form) | R (xor `instances`) |
| `declared_in` | path in committing tier's body; synthesis: human-readable only; policy_application: marker `policy.structural`/`policy.required` | R |
| `cardinality` | `source: {min,max}`, `target: {min,max}` (max default unbounded); refinements `when:` (predicate slot 2), `per_source:` | — / O |
| `graph_constraint` | list from `acyclic`, `no_self_loop`, `tree` | — |
| `consistency` | dependency only: `eventual` (default) \| `transactional` | O |
| `navigation` | bool, default false; true = cyclic-legal, banned from readiness walks | O |
| `constraint` | predicate slot 3, e.g. `reaches(source, target)` | O |
| `instances` | list of `{source, target, declared_in, cardinality, source_ref, target_ref}`; mutually exclusive with inline form | — |
| `source_ref` / `target_ref` | locator, closed (4): `self` (default), `self.parent`, `fanout(<edge>)`, `@<attr>`; a `scope: singleton` endpoint needs none; other side defaults to trailing `.@attr` of `declared_in` | O / R when nothing structural applies |

### Flows (§6)
`flow` (R), `delta: {tiers: [], edges: []}`, `walk` closed (2): `downward_cascade` \| `up_then_down`, `ticket: {entry: <tier>, labels: []}` (the delivery face), `completion: <named predicate>` (predicate slot 4).

### Context walks (§7, §7.1, §7.2)
Tokens: `self`, `self.parent`, `.<edge>` (hop; chains allowed), trailing `~` (reversed hop), `-> <tier>.<projection>` where projection ∈ {`.handle`, `.handle.fragments[<kind>]`} (`.synthesis` **retired**, load error), `all.<tier>.<projection>` (no edge; not on `reference` scope), `input.<role>`, `input.*` (reserved variable `raft`), `ticket.findings` (extension source, flow-planning tiers only). Platform roles (4): `project_doc`, `mocks`, `non_goals`, `design_system` (the last read via `supplied`'s `source:`, not a walk).

### Predicates (§8)
Six families: comparison `== != < > <= >=`; boolean `AND OR NOT`; edge counting `has_edge`, `count(...) op N`; existential `exists(path where p)`; universal `all/any(path -> field)`; reachability `reaches(a, b, via=[...])`. Exactly four slots: `scope_filter`, `cardinality.when`, edge `constraint`, flow `completion`. No arithmetic, strings, regex. A `cascade_visit` tier name as path root = every instance for the open flow.

### Prompts (§9)
Liquid/Solid. Variables: one per walk (named by target tier; same-tier walks merge into one collection), `self`, `feedback` (list of maps: `body`, `locator`, `author_id`, `posted_at`), `prior_review` (map: `score`, `findings`, `kind`, `body_sha`), `draft` (review only), `raft` (for `input.*`), `<role>` (for `input.<role>`, plain string). `{% render "partials/<n>" %}`.

### Grammars (§10)
`draft.root_tag` + XSD at commit. Review grammar (platform-wide): `<intro>`, `<score>` 0–100, `<finding id>`. v5 productions: `<permissions>`, `<enforcement>`, `<implementation>`, process inventory, `<tests>`.

### Extensions (§12)
Five registration kinds: annotation namespaces (`delivery:`, `enforcement:`), declaration kinds, generator types, context sources (`ticket.findings`), enforcement profiles (`codegen: restricted`, `purity: replay_floor`). Dialects (2): `design`, `runtime`. Loader inputs named in §13 (not bundle content): `role_holders:`, `mirror_mapping:`.

### Workflow-axis vocabulary that appears inside §13 (not chain grammar)
`type`, `skeleton` (`ticket`|`container`), `statuses`, `status`, `review`, `environment`, `flow`, `blocks`, `throwback`, `depth`, `name`; status kinds `pending`, `generation`, `design`, `architecture`, `implementation`, `critique`, `reconcile`, `checks`, `merge`, `deploy`, `setup`, `prep`, `main`, `retro`, `cleanup`, `terminal`; explicitly non-existent: `after:`, `enabled:`, `opens:`, `gate:`, `requires_gates:`, `review_path:`, `required:`.

**Count.** Chain-axis distinct keys/keywords/members (files excluded, `self`/`self.parent` counted once each): 2 (catapult.yaml) + 12 (bundle.yaml incl. `extends`) + 34 (tier keys incl. generator-specific) + 3 (identity) + 5 (field sources incl. `argument`) + 7 (body attrs) + 5 (scope) + 8 (generator) + 19 (edge keys) + 14 (edge closed members) + 9 (flow keys) + 2 (walk kinds) + 11 (walk tokens incl. retired) + 4 (roles) + 16 (predicate operators/functions) + 15 (prompt variables + map keys) + 7 (grammar elements) + 9 (extension kinds/profiles/dialects) + 2 (loader inputs) ≈ **184**. Workflow-axis tokens leaking into §13: ~35 more.

## PART 2 — Text classification (rough line estimates; a=grammar, b=protocol rule, c=mechanism, d=rationale/history, e=example)

| § | lines | a | b | c | d | e | note |
|---|---|---|---|---|---|---|---|
| 1 | 38 | 30 | 2 | 1 | 5 | 0 | layout block is grammar |
| 2 | 52 | 22 | 8 | 12 | 10 | 0 | `entry:` para narrates loader's three checks and §15.6 derivation |
| 3 | 125 | 40 | 20 | 35 | 30 | 0 | ORC-236 cited 3×; `DraftCommitted`/`mints:` narrative |
| 3.1 | 46 | 12 | 8 | 6 | 20 | 0 | "Delta from v4", "exists for exactly one purpose" |
| 3.2 | 46 | 14 | 5 | 4 | 23 | 0 | five-slots-of-`reference` essay |
| 3.3 | 59 | 18 | 22 | 8 | 11 | 0 | |
| 4 | 52 | 27 | 12 | 8 | 5 | 0 | |
| 4.1 | 63 | 10 | 12 | 10 | 6 | 25 | yaml is default-bundle example |
| 4.2 | 97 | 20 | 20 | 25 | 12 | 20 | every locator justified by a shipped instance |
| 6 | 19 | 12 | 4 | 0 | 3 | 0 | |
| 7 | 28 | 8 | 3 | 2 | 15 | 0 | census of ten `synthesis` tiers |
| 7.1 | 31 | 5 | 8 | 8 | 4 | 6 | |
| 7.2 | 54 | 8 | 12 | 8 | 22 | 4 | role-set governance prose |
| 8 | 22 | 10 | 3 | 6 | 3 | 0 | |
| 9 | 60 | 20 | 8 | 22 | 10 | 0 | engine events, `reviews_for_node/2`, Solid behavior |
| 10 | 16 | 10 | 0 | 4 | 2 | 0 | |
| 11 | 49 | 4 | 12 | 8 | 25 | 0 | |
| 12 | 20 | 14 | 2 | 4 | 0 | 0 | |
| 13 | 508 | 40 | 200 | 120 | 130 | 18 | ~350 lines are workflow-axis (§15) checks; two "Added with ORC-nnn" blocks |
| 14 | 60 | 0 | 10 | 0 | 50 | 0 | |
| **Σ** | **1445** | **~324** | **~371** | **~291** | **~386** | **~73** | grammar proper ≈ 22% |

**Five clearest implementation leaks into a syntax reference:**
1. **l.148–168 (§3)** — `mint.parent.<name>` explained via the committing tier's `DraftCommitted`, "the extraction pass", and "before `mints:` is even built"; also "nothing is read from the store". Engine internals to define a field-source spelling.
2. **l.540–551 (§4.2)** — a singleton endpoint resolves because `scope_key: %{}` and "the same way `Store.get_node_by_scope/3` already resolves"; l.585–593 cites "`references/5`'s own mechanism".
3. **l.753–770 (§9)** — `feedback`/`prior_review` defined by `systems/delivery.md`'s ORC-34 entry, `CommentPosted`/`CommentFeedback`, `reviews_for_node/2`, and Solid's unset-is-empty behavior.
4. **l.847–855 (§11)** — "`Catapult.Dsl.Loader.load_axes/5` builds exactly one chain … no list": a function arity as the rule's evidence.
5. **l.1266–1268 and l.1384–1390 (§13)** — `name:` "never atomized (`Catapult.Dsl.Fields`'s no-`to_atom` discipline)"; a `min` bound "evaluated only once that side's tier is `drained?/1`". Runners-up: l.1039–1047 (`role_holders:`/`mirror_mapping:` resolvers as loader inputs, Phase 7/4+ scheduling), l.1300–1306 ("this bundle factors nearly every element into a named complexType").

## PART 3 — §14 "Deliberately absent"

1. **phases** — dropped with v5 §6; no `phase` dimension.
2. **spawn declarations** — a plane rule keyed to the plan naming its children; not bundle content, not a status transition (v5 §7.10, §7.15).
3. **derived fragments** — context walks at read time do that job.
4. **bundle-side code / open predicates** — closed-vocabulary invariant.
5. **per-project restructuring of the automation protocol** — gates/environments declarable; agent+queue states platform-fixed (v5 §7.10/7.16/7.18).
6. **any cross-axis reference** (`gate:` on a tier, tier name in a gate, `requires_gates:`) — would make the two bundles a matched pair; composability protected.
7. **a second bundle system for delivery config** — one language, two document kinds (v5 §9, §7.18).
8. **`review_path:` on a review tier** — a review projects to comments, never a committed file (§7.19).
9. **per-tier `required:` gating flag** — threshold gating is a parked scheduler item, not bundle content.
10. **milestone boundary ticket (pause-proxy)** — Catapult owns its tracker, so container state lives on the entity; explicitly "not the same absence as no retro".
11. **stored per-queue ticket bucket** — a queue is a derived query; a stale bucket is worse than none (same reason as `ready_scopes`).
12. **retro note** — containers keep references to archived work, removing the duplicate-detection premise.
13. **`archive`-precedes-every-queue load check** — the failure it would guard cannot occur; "a check without its reason".

§13 also declares absences that belong here: no `after:` (l.1031), no `enabled:` (l.967), no `opens:` (l.1094), no chain/workflow compatibility check (l.927), no instance-level ancestor check (l.1165), `reconcile` not a `depth:` site (l.951).

## PART 4 — Observations

**Overfit to the default bundle (construct justified by one shipped case):**
- `cascade_visit` scope: "Exists for exactly one purpose: a flow's planning tier" (l.244).
- `scope: reference` + `generator: reference`: "a ref — the sole tier at this scope today" (l.254); exclusivity of the pairing is a rule written to stop a hypothetical second shape (l.259–264).
- `supplied` generator exists for `design_system`; `external` for the registry (l.279–290).
- `type: synthesis` edge's only motivating case is the cascade-planning correspondence (l.415–418).
- `fanout(<edge>)` locator is defined by `fulfills`'s `comp → resp` instance (l.520–531); the `@<attr>` form "for the six same-tier `dependency` instances this form exists for" (l.556–557).
- `mint.parent.<name>` is specified through `comp.project_techspec` and `subcomp.parent_techspec` (l.173–183).
- `argument` reserved field exists for one UI screen (l.203–214).
- The four `input.<role>` names are admitted by "which shipped tier reads it" (l.695–704, 710–712) — bundle census as grammar.
- §7 l.629–633 enumerates ten default-bundle tiers by name inside a retirement note.
- §13 l.1300–1306 tunes the schema check to how "this bundle factors" its XSD.

**Defined more than once:**
- `extends:` forbidden — §1 comment, §2 (l.63, 99–102), §11 (l.826–830), §13 (l.1057).
- Review-tier omitted keys — §3.3 lists six (`scope`, `identity`, `handle`, `fields`, `draft`, `produces`); §13 l.916–919 checks only three (`scope`, `draft`, `produces`). `identity`/`handle`/`fields` are never made a load error.
- Review `context:` equality — §3.3, §9 (l.805–807), §13 (l.911–915).
- `delivery:` fixed-vocabulary rule — §3 comment, §3.3, §11, §13 (l.922–928).
- `.synthesis` retirement — §7 and §13 (l.1397–1400).
- `reference` scope/generator pairing — §3.1, §3.2, §13.
- `source_ref`/`target_ref` rules — §4.2 (list, then restated l.568–584) and §13 ORC-236 block (l.1334–1350).
- "role with no docs never blocks readiness" — §7.2 and §9.
- `catapult.yaml` names one chain — §1, §11.

**Contradictions / inconsistencies inside §1–14:**
- **Missing §5 is visible as an orphan**: l.490–495 ("Authored-only … Declared in `bundle.yaml`'s closed vocabulary; written via `produces:`; read via `handle.fragments`") is a fragments paragraph sitting at the end of §4.1 with no subject — almost certainly the body of a deleted "§5 Fragments" heading. Fragment/`produces` forms consequently have no owning section.
- `grammar:` sits under `draft:` on a generation tier (l.118) but at top level on a review tier (l.331); §10 calls the review grammar "platform-wide" while §3.3 shows a bundle-relative path. Two positions, one key.
- §4 l.408: "`type: synthesis` is the **one** exception" to `declared_in` parsing against committed bodies — but §4.2 l.585–593 makes `policy_application` a second (its `declared_in` is a marker on the minting element).
- §3.1 l.250–252: `reference` is "the one shape none of the **three** above can express" — four scopes precede it; `cascade_visit` is silently omitted (the exact numeral-in-prose defect CLAUDE.md warns about).
- §4 l.400–402 requires type-level acyclicity over the full edge-instance graph, yet `navigation: true` edges are "cyclic-legal" (l.428) — whether navigation edges are excluded from that check is never stated.
- §9 l.753–755 says ORC-34 "pins this against the ambiguity §3.3 leaves", but §3.3 l.361–365 already states `draft`/`prior_review` handling unambiguously — a stale correction narrative.
- §7.2 lists `design_system` as an `input.<role>` walk, then says it is read through `supplied`'s `source:` "rather than a `context:` walk" (l.700–703): listed in the walk vocabulary while not being one.
- §12 says extensions add "declaration kinds (new file types — the flow ticket face)", but §6 shows `ticket:` as an inline key on `flow.yaml`, not a file type. Likewise `delivery:` is "extension-provided" (§3, §12) yet its values are validated against the core's fixed §15.1 vocabulary (§13 l.922–924) — extension in name, core in substance.
- §4.2 l.516 cites `produces:` `owner:` as "(§4)"; it is defined in §3.
- Generator-specific keys (`code_repo_url`, `path_from_handle`, `package`, `options`, `template`, `source`) exist only in §3.2 prose and never in §3's tier block, so the block is not the full key set it presents itself as. Similarly `fields:` is glossed "scalar projections of body content" (l.111) while three of its four sources are not body content.
- §3's `handle.fields: [id, name]` names `id`, which is not in the tier's `fields:`; whether identity is implicitly a field is unstated.
