# Report B — `docs/dsl-syntax.md` §15 (lines 1461–3750), workflow-bundle syntax

Subsection extents: §15.1 1468–1865 (398 lines) · §15.2 1866–2196 (331) · §15.3 2197–2231 (35) · §15.4 2232–2366 (135) · §15.5 2367–2456 (90) · §15.6 2457–2555 (99) · §15.7 2556–2709 (154) · §15.8 2710–2810 (101) · §15.9 2811–2860 (50) · §15.10 2861–3227 (367) · §15.11 3228–3623 (396) · §15.12 3624–3750 (127). Total ≈2290 lines, of which ≈313 are inside YAML fences.

## PART 1 — Vocabulary inventory

| Construct | Where | Meaning | Req. |
|---|---|---|---|
| **bundle.yaml** `kind: workflow` | §15 intro, §2 | marks the bundle as workflow-axis | required |
| `gates:`, `environments:`, `types:` | §2 (shown in shipped bundle.yaml) | glob lists of declaration files | required |
| `entry:` | §15.2, §15.6, §15.9 | which root type the plane instantiates for a fresh project; checked against the declaration graph | required (only way to pick a root) |
| `name:`, `version:` | §2 | bundle identity | required |
| (no `extends:`) | §11/§13 | a workflow bundle is forked, never layered | — |
| **types/<name>.yaml** `type:` | §15.2 | declaration name; what `flow:` and a chain `ticket: labels:` reference; unique across the registry | required |
| `skeleton:` | §15.1, §15.2 | `ticket` \| `container` \| omitted (no third value; no `none`) | optional |
| `statuses:` | §15.2, §15.3 | ordered array; array index is the only ordering mechanism | required |
| entry: `status: <kind>` | §15.1 | one of the 20 fixed kinds | one of three entry forms |
| entry: `review: <gate>` | §15.4 | citation of a declared gate; name only | — |
| entry: `environment: <env>` | §15.4 | citation of a declared environment; sits before the `deploy` it targets | — |
| entry: sub-array (`- - status:`) | §15.10 | anonymous grouping of contiguous entries; must contain exactly one non-review-shaped agent-balled entry; no key of its own; not nestable | optional |
| `flow: <type>` | §15.7 | on a population anchor (`prep`/`main`/`cleanup`, or any `status:` in a skeleton-less type): the type dispatched into this queue | required on population anchors, forbidden elsewhere |
| `blocks: [<pos>...]` | §15.7, §15.10 | entry guard: named positions cannot be entered while this queue holds unresolved work; same declaration only; not into nested containers | optional |
| `depth:` on `critique` | §15.5 | fan-out levels the critique tier runs at; `int` or `[first, rest]`; default 0 | optional |
| `name:` on a `status:` entry | §15.12 | authored label; defaults to the kind; unique within its namespace | optional |
| `<anchor>.<name>` reference | §15.12 | namespace-qualified position (one level, anchor = the sub-array's agent-balled entry); required when a bare name is ambiguous | — |
| **skeleton `ticket` backbone** | §15.1 | `pending` → (generation-shaped ⟂ gates, `critique` optional)* → `checks` → `reconcile` → `merge` → `deploy` → `terminal`; all recur except `terminal` (exactly once, last); `pending` recurs once per generation-shaped sub-array | — |
| **skeleton `container` backbone** | §15.1 | `setup`, `prep`, `main`, `retro`, `cleanup` each ≥1 in that relative order, then `terminal` exactly once | — |
| **fixed kinds (20)** | §15.1 table | `backlog`, `pending`, `generation`, `design`, `architecture`, `implementation`, `critique`, `checks`, `reconcile`, `merge`, `deploy`, `validating`, `blocked`, `stubbed`, `setup`, `prep`, `main`, `retro`, `cleanup`, `terminal` | closed |
| generation-shaped subset | §15.1 | `generation`, `design`, `architecture`, `implementation` | closed |
| review-shaped subset | §15.1 | `critique`, `reconcile` | closed |
| population anchors | §15.7 | `prep`, `main`, `cleanup` (+ every `status:` in a skeleton-less type) | closed |
| `ball` column | §15.1 | author / plane / agent / world / varies / — | fixed, not authored |
| agent steps (chain-side, listed here) | §15.1 | `design`, `dev`, `critique`, `reconcile`, `validate` | closed |
| **gates/<gate>.yaml** `review:` | §15.4 | gate name; unique in loaded union; disjoint from every status name | required |
| `role:` | §15.4 | who signs off (bindings supply holders) | required |
| `depth:` | §15.4 | `int` \| `[first, rest]`; default 0; "0 is the rule" | optional |
| `escalation:` | §15.4 | policy (shipped value: `author`) | required (shown in every example) |
| `throwback:` | §15.4, §15.10 | single status overriding the derived landing point; must be earlier in the citing type's effective sequence; mandatory where no default derives | optional/conditional |
| absent by decision: `after:`, `ticket_types:`, `approvers:`, `enabled:`, `singleton:`, `scope:`, `skeleton: none`, `id:` on sub-arrays | §15.3, §15.4, §15.5, §15.7, §15.10, §15.11 | each refused with a reason | — |
| **environments/<env>.yaml** `environment:` | §15.4 | environment name | required |
| `promote_from:` | §15.4 | previous environment; omitted = first | optional |
| `depth:` | §15.4 | `int` \| `[first, rest]`; default 0 | optional |
| `lifetime:` | §15.4 | `persistent` \| `per_ticket` | required (shown) |

Count: **21 distinct key names** (`name`, `version`, `kind`, `gates`, `environments`, `types`, `entry`, `type`, `skeleton`, `statuses`, `status`, `review`, `environment`, `flow`, `blocks`, `depth`, `promote_from`, `lifetime`, `role`, `escalation`, `throwback`); **closed keyword sets**: 20 kinds, 2 skeleton values, 2 lifetime values, 5 agent steps (= 29); **3 structural forms** (sub-array, `[first, rest]`, `<anchor>.<name>`). ≈53 vocabulary items; against that, at least 8 named non-fields.

## PART 2 — Text classification

Approximate lines per subsection (a grammar / b author rule / c engine mechanism / d rationale-history / e YAML):

| § | lines | a | b | c | d | e |
|---|---|---|---|---|---|---|
| 15.1 | 398 | 90 | 60 | 55 | 190 | 0 (lifecycle mapping is prose) |
| 15.2 | 331 | 30 | 40 | 15 | 80 | 164 |
| 15.3 | 35 | 5 | 10 | 0 | 20 | 0 |
| 15.4 | 135 | 20 | 35 | 5 | 45 | 31 |
| 15.5 | 90 | 15 | 25 | 5 | 40 | 7 |
| 15.6 | 99 | 10 | 30 | 15 | 45 | 0 |
| 15.7 | 154 | 15 | 30 | 65 | 35 | 9 |
| 15.8 | 101 | 0 | 10 | 70 | 20 | 0 |
| 15.9 | 50 | 0 | 0 | 5 | 45 | 0 |
| 15.10 | 367 | 25 | 70 | 50 | 200 | 20 |
| 15.11 | 396 | 15 | 60 | 150 | 95 | 78 |
| 15.12 | 127 | 20 | 35 | 45 | 25 | 4 |
| **total** | **2290** | **~245 (11%)** | **~405 (18%)** | **~480 (21%)** | **~840 (37%)** | **~313 (14%)** |

Roughly one line in nine states grammar. §15.8 and §15.9 contain no grammar at all; §15.9's title is literally "…continued".

Eight passages most clearly narrating engine internals in a syntax reference:

1. **1560–1575** — `ContainerLifecycle.inline_dispatch_point?/1` excluding `merge` "by name" against its own moduledoc; the reason the `reconcile` kind was split. Repeated at **3236–3252** with the predicate text and `SystemStatus.agent_balled?/1`.
2. **1952–1961** — `ContainerLifecycle.Sequence` lookups and `container.current_queue` carrying `<anchor>.<name>` "end to end" (ORC-116, ORC-171).
3. **2578–2584** — "A queue is a query, never stored"; `ready_scopes`, `Catapult.Engine.Scheduler` holding no broadcast memory.
4. **2653–2681** — `blocks:` as a once-at-entry guard; "what rules out the eject"; `retro` interrupting itself under a standing-hold reading.
5. **2710–2810** (all of §15.8) — mint vs activation, three causes of backward movement, `ContainerLifecycle` making forward advance, the author's manual `retro`→`main` return.
6. **3010–3021** — `decline_gate.ex` moduledoc, the "unbuilt" command edge, `Catapult.Dsl.Workflow.gate_throwback_problems/2` computing `target in Enum.take(...)`.
7. **3344–3402** — "Dispatched once per tree level", per-instance effective sequences, why a `depth: 2` scope-run cannot narrow a bounce; **3527–3583** the two interlocking merge-cascade rules (parent `reconcile` triggers child merge).
8. **3695–3745** — `FeatureLifecycle.Sequence.resolve_position/3`, `String.to_existing_atom` raising on the throwback path, `Store.tickets_for_project/1`'s `status_kind`/`status_gate` columns.

Honourable mentions: 1608 (`feature_lifecycle/sequence.ex`'s trailing sentinel), 3138–3146 (staleness join, ORC-84/ORC-6, "Phase 7"), 3190–3194 (`board` lane rendering and `throwback_default/3`).

## PART 3 — Rule duplication within §15

| Rule | Statements (line) |
|---|---|
| `merge` needs an earlier `reconcile` in the same array | 1583; 1774–1776; 2112–2114; 3255–3258; comment 2895 |
| `critique` immediately after a generation-shaped entry, or after that entry's `checks` | 1815–1818; 2136–2140; 2159–2163; 2384–2388; YAML 2399–2405 |
| `pending` is the first member of every generation-shaped sub-array | 1668–1672; 1762–1768; 1946–1948; 2108–2110; 2961–2963; 3101; 3205–3208; comment 2886 |
| `reconcile` is required, not opt-in (unlike `critique`) | 1576–1580; 1774; 2373–2375; 3265–3268 |
| `reconcile` carries no `depth:` | 1591–1595; 3403–3405 |
| `reconcile` sits in the flat backbone, not in a sub-array | comment 2019–2026; 3275–3290; comment 3440–3446 |
| exactly one non-review-shaped agent-balled entry per sub-array | 2922–2935; 3132–3134; 3653–3655 |
| gate depth 0 is the rule, not the default (and `merge` "depth-0 by rule") | 2349–2357; 2375–2377; 3485; 3519–3527 |
| `throwback:` is a single optional target, an override not a bound | 2315–2347; 3023–3040; 3211–3216 |
| a gate with no derivable default must declare `throwback:` | 2973–2977; 3078–3090; 3178–3186 |
| legal decline targets = "earlier in the effective sequence" | 2346–2347; 2998–3021; 3150–3163 |
| `[first, rest]` depth form | 2246–2249; 2257–2258; 2434–2440 |
| no `after:` field | 2199–2209; 2261–2264 |
| declaration graph is acyclic; nodes = types with a population anchor | 2118–2127; 2471–2482; 2484–2500; 2510–2514 |
| rootness derived; `entry:` picks the start | 2171–2185; 2516–2527; 2841–2846 |
| `setup`/`retro` are inline, carry no `flow:` | 1939–1942; 2585–2600; 2640–2650; 3218–3224 |
| gates and environments legal on every type | 2153–2166; 2375–2380; 2906–2909 |
| `architecture-review` ≠ `architecture-synthesis-review` | 1699–1707; comment 2040–2046; 2286–2296; comment 3459 |
| names unique within a namespace | 2288–2293; 3671–3680 |
| environment precedes its `deploy` | 1671; 2441–2451 |
| queue is a query, never stored | 2177; 2578–2584; 2775–2777 |
| "this mapping and feature.yaml are edited together" — a rule about the doc itself | 1715–1729 |

Twenty-one rules with two or more statements inside §15 alone, before counting §13's checklist. The `pending`-head rule is stated eight times.

## PART 4 — Observations

**Constructs serving exactly one case in `bundles/default-flow`** (13 files: bundle.yaml, 3 environments, 5 gates, 4 types):

- `blocks:` — one use (`main: blocks: [retro]`, milestone.yaml); the sub-array-reach-through rule exists only for it.
- `[first, rest]` depth — one use (`critique: depth: [2, 0]` in feature.yaml). Every gate and environment declares `depth: 0`, so gate/environment depth is never non-default anywhere.
- `skeleton: container` — one type (milestone); `setup`, `retro`, `prep`, `main`, `cleanup` each appear once, in it.
- no-skeleton type — one (project). `entry:` — one, pointing at it.
- `flow: seed` and `types/seed.yaml` — one queue.
- `lifetime:` — always `persistent`; `per_ticket` is unused. `escalation:` — always `author`. `promote_from:` — two uses, a linear chain.
- `environment:` citations — two (`staging` in feature, `prod` in milestone).
- `throwback:` — all five gates declare it; the doc itself (3040–3113) concludes one of the five (`ux-review`) is redundant, so the field earns its keep in four.

**Constructs with zero cases in the shipped bundle:** `design`, `architecture`, `implementation` kinds (the shipped feature.yaml uses bare `generation` and one sub-array); a recurring `reconcile`; `name:` on a status entry; any `<anchor>.<name>` reference; a gate cited twice by one type; nonzero gate depth; `backlog`, `blocked`, `stubbed`, `validating` in any array (plane-owned kinds, never authored); `types/component.yaml`, `product-review`, `architecture-review`, `architecture-synthesis-review`. This is the most consequential finding: **the §15.2 `feature.yaml` (1991–2075) and §15.11 `component.yaml` (3418–3495) worked examples do not match the shipped `bundles/default-flow/types/feature.yaml`**, which is the §15.10 shape (`pending, generation, critique, ux-review, engineering-review` + flat backbone). §15.1's "edited together" rule (1715) binds the §7.6 mapping to §15.2's example, not to the tree; per repo CLAUDE.md ("the record is what the tree will be made to match") this is either a design that dev has not caught up with or a record that has drifted, and nothing in §15 says which. Three of the four gate files §15.2/§15.11 cite do not exist.

**Engine-derived rather than author-declared:** throwback default (sub-array's earliest entry, §15.10); gate scope own-vs-joined (position relative to nearest preceding `reconcile`, §15.11); whether an instance runs `reconcile` at all (tree position, §15.11); `merge` reaching only the root (§15.11); per-instance effective sequence (depth ceiling × tree shape); rootness (§15.6); namespace identity `<anchor>.<name>` (§15.12); `name:` defaulting to kind; `depth` defaulting to 0; `promote_from` omitted = first; queue membership (a query); the `terminal` guard (undeclarable, §15.7); what a passed gate pins (§15.10/§15.11). The grammar's pattern is consistent: every time a field could restate a derivable fact, the field is refused and a derivation is described instead — which is why so much of §15 is prose about derivations rather than about syntax.

**Grammar or design log?** §15 reads as a design log with a grammar embedded in it. Evidence: 37% of lines are rationale or round-correction narrative; §15.9 is titled "…continued" and contains no syntax; §15.8 contains no syntax; §15.10 spends ~85 lines auditing five shipped gate files one by one; ORC ticket numbers appear inline in YAML comments (1893, 1900, 1904, 1916, 1928, 2044, 3459) and in prose (1958, 1960, 3141–3142); "fourth-pass correction" is cited by the bundle's own comments as the reason for a value; the record narrates its own review history ("disagreed across five consecutive design-review rounds", 1719) — exactly the changelog form the repo CLAUDE.md's "state the rule; do not narrate what it replaced" forbids. The actual grammar — 21 keys, 20 kinds, two skeletons, three structural forms, and ~15 positional load checks — would fit in roughly 250 lines plus the YAML; §13's checklist already holds the load checks once. The remaining ~1700 lines are the reasons, the mechanism, and the history, each stated in two to eight places.
