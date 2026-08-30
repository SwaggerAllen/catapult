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
