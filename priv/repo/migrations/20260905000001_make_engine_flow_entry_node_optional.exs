defmodule Catapult.Repo.Migrations.MakeEngineFlowEntryNodeOptional do
  use Ecto.Migration

  # `systems/engine.md` #ORC-269-2: a flow covering whole tiers names no
  # entry node. The composite `(project_id, entry_node_id)` foreign key
  # stays — a null column skips it — so a flow that does name one is
  # still held to an existing node.
  def up do
    execute("ALTER TABLE engine_flows ALTER COLUMN entry_node_id DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE engine_flows ALTER COLUMN entry_node_id SET NOT NULL")
  end
end
