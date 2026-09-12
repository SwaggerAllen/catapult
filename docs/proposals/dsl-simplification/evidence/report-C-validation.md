# Report C — `docs/dsl-syntax.md` §13 "Load-time validation" (lines 893-1399)

Scope: lines 893-1399 only (507 lines, 15 blank, 53 bullets, 92 `§` citations).
No other part of the doc was read; nothing was modified.

## PART 1 — Every distinct check §13 states

Axis: C = chain bundle, W = workflow bundle, B = both.
Class: S structural, R referential, P protocol rule, I implementation
constraint / engine narration / negative ("no check"), D derivation.

| # | Check (one line) | Lines | Axis | Class |
|---|---|---|---|---|
| 1 | Unknown fields rejected | 895-896 | B | S |
| 2 | Every cross-reference resolves: edge endpoints, fragment kinds, prompt/schema paths, predicate names | 896-897 | C | R |
| 3 | Scope expressions and generator types come from closed sets | 897-898 | C | S |
| 4 | Type-level acyclicity over the edge-instance graph | 898-899 | C | P |
| 5 | Cardinality shapes well-formed | 899 | C | S |
| 6 | `delivery:` values validated against the platform's fixed protocol vocabulary | 899-900 (restated 919-921) | C | S |
| 7 | Navigation edges absent from readiness walks | 900-901 | C | P |
| 8 | Instance-level constraints (dependency cycles, cardinality counts) deferred to projection time | 901-903 | C | I |
| 9 | `reviews:` names a tier in the loaded union | 907-908 | C | R |
| 10 | Review tier's `context:` is the same set of walks as the reviewed tier's (triad invariant) | 909-912 | C | P |
| 11 | Review tier carries no `scope:`, `draft:`, `produces:` | 913-915 | C | S |
| 12 | A chain referencing a workflow declaration, or a workflow referencing a tier, is an error; no chain/workflow compatibility check exists | 919-926 | B | R (+I negative) |
| 13 | Each gate/environment entry sits between skeleton anchors present in the citing type's array; exits resolve within that array | 927-929 | W | R |
| 14 | A `pending` immediately precedes every generation-shaped entry (sub-array head when grouped, anywhere earlier otherwise), one `pending` per such entry | 930-940 | W | P |
| 15 | A `pending` sits somewhere earlier than every `deploy` | 940-945 | W | P |
| 16 | Every generation-shaped entry has at least one blocked exit | 946-951 | W | P |
| 17 | Fan-out depth is never validated against the chain | 952-956 | W | I (negative) |
| 18 | `depth:` is a non-negative integer or a list of exactly two, on gate / environment / `critique` | 957-964 | W | S |
| 19 | `reconcile` takes no `depth:` (falls under unknown-field) | 965-971 | W | I |
| 20 | `critique` sits immediately after a generation-shaped entry (after that entry's `checks` if declared), in the same array | 972-985 | W | P |
| 21 | There is no `enabled:` field (falls under unknown-field) | 985-988 | W | I |
| 22 | No `depth:` is read by anything today | 988-990 | W | I |
| 23 | Gate's forward exit and escalation policy well-formed | 991-992 | W | S |
| 24 | Gate's declared `throwback:` is earlier in the citing type's array (undeclared decline target is a runtime check) | 992-998 | W | P |
| 25 | `type:` name unique in the loaded union across all skeletons | 999-1001 | W | S |
| 26 | Container-skeleton array holds `setup`,`prep`,`main`,`retro`,`cleanup` each >=1 in relative order, then `terminal` exactly once, last | 1002-1013 | W | S |
| 27 | Ticket-skeleton array opens with `pending` (flattened one level), holds >=1 generation-shaped, `checks`, `merge`, `deploy` in relative order, `terminal` exactly once last | 1014-1029, 1044-1047 | W | S |
| 28 | Every `merge` is preceded earlier in the same array by a `reconcile` (any skeleton) | 1030-1034, 1047-1049 | W | P |
| 29 | The merge/reconcile check is unaffected by `merge` being top-level-only at dispatch | 1049-1056 | W | I |
| 30 | No `after:` field — rejected as unknown | 1057-1060 | W | S (subsumed by #1) |
| 31 | A gate whose role has no holders is an error; opt-in via `role_holders:` resolver, skipped when absent | 1061-1067 | W | R (+I) |
| 32 | Every review state has a mirror-mapping counterpart when the tracker add-on is configured; opt-in `mirror_mapping:` resolver | 1068-1073 | W | R (+I) |
| 33 | Naming discipline: no two states, or state and label, one hyphen apart in meaning | 1074-1076 | W | P |
| 34 | A workflow bundle under the `runtime` dialect is an error | 1077-1078 | W | S |
| 35 | A bundle carrying `extends:` is an error, either axis | 1079-1080 | B | S (subsumed by #1) |
| 36 | `types/<name>.yaml` shape: `type:`, optional `skeleton:` in {ticket, container}, `statuses:` array; one shared registry | 1084-1091 | W | S (+I) |
| 37 | A `statuses:` entry is exactly one of `status:` / `review:` / `environment:`; `status:` from the skeleton's closed set (free if skeleton-less); `review:`/`environment:` resolve in the union | 1092-1098 | W | S + R |
| 38 | `review:`/`environment:` legal in any type's array (no check) | 1099-1104 | W | I (negative) |
| 39 | `flow:` required on population anchors and absent elsewhere; `blocks:` optional there, absent elsewhere; a `review:`/`environment:` entry carrying either is an error | 1105-1121 | W | S |
| 40 | `flow:` names a member of the type registry (a skeleton-less target is legal; no `opens:` field) | 1122-1138 | W | R (+I) |
| 41 | No cross-axis check binds a queue's `flow:` to a chain `flow:` of the same name | 1139-1152 | W | I (negative; restates #12) |
| 42 | `blocks:` resolves to exactly one entry (0 or >=2 is an error, naming the count); §15.6 scoping (other declaration, nested, self) still errors | 1153-1169 | W | R (+P) |
| 43 | Declaration graph (types with a population anchor; `flow:` edges) is acyclic; self-`flow:` rejected; no instance-level ancestor check | 1170-1201 | W | P (+I) |
| 44 | `entry:` required on workflow `bundle.yaml`, resolves, is a graph node, and is a root; no opt-in exemption | 1202-1214 | W | S + R + P |
| 45 | An array-valued `statuses:` entry is a sub-array; the three-key rule applies inside; a nested sub-array is an error | 1218-1224 | W | S |
| 46 | A sub-array holds exactly one non-review-shaped agent-balled `status:` (`generation`,`design`,`architecture`,`implementation`,`retro`,`setup`); `pending`/`critique`/`reconcile` don't count | 1225-1243 | W | S |
| 47 | No check refuses a population anchor inside a sub-array | 1244-1251 | W | I (negative) |
| 48 | `throwback:` check is unaffected by sub-array membership | 1252-1257 | W | P (restates #24) |
| 49 | A `review:` inside a sub-array derives its one-click default to that sub-array's earliest entry; computed, never stored | 1258-1269 | W | D |
| 50 | A `review:` outside every sub-array, or inside one but before its earliest entry, must declare `throwback:` explicitly | 1269-1276 | W | P |
| 51 | `name:` defaults to the `status:` value; plain string, never atomized | 1280-1283 | W | D (+I) |
| 52 | Every name unique within its namespace (top-level array or one sub-array), authored or defaulted | 1284-1291 | W | S |
| 53 | A bare reference resolving in more than one namespace is an error; `<anchor>.<name>` disambiguates | 1292-1297 | W | R |
| 54 | No gate name collides with any addressable status name, bare or qualified | 1298-1301 | W | S |
| 55 | `declared_in` segments checked against the schema of the tier the leading segment names, following same-file `type=` references | 1306-1319 | C | R |
| 56 | An unresolvable segment (`xs:group`, `xs:extension`, imported type) is not an error | 1320-1327 | C | I |
| 57 | Attribute segments (`.@attr`) checked the same way | 1328-1330 | C | R (refines #55) |
| 58 | Non-self `source`/`target` that does not structurally resolve (`self.parent`, `fanout(...)`, singleton) must declare `source_ref:`/`target_ref:` | 1336-1342 | C | P |
| 59 | `fanout(<edge>)` names an edge whose `declared_in` is a path-prefix of the citing instance's | 1343-1346 | C | R |
| 60 | `source_ref:`/`target_ref:` value is one of `self`, `self.parent`, `fanout(<edge>)`, `@<attr>` | 1347-1350 | C | S |
| 61 | Explicit `@<attr>` path gets the declared_in/schema cross-validation | 1351-1354 | C | R |
| 62 | `fields:`/`produces:` `draft.<path>` gets the same schema cross-validation | 1355-1362 | C | R |
| 63 | `mint.parent.<name>` names one of the committing tier's own `fields:` or `produces:` kinds | 1363-1367 | C | R |
| 64 | `scope: reference` and `generator: reference` only legal paired | 1368-1371 | C | S |
| 65 | `reference.<name>` field source only on a `scope: reference` tier; `<name>` not cross-checked | 1372-1378 | C | S (+I) |
| 66 | A `reference`-scope tier declaring `produces:` is an error | 1379-1382 | C | S |
| 67 | An `all.<tier>` walk may not target a `reference`-scope tier | 1383-1388 | C | P |
| 68 | Non-zero cardinality `min` on a `reference`-scope side is an error | 1389-1396 | C | P |
| 69 | A walk projecting `.synthesis` is an error | 1397-1399 | C | S |

Totals (primary class): **S 25** (1,3,5,6,11,18,23,25,26,27,30,34,35,36,37,39,45,46,52,54,60,64,65,66,69); **R 15** (2,9,12,13,31,32,40,42,53,55,57,59,61,62,63); **P 17** (4,7,10,14,15,16,20,24,28,33,43,44,48,50,58,67,68); **I 10** (8,17,19,21,22,29,38,41,47,56); **D 2** (49,51). Total 69.

By axis: chain 25 (2-11, 55-69), workflow 41 (13-34, 36-54), both 3 (1, 12, 35).

Of the 69 rows, 10 are pure I (negatives or engine narration, not author-facing checks), 3 are subsumed by #1 (30, 35, 19/21 also), and 2 are restatements (41, 48). Net distinct author-facing checks: ~54.

## PART 2 — Checks that vanish with the construct they guard

- **Sub-arrays (§15.10):** 45, 46, 47, 48, 49, 50 wholly; the "flattened one level" clause of 27; the sub-array-head branch of 14; the sub-array namespace half of 52, 53, 54 (namespaces collapse to one). Roughly 6 checks plus 4 clauses.
- **Named positions / `name:` (§15.12):** 51, 52, 53, 54 (namespacing and gate/status collision only exist because names are addressable).
- **`flow:` / population anchors / nesting (§15.2, §15.7, §15.8):** 39, 40, 41, 43, 44 (`entry:` root-ness presupposes the graph), and the population-anchor exception in 47.
- **`blocks:` (§15.6/§15.7):** 42, the `blocks:` half of 39, and 53's `blocks:` case.
- **`throwback:` on gates:** 24, 48, 50, and the derived default 49.
- **`depth:` (gate/environment/critique):** 17, 18, 19, 22.
- **`critique` entries:** 20, 21, the critique site of 18, and the critique exclusions in 46.
- **`reconcile`:** 28, 29, 19, the reconcile exclusion in 46.
- **Skeletons (`ticket`/`container`):** 26, 27, 25's cross-skeleton clause, 36's `skeleton:` key, 37's closed-set branch, and the "no skeleton-keyed special case" prose in 43/44.
- **`pending` as a declared entry:** 14, 15, 27's opening clause, 46's `pending` exclusion.
- **Review tiers (`reviews:`) on the chain axis:** 9, 10, 11.
- **`declared_in` / schema paths (ORC-232):** 55, 56, 57, and dependents 61, 62.
- **`source_ref:`/`target_ref:` / `fanout(<edge>)` / `mint.parent` (ORC-236):** 58, 59, 60, 61, 63.
- **`reference` scope/generator (ORC-236):** 64, 65, 66, 67, 68.
- **`.synthesis` projection:** 69 (already retired; the check guards a form with no consumer).
- **Role holders / mirror mapping (external resolvers):** 31, 32 — both are opt-in and skip when the resolver is absent, so they are already effectively conditional.
- **`instances:` on edges** (the prompt's example) is not named in §13; the edge-instance constructs it does guard are 4 (type-level acyclicity), 5 (cardinality shape), 58-59 and 68.

## PART 3 — Restatements within §13

- `delivery:` vocabulary: line 899-900 and 919-921.
- No chain/workflow cross-check: 924-926, 952-956 (fan-out depth form), 1139-1152 (`flow:` form).
- Gate `throwback:` earlier in the citing array: 992-995 and 1252-1257 (the second adds only "sub-array membership is not a bound"); 1265-1269 defers to the same earlier-prefix rule a third time.
- `pending` immediately precedes a generation-shaped entry: 930-940, re-invoked at 1021-1025 ("identical flattening the pending-precedes check above already uses") and 1236-1240 ("the pending-precedes check above").
- "Exactly one of `status:`/`review:`/`environment:`": 1092-1098 and 1218-1221.
- Unknown-field rejection: 895-896, then as specific instances 965-971 (`depth:` on `reconcile`), 985-988 (`enabled:`), 1057-1060 (`after:`), 1079-1080 (`extends:`), 1123-1124 (`opens:`).
- `merge` preceded by `reconcile`: 1030-1034 and 1047-1049 (same bullet, stated twice).
- Generation-shaped entry enumerated (`generation`, `design`, `architecture`, `implementation`): 931, 973, 1016-1017, 1226-1227.
- "Node set read from declared entries, never from `skeleton:` alone": 1127-1134, 1176-1181, 1181-1189, 1208-1210.
- Opt-in resolver shape (`role_holders:`/`mirror_mapping:`): 1063-1067, 1070-1073, 1211-1214.
- `critique` adjacency rule cited back at 1103-1104 and 1228-1230, 1236.
- ORC-232 "two-outcome shape" (resolved-and-wrong vs unresolvable): 1320-1327, 1352-1354, 1361-1362.

## PART 4 — Checklist vs. rationale/narrative

- Total 507 lines (15 blank, 8 sub-headings/intro lines).
- Operative checklist content (the rule plus "is a load error naming X"): roughly **200 lines (~40%)**.
- Rationale, cross-citation, defensive clarification and negatives: roughly **290 lines (~60%)**.
- Per block: opening 9 lines ~90% checklist; review tiers 11 ~70%; two-axes block (917-1080, 164 lines) ~37%; unified declaration (1082-1214, 133 lines) ~30%; sub-arrays (61 lines) ~35%; named positions (24 lines) ~65%; ORC-232 (28 lines) ~40%; ORC-236 (68 lines) ~55%.
- The heaviest single bullets: ticket-skeleton (1014-1056, 43 lines, ~12 operative); declaration graph (1170-1201, 32 lines, ~6 operative); `critique` adjacency (972-990, 19 lines, ~7 operative); `flow:` resolves (1122-1138, 17 lines, ~2 operative).
- Marker counts in the range: `ORC-nnn` 8 hits (all in the two "Added with ..." headers and the ORC-236 cross-references at 1352, 1357, 1362, 1391); "this pass" 0; "revised" 0; "corrected" 0; "round" 0 (the one hit is "around"). So the narrative is not changelog-shaped; it is argument-shaped: "deliberately" 4, "because" 5, "since" 6, "otherwise" 4, "never" 29, "already" 13, "unaffected" 6, and 6 explicit "no check / never validated" negatives. "load error" appears 28 times, which is a fair count of the operative sentences.
- Bullets that are entirely non-checks (0 operative lines): 952-956, 1099-1104, 1139-1152, 1244-1251 — 4 of 53 bullets, ~30 lines.
