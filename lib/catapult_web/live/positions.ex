defmodule CatapultWeb.Live.Positions do
  @moduledoc """
  `Catapult.Delivery.FeatureLifecycle.Sequence.position/0` rendered and
  round-tripped through HTML — shared by `board` and `ticket`
  (`screens/board.md`, `screens/ticket.md`), both of which place a
  ticket from the identical `{:kind, atom()} | {:gate, String.t()}`
  shape `Catapult.Delivery.Store.tickets_for_project/1`'s
  `status_kind`/`status_gate` pair already carries.

  Rendering only: no screen introduces a vocabulary of its own here
  (`docs/ui-spec.md` §2) — every function below is a pure reshape of a
  position the engine/delivery layer already produced.
  """

  alias Catapult.Delivery.FeatureLifecycle.Sequence

  @type position :: Sequence.position()

  @doc "The flattened `(status_kind, status_gate)`/`(blocked_origin_kind, blocked_origin_gate)` column pair, unflattened — the identical shape `Catapult.Delivery.FeatureLifecycle.status/1` reads off its own struct, made available to the maps `Catapult.Delivery.Store.tickets_for_project/1` returns instead."
  @spec from_columns(String.t() | nil, String.t() | nil) :: position() | nil
  def from_columns(nil, nil), do: nil
  def from_columns(kind, nil), do: {:kind, String.to_existing_atom(kind)}
  def from_columns(_kind, gate), do: {:gate, gate}

  @doc "A stable string encoding for a position, safe to round-trip through a `phx-value-*`/query-string param and back through `decode_key/1`."
  @spec key(position()) :: String.t()
  def key({:kind, kind}), do: "kind:" <> Atom.to_string(kind)
  def key({:gate, name}), do: "gate:" <> name

  @doc "The inverse of `key/1`."
  @spec decode_key(String.t()) :: position()
  def decode_key("kind:" <> kind), do: {:kind, String.to_existing_atom(kind)}
  def decode_key("gate:" <> name), do: {:gate, name}

  @doc "A human-readable label — the citing type's own status name or a declared gate's own name, title-cased for a status."
  @spec label(position()) :: String.t()
  def label({:kind, kind}), do: kind |> Atom.to_string() |> Phoenix.Naming.humanize()
  def label({:gate, name}), do: name

  @doc "`:status` or `:gate`, the two lane/sequence-entry shapes `board` and `ticket` render distinctly."
  @spec kind(position()) :: :status | :gate
  def kind({:kind, _kind}), do: :status
  def kind({:gate, _name}), do: :gate

  @doc "The role a gate position routes to, or `nil` for a status position — read off the loaded workflow's own gate declaration."
  @spec role(position(), Catapult.Dsl.Workflow.t()) :: String.t() | nil
  def role({:gate, name}, %Catapult.Dsl.Workflow{gates: gates}) do
    case Map.fetch(gates, name) do
      {:ok, gate} -> gate.role
      :error -> nil
    end
  end

  def role({:kind, _kind}, %Catapult.Dsl.Workflow{}), do: nil
end
