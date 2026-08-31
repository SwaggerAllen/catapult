# Retro — Tech debt · before the product tier

Shipped (archived from the tracker; this note is what duplicate detection reads, and what the rehearsal reset reverts):

- ORC-113 — Make the storybook preview publish a real export (merged 5b29bfafcc01e8791dc4e0f5f6d8d1f55e85cff0)
- ORC-115 — Group workflow statuses into subflows and derive throwback structurally
- ORC-116 — Render subflows as a visual grouping on the work surface (merged 6fbb3a1565bc2c97f753caa8268126b635720ffb)
- ORC-119 — FeatureLifecycle.Projection's moduledoc still claims gate-approval is dormant until Phase 7 (merged 52de4583267084f407f809335db1f9301f1dcff8)
- ORC-121 — event_store_test.exs is not rerun-safe against a persistent test event store (merged 2628ecb59844e2878b5efb089e562a335b85d839)
- ORC-129 — board/ticket's child roll-up has no data source in Phase 4 — Flow carries no parent-flow reference
- ORC-130 — board's label filter has no per-instance data to filter against — the screen doc describes it as shipping and it does not function (merged 6e0759628cfbf16b7cf0e7653a2a7c6f38c8f269)
- ORC-131 — ci.yml's sobelow --ignore Config.HTTPS rationale ('no Phoenix endpoint') is false since ORC-35, and the ignore is still armed
- ORC-134 — Five default-bundle prompts guard on {% if feedback %}, which Liquid/Solid truthiness will never treat as an empty list as false (merged 3cfa077addefe4de438057dd683c2935535246c4)
- ORC-141 — Build the subflow machinery: load sub-arrays, derive throwback, narrow throwback: to one target (merged 21f2502ccf397be52dc9bacd11bbdcc5232b18b0)
- ORC-148 — Retire singleton and the container/ticket functional split: setup and retro become sub-arrays with their own generation (merged 3b3ccac25de2fc1de5e405b33070f25c7a241886)
- ORC-151 — Review-shaped statuses: split reconcile from merge, and derive gate scope from position (merged a446e4b1d9ff664d2e5da29e7e2723a0e5dcd760)
- ORC-155 — Give a status entry a name distinct from its kind, and namespace positions by their subflow anchor (merged 71009c216e0394e69b1d332e588ff7a4bec50a3e)
- ORC-171 — Runtime position-tracking resolves a bare kind/gate name with no namespace awareness — a bundle the loader now permits can silently corrupt a live instance (merged ea69e1983221e9994b92d0937288d145d2db45dd)
- ORC-172 — @ticket_status_names rejects most of the fixed vocabulary a ticket-skeleton array is documented to legally hold (merged f4cdc2af74da170337ff020949b25825056934ae)
- ORC-174 — throwback_default/3 still derives the sub-array's agent step, not its own leading pending, for a generation-shaped group (merged 4e29e44b2546e157b1534d415cec5f97486a484e)
- ORC-175 — Container-as-dispatch-target executor/mutex/DispatchRun work is still unbuilt
- ORC-176 — setup/retro's own generation-to-deploy progression is no longer placeable by FeatureLifecycle (merged 7439c1be85fb9fc35a805891f1f714f26a3e9b7a)
- ORC-177 — ContainerLifecycle's repopulation/backward-move semantics still implement the design's own retired reading (merged 27e0bffefdafd8d17eaf590151c19f9f910c32cb)
- ORC-179 — Which generation kind (design/architecture) each bundle chain tier picks is still undecided — deliberately deferred (merged 3e2bee0f0fbbb5143319d5fc654484ec7e9373dc)
- ORC-181 — dsl-syntax.md §15.10 doesn't settle the derived default for a gate sitting before its own sub-array's agent step
- ORC-182 — Sequence.positions/2 truncates at the first :checks entry, not the last one before merge (merged 047292ec14d9a01270dbf4c598abf436c4ebebc7)
- ORC-183 — No CSS build pipeline for the dashboard — every daisyUI class in storybook/screens/** is unstyled (merged b2dd679b94c37b43e00f54fd1e9867171e0fa1d4)
- ORC-184 — partials/_architecture_framing.md.liquid's own feedback-revision block never renders — {% render %} isolates scope from every one of its 9 call sites (merged 75f705ada92dd9352d02f2b20e7cc85189e26f21)
- ORC-187 — Docs coherence sweep: six places the record contradicts the tree or itself after ORC-141/148/151/155
- ORC-188 — board_live and ticket_live's moduledocs still route a code reader to a Linear hand-back for a decision that now has a real home (merged 242e73a163e19e99fa9b7912bfeabaec1c03e7e4)
