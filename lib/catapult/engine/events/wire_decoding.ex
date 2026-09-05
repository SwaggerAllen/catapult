defmodule Catapult.Engine.Events.WireDecoding do
  @moduledoc """
  `Commanded.Serialization.JsonDecoder` for every engine event that
  carries a value which started life as an atom and travels the wire
  as a JSON string (`systems/engine.md`'s ORC-226 design pass):
  `ReviewWritten.kind`, `ActiveBundleFlipped.axis`,
  `FindingAdjudicated.disposition`, and `DraftCommitted`'s
  `mints[].status`/`.edge_type` and `edges[].type`. `struct/2`
  restores atom *keys*; it does nothing for these values, and nothing
  downstream ever casts on read — every `Store` insert/upsert goes
  through `Ecto.Changeset.change/2`, which performs no casting.

  Each field is repaired against the legal set `Ecto.Enum.values/2`
  returns for the `Store` schema and column the reducer eventually
  writes it to, never against a value list this module writes out
  itself — the day a value is added to that column's `Ecto.Enum,
  values: [...]`, this sees it on the next call, with nothing to edit
  and nothing that can fall out of sync. This is also why the wire
  string is never handed to `String.to_existing_atom/1` directly: an
  event module's own `@type` spec is not a source of compile-time atom
  literals the way `Catapult.Delivery.ContainerLifecycle`'s inline
  states are, so `atomize/3` matches the wire string against the atoms
  `values/2` already resolved (`Atom.to_string/1` on each) and
  substitutes the one already held, instead of minting an atom from a
  string.

  An unrecognised value is left as the wire string, unchanged, rather
  than raising here: `decode/1` runs before `Catapult.Engine.Reducer`
  ever reaches a `Store` call, and raising here would fire before
  `Catapult.Engine.Projector`'s `error/3` — the site this class's
  crash-loop is actually governed at — is ever reached. The struct
  then reaches its `Store` call exactly as it always would have, and
  an unrecognised value fails as the `Ecto.ChangeError` this class
  already surfaces as, at the site already responsible for it.
  """

  @doc false
  def atomize(value, schema, field) when is_binary(value) do
    schema
    |> Ecto.Enum.values(field)
    |> Enum.find(value, &(Atom.to_string(&1) == value))
  end

  def atomize(value, _schema, _field), do: value
end

defimpl Commanded.Serialization.JsonDecoder,
  for: [
    Catapult.Engine.Events.ReviewWritten,
    Catapult.Engine.Events.ActiveBundleFlipped,
    Catapult.Engine.Events.FindingAdjudicated,
    Catapult.Engine.Events.DraftCommitted
  ] do
  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Events.WireDecoding
  alias Catapult.Engine.Store

  @doc "See `WireDecoding`'s own moduledoc: repairs the atom(s) `struct/2` leaves as bare wire strings."
  def decode(%ReviewWritten{kind: kind} = event) do
    %{event | kind: WireDecoding.atomize(kind, Store.Review, :kind)}
  end

  def decode(%ActiveBundleFlipped{axis: axis} = event) do
    %{event | axis: WireDecoding.atomize(axis, Store.ActiveBundleVersion, :axis)}
  end

  def decode(%FindingAdjudicated{disposition: disposition} = event) do
    %{
      event
      | disposition: WireDecoding.atomize(disposition, Store.ContainerFinding, :disposition)
    }
  end

  def decode(%DraftCommitted{mints: mints, edges: edges} = event) do
    %{event | mints: Enum.map(mints, &decode_mint/1), edges: Enum.map(edges, &decode_edge/1)}
  end

  defp decode_mint(mint) do
    %{
      mint
      | status: WireDecoding.atomize(mint.status, Store.Node, :status),
        edge_type: WireDecoding.atomize(mint.edge_type, Store.Edge, :type)
    }
  end

  defp decode_edge(edge) do
    %{edge | type: WireDecoding.atomize(edge.type, Store.Edge, :type)}
  end
end
