# DSL audit (E): loader surface vs. plane consumption

Scope: `lib/catapult/dsl/*.ex` (27 files, 6034 lines) and every reader of `Catapult.Dsl.*` outside it. Tree state as of `bdfd150` (post ORC-236 `917a5dc`). No files modified; `docs/dsl-syntax.md` not read.

## PART 1 — Loader surface

### Modules

| Module | Lines | Parses / validates |
|---|---|---|
| `loader.ex` | 97 | Entry: dialect → registry → `catapult.yaml` → chain + (design only) workflow; unions all problems. |
| `dialect.ex` | 41 | Two fixed dialects (`design`, `runtime`); extension list empty in both. |
| `registry.ex` | 109 | Union of extension namespaces/kinds/generator types/context sources/enforcement profiles; collision check. Empty in practice. |
| `extension.ex` | 76 | Behaviour with empty defaults. No implementer exists. |
| `catapult_yaml.ex` | 57 | `chain`, `workflow` keys; `workflow` required (design) / forbidden (runtime). |
| `manifest.ex` | 104 | `bundle.yaml`: name/version/kind + per-kind globs; unknown-key rejection. |
| `yaml.ex` | 42 | One YAML read (must be a mapping); sorted glob. |
| `fields.ex` | 200 | Shared `{value, problems}` accessors; `depth` grammar; `unknown_keys`. |
| `chain.ex` | 770 | Chain bundle: parses tiers/edges/flows/predicates, then 13 cross-reference passes (§13). |
| `tier.ex` | 510 | One tier (generation or review form): closed sets, per-generator opts, structural shape. |
| `edge.ex` | 303 | One edge: type/graph_constraint/consistency closed sets; inline-vs-`instances:` exclusivity; cardinality bounds. |
| `edge_locator.ex` | 221 | `source_ref`/`target_ref` locator resolution (`self`, `self.parent`, `fanout(e)`, singleton, `@attr`); shared with Extraction. |
| `declared_in_schema.ex` | 425 | Walks each tier's XSD to check `declared_in`, `draft.*` field/produces paths and `@attr` refs exist. |
| `context_walk.ex` | 234 | Parses one walk string: `self[.parent]`, hops with `~`, `-> tier.proj`, `all.tier.proj`, `input.*`, `ticket.*`. |
| `predicate.ex` | 317 | Recursive-descent parser for the §8 predicate language → AST. |
| `predicates_file.ex` | 51 | `predicates.yaml` name → AST. |
| `flow.ex` | 112 | One flow: `delta.{tiers,edges}`, `walk` (closed), `ticket.{entry,labels}`, `completion`. |
| `graph.ex` | 59 | libgraph acyclicity/cycle finder (self-loops dropped). |
| `grammar.ex` | 97 | Commit-time XSD validation of a draft body (not load-time). |
| `bundle_path.ex` | 35 | Bundle-relative path resolution with escape guard. |
| `workflow.ex` | 1158 | Workflow bundle: gates/environments/types, 24 cross-checks, plus runtime throwback API. |
| `gate.ex` | 83 | One gate: `role`, `depth`, `throwback`, `escalation`. |
| `environment.ex` | 68 | One environment: `promote_from`, `depth`, `lifetime` (closed). |
| `type.ex` | 396 | One type: `skeleton`, flattened `statuses` + sub-array `groups`; §15.12 namespaced positions. |
| `status.ex` | 225 | One statuses entry: exactly one of `status`/`review`/`environment`; `name`, `flow`, `blocks`, `depth` gating. |
| `system_status.ex` | 226 | Fixed vocabulary table (20 kinds, 5 agent steps) and shape predicates. |
| `error.ex` | 18 | Two boundary error kinds. |

### YAML keys read (V = parsed-and-validated beyond shape, S = parsed-only/stored, R = rejected-unknown)

Every mapping the loader reads passes `Fields.unknown_keys` (manifest, catapult.yaml, tier, handle, draft, produces entry, delivery, edge, instance, cardinality, cardinality side, flow, delta, ticket, gate, environment, type, status entry). So **any key not listed below is R**, with one deliberate hole: `Tier.extra = Map.drop(raw, @core_keys)` is always `%{}` because unknown keys already failed the load.

**catapult.yaml**: `chain` V, `workflow` V (dialect-conditional).
**bundle.yaml**: `name` S, `version` S (never compared), `kind` V, `tiers`/`edges`/`flows`/`fragments` (chain) V, `gates`/`environments`/`types`/`entry` (workflow) V.
**tier**: `tier` V (dup check); `scope` V (`singleton|per(X)|child_of(X)|reference|cascade_visit`, X must exist); `scope_filter` V (predicate parses/names); `identity` V (`id|alias|name`); `fields` V (string map; `draft.*` paths XSD-checked; `mint.parent.<n>` must be provided by fanout source; `reference.*` only on reference scope; `mint.<n>` **unvalidated by design**); `handle.fields` S (strings only, never checked against `fields`), `handle.fragments` V (in bundle vocab); `draft.root_tag` S, `draft.grammar` V (file must resolve for XSD walk, else silently unresolvable); `generator` V (closed 8); per-generator opts: `code_repo_url`/`path_from_handle` (git_commit) S, `package`/`options` (external) S, `template` S, `source` (supplied) V (`input.<role>`); `prompt` V-ish (required for llm; existence only checked at dispatch); `executor` **S (any map, never inspected)**; `context` V (walk parse + hop/side/target/navigation/reference-scope/ticket-source checks; review tier's must equal reviewed tier's); `produces[].fragment.{owner,kind,authored}` V (owner `self`/`self.parent`, kind in vocab, `draft.*` XSD-checked); `delivery.{phase,agent_step}` V (against SystemStatus); `enforcement` V (against an always-empty registry, so any value fails); `reviews` V (tier exists; forbids scope/identity/fields/handle/draft/produces); `grammar` (review tier) S.
**edge**: `edge` V; `type` V (closed 5); `source`/`target` V (tiers exist; type-level acyclic); `declared_in` V (XSD-walked when `<tier>.draft.*`; other shapes pass); `cardinality.source/target.{min,max}` V (ints; non-zero min on reference tier refused); `cardinality.when` V (predicate parses), `cardinality.per_source` **S**; `source_ref`/`target_ref` V (form + locatability + `@attr` XSD); `instances[]` V (same, non-empty, exclusive with inline); `graph_constraint` V (closed 3); `consistency` V (closed 2, dependency-only); `navigation` V (boolean; walk over it refused); `constraint` V (predicate parses).
**predicates.yaml**: `<name>` V (parses).
**flow**: `flow` V; `delta.tiers`/`delta.edges` **S (never resolved against tiers/edges)**; `walk` V (closed 2); `ticket.entry` V (tier exists); `ticket.labels` S; `completion` V (parses).
**gate**: `review` V; `role` S (opt-in holders check, never passed); `depth` V (shape only); `throwback` V (resolves earlier in each citing type); `escalation` **S (free string)**.
**environment**: `environment` V; `promote_from` V (exists, acyclic); `depth` V (shape); `lifetime` V (closed 2).
**type**: `type` V; `skeleton` V (closed 2 + backbone rules); `statuses[]` V (flattened; sub-array anchor count; nesting refused).
**status entry**: `status` V (ticket-skeleton names ∈ SystemStatus; pending/critique/reconcile/merge positional rules); `name` V (uniqueness per namespace, gate disjointness); `review` V (gate exists); `environment` V (exists); `flow` V (type exists, declaration graph acyclic, entry is root); `blocks` V (resolves, not self, unambiguous); `depth` V (shape; only on critique).

## PART 2 — Consumers

Boundary: `Catapult.Dsl.load/2` and `validate_draft/5` only. Callers of `load`: `Generation.Sweeper`, `Generation.DispatchWorker`, `Generation.CommitPath`, `Delivery.Provisioning`, `Engine.Scheduler/Sweeper/Projector`, the LiveViews. Everything else reads struct fields directly.

**Chain-level**: `chain.name` → bundle dir (ContextAssembly, CommitPath). `chain.tiers`/`chain.edges` → everywhere below. `chain.predicates` → only via `Chain.resolve_predicate/2` (ReadyScopes). `chain.fragments`, `chain.flows` → **no consumer** (flows: `Dsl.Flow` is referenced by nothing outside `dsl/`; engine `OpenFlow.flow_name` is a *workflow type* name, not a chain flow).

**Tier fields**
- `scope` → ReadyScopes `candidates/3` (`singleton`/`per`/`child_of`; `cascade_visit` → `[]`), `drained?/3`, EdgeLocator. Real semantics.
- `scope_filter_raw` → ReadyScopes → PredicateEvaluator. Real.
- `identity` → Extraction `identity_field/2` (attr/text lookup, `alias` fallback for `id`). Real.
- `fields` → Extraction: `draft.*` read at commit (CommitPath merges into node.fields); `mint.<n>`/`mint.parent.<n>` resolved in `mints/7` at fanout time; `reference.<n>` **no consumer** (no write path creates reference nodes anywhere in `lib/`). ORC-236 wiring is present.
- `handle_fields`/`handle_fragments` → ContextAssembly `render_node/3` projects them into template variables. Real (but never checked against `fields` keys at load).
- `draft` → `root_tag`/`grammar` to `validate_draft` (CommitPath); presence gates `generation_tier?`, `mint_status` (`:approved` if nil), `dispatchable?`. Real.
- `generator` → Sweeper/Provisioning (`"llm"` dispatches; `"supplied"` mints via `generator_opts.role`), ReadyScopes (`supplied`/`reference` settled unconditionally). `git_commit`/`external`/`template`/`webhook`/`synthesis` **have no executor**; their opts are never read.
- `prompt` → ContextAssembly (Solid render). Real.
- `context` → ReadyScopes (readiness), Staleness, ContextAssembly (variables), all via ContextResolver. Real.
- `produces` → Extraction `produces/3` (only `self.parent` owner works; `self` returns `{:error, :self_not_yet_known}` so `owner: self` is validated at load and **silently dropped at runtime**). Reducer applies fragments; ContextAssembly renders via `Store.fragments`.
- `reviews` → ReadyScopes `ready_review`, ContextAssembly (reviewed tier's context + `draft` var), CommitPath, Sweeper, ExplainWhyLive.
- `grammar` (review) → CommitPath `validate_draft(..., "review", ...)`.
- `executor`, `enforcement`, `delivery`, `extra`, `generator_opts` (except `supplied.role`) → **no consumer found**.

**Edge fields**
- `type` → Extraction (`fanout` mints; `reference`/`dependency` via EdgeLocator; `policy_application` mint-time markers; `synthesis` **no consumer**), ReadyScopes `child_of_drivers` (fanout sources).
- `instances[].source/target/declared_in` → Extraction, ReadyScopes, GraphConstraints. `source_ref`/`target_ref` → Extraction `instance_edges/4` via EdgeLocator. Real (ORC-236 wired).
- `cardinality.{source,target}.{min,max}` → GraphConstraints (`max` always, `min` once `drained?`) — **reported, never blocking**, and `GraphConstraints.violations/2` itself has **no caller outside tests** (grep: only its own module). `cardinality.when`, `per_source` → explicitly not evaluated (module doc).
- `graph_constraint` → GraphConstraints (same non-blocking, uncalled path). Load-time only checks type-level acyclicity.
- `consistency`, `navigation`, `constraint_raw` → **no runtime consumer** (`navigation` and `constraint` are load-time only; `consistency` is stored and never read — engine `e.type == :dependency` is the store's own column).

**Context walks**: `~` reversal **is implemented** (ContextResolver `landings/2` uses `Store.edges_to`). `all.<tier>` **is implemented** (`Store.list_nodes` + `drained?` gate, ORC-235). `self.parent` implemented. `input.*` → `{:ok, []}` for readiness; ContextAssembly reads Delivery directly. `ticket.<source>` → `{:error, :unsupported}` everywhere (and can never load: registry has no context sources). Projection `:handle`/`{:fragments, k}` → ContextAssembly `render_node/3` (ORC-236 wired).

**Predicates**: only the `scope_filter` slot is evaluated (PredicateEvaluator, called from ReadyScopes). `cardinality.when`, edge `constraint`, flow `completion` are parsed and never evaluated. `reaches`, `exists`, `all/any`, `count`, `has_edge` are implemented in the evaluator but nothing in `bundles/default` reaches them except through `scope_filter`.

**Flows**: `delta`, `walk`, `ticket.entry/labels`, `completion` → **no consumer**. `cascade_visit` scope → `[]` candidates.

**Workflow**
- `entry` → **no consumer** (validated as root type; nothing mints the first container from it — Provisioning does not read it).
- `gates[].role` → `CatapultWeb.Live.Positions.role/2` (display); `ApproveGate` explicitly does not check it. `throwback` → `Workflow.throwback_default/3` (DocumentReviewLive, ContainerQueues). `depth`, `escalation` → **no consumer**.
- `environments[]` → only existence check for `environment:` citations; `promote_from`, `lifetime`, `depth` → **no consumer**. An `environment:` entry is dropped from both Sequence modules (`to_position`/`to_step` → nil).
- `types[].skeleton` → BoardLive (ticket types), ContainerLifecycle `nests?` (`[nil,"container"]`). `statuses`/`groups` → FeatureLifecycle.Sequence, ContainerLifecycle.Sequence, ContainerQueues, Composition via `Type.namespaced_positions/group_at/anchor_index`. Real.
- `Status.status/review/environment/name` → both Sequences. `flow` → ContainerLifecycle `mint_child`/`nests?`. `blocks` → ContainerQueues `held_or_resolved`. `depth` → **no consumer**.
- Runtime API on `Workflow`: `throwback_targets/legal?/target_details/default`, `approve_leaves_group?` → DocumentReviewLive, DraftResolution, FeatureLifecycle.

**ORC-236 status**: the commit's seven items are wired — mint fields (`Extraction.resolve_mint_field`), `source_ref`/`target_ref` (EdgeLocator shared by Chain and Extraction), supplied tiers (`Sweeper.mint_supplied`), walk projections (`render_node/3`), cardinality/graph_constraint (GraphConstraints, but with no production caller), `reference` scope settled/never-drained (ReadyScopes). Still unwired after it: `reference.<name>` field sources (no write path), `produces` with `owner: self`, and `GraphConstraints.violations/2` surfacing anywhere.

## PART 3 — Load-time validation in code

Problems are strings, not error kinds: the boundary collapses them into **2** `Catapult.Dsl.Error` kinds (`:dsl_catapult_yaml_invalid`, `:dsl_bundle_invalid`, each with `problems: [String.t()]`). `Grammar` adds **4** commit-time failure atoms (`schema_not_found`, `malformed_xml`, `root_tag_mismatch`, `schema_invalid`). Counting distinct message templates:

- Generic shape (`Fields`, `Yaml`): 12 — missing required; not non-empty string; not string; not one-of; not boolean; not map; not list of strings / non-string entry; depth shape; unknown field; file missing; unparseable; not a mapping.
- Loader/CatapultYaml/Manifest/Registry: 4 — unknown dialect; workflow under runtime; kind/axis mismatch; duplicate extension registration.
- Predicate parser: 7; PredicatesFile: 1.
- ContextWalk: 12 (arrow count, bad source, empty, arrow without hop, empty hop, bad target, bad projection, `all` form ×2, `input` form ×2, `ticket` form ×2 → 12).
- Tier structural: 10 (review key type; review-forbidden keys; scope grammar; string-map; produces list/entry shape; reference/generator pairing ×2; reference draft/produces ×2; `reference.*` off reference scope; supplied source).
- Edge structural: 9 (both/neither/empty/not-list/not-mapping instances; min/max ints; graph_constraint set; consistency on non-dependency).
- Chain cross-reference: 28 (duplicates ×3 labels; scope target; 4 predicate slots; endpoint; type-level cycle; declared_in/field/ref schema mismatch ×3; locator form; unlocatable side; reference-tier min; mint.parent provider; reviews target; review context mismatch; handle fragment vocab; produces vocab; produces owner; walk edge undeclared; walk side mismatch; no landing; navigation edge; walk target; all-on-reference; ticket source; delivery phase; agent step; enforcement profile; flow ticket.entry).
- Type/Status structural: 7 (skeleton; statuses missing/not list; nested sub-array; anchor count 0/many; entry has none/several of status-review-environment).
- Workflow cross-reference: 36 (duplicates ×3; throwback ambiguous/not-earlier; promote_from missing/self/cycle; naming discipline; role holders; mirror mapping; 2 platform-defect self-checks; container missing/terminal-close/terminal-dup/order; ticket invalid-names/open-pending/close-terminal/terminal-dup/missing/order; merge-without-reconcile; pending un-spent/grouped-first-not-pending; critique adjacency; name dup top-level/group; gate-status collision ×2; flow/review/environment unresolved; blocks self/ambiguous/unresolved; flow self; declaration cycle; entry unresolved/no-anchor/not-root).

**≈126 distinct load-time problem templates**, 2 boundary kinds, 4 commit-time kinds.

## PART 4

**Pure pass-through / opaque (implementation config, not protocol).** A large share of the loader's surface is validated in detail and then read by nothing: tier `executor`, `enforcement`, `delivery.{phase,agent_step}`, every generator-opts block except `supplied.source`, the whole `flows/` declaration (`delta`, `walk`, `ticket`, `completion`), edge `consistency`, `navigation` (load-time only), `constraint`, `cardinality.when`/`per_source`, gate `depth`/`escalation`, environment `promote_from`/`lifetime`/`depth`, status `depth`, workflow `entry`, manifest `version`, bundle `fragments` (vocabulary only), and `ticket.<source>` walks (unloadable in any case since the registry is empty). `generator` beyond `llm`/`supplied`/`reference` (`git_commit`, `external`, `template`, `webhook`, `synthesis`) is a closed set with one executor. The extension mechanism (`Dialect`/`Registry`/`Extension`) is a fully built seam with zero registrations, meaning `enforcement:` and `ticket.*` cannot be authored at all today. `prompt`, `draft.grammar` and `handle.fields` are opaque strings whose only runtime meaning is "a file path Solid/xmerl opens" or "a key into `node.fields`"; the loader checks neither that `handle.fields ⊆ fields` nor that `prompt` exists. `cardinality`/`graph_constraint` sit in between: real evaluator, no production caller, non-blocking by design. These are candidates for "implementation config": nothing the engine does changes if they are removed or renamed, and several (flows, executor, delivery) encode a future the plane has not built.

**Real semantics enforced by the engine (protocol).** The chain axis's live core is: `scope` (candidate enumeration, `drained?`), `scope_filter` (the one evaluated predicate slot), `identity` (node ids and scope keys), `fields` sources `draft.*`/`mint.*`/`mint.parent.*` (Extraction at commit and mint), `handle.{fields,fragments}` (context projection), `draft.{root_tag,grammar}` (commit-time XSD rejection and generation-tier gating), `generator ∈ {llm, supplied, reference}`, `prompt`, `context` walks including `~`, multi-hop, `self.parent`, `all.<tier>` and `:handle`/`{:fragments,k}` projections, `produces` (owner `self.parent` only), `reviews`, edge `type` (`fanout` mints with parent linkage; `reference`/`dependency` via the five-kind EdgeLocator shared with the loader; `policy_application` markers), `instances[].{source,target,declared_in,source_ref,target_ref}`. The workflow axis's live core is: `types[].statuses` as an ordered, sub-array-grouped sequence (`Type.namespaced_positions`, `group_at`, `anchor_index` drive both lifecycle Sequences, ContainerQueues, throwback legality/default, `approve_leaves_group?`), `status`/`review`/`name` entries, `flow:` (child container minting), `blocks:` (queue holds), `skeleton` (`ticket` vs container nesting), gate `role` (routing display) and `throwback` (decline landing), plus the fixed `SystemStatus` table whose shape predicates (`agent_balled?`, `review_shaped?`, `generation_shaped?`) decide inline dispatch and sub-array anchors. This is the set where a load-time rule has a matching runtime read, and where the loader's checks (locatability, XSD path walks, reference-scope refusals, throwback-earlier, gate/status disjointness) exist because a specific runtime failure was observed.
