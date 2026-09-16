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

  **`key/2` carries an optional namespace-qualifying anchor beside the
  position it encodes** (dsl-syntax.md §15.12, ORC-155): a bare
  `position()` stopped being a sufficient identity the moment a bundle
  could recur one kind across more than one sub-array — three
  `pending`, three `checks`, two `reconcile` in one type's array is
  legal now, and a bare `"kind:pending"` key cannot tell any of them
  apart. `<anchor>.<name>` (§15.12) is the qualified form; `anchor` is
  `nil` for a position this ticket's own effective sequence never
  repeats, which keeps every existing `key/1` call site — and the
  encoding it has always produced — unchanged. **`docs/ui-spec.md` §2
  rule 2 is why this lands here rather than in the screen that will
  actually need it**: `ORC-116` renders subflows as a visual grouping
  and consumes this encoding rather than deriving one of its own, so
  the vocabulary has to exist here first. **Computing a real anchor for
  a *resting* ticket — as opposed to accepting one a caller already
  has — is `resting_key/2`, below** (ORC-116): `Catapult.Delivery
  .FeatureLifecycle.Projection`'s own `passed`/`pinned_to`/
  `blocked_from` still key on the bare `position()` tuple throughout,
  with no namespace attached, so `resting_key/2` resolves the anchor by
  finding that bare position inside the citing type's own
  `annotated_positions` instead — first match, best-effort where the
  bare kind recurs, since disambiguating *which* occurrence a resting
  ticket is actually at needs runtime position-tracking the projection
  does not carry. That remaining gap is `Sequence.name/3`'s own caveat,
  not this module's.
  """

  alias Catapult.Delivery.FeatureLifecycle.Sequence

  @type position :: Sequence.position()

  @doc "The flattened `(status_kind, status_gate)`/`(blocked_origin_kind, blocked_origin_gate)` column pair, unflattened — the identical shape `Catapult.Delivery.FeatureLifecycle.status/1` reads off its own struct, made available to the maps `Catapult.Delivery.Store.tickets_for_project/1` returns instead."
  @spec from_columns(String.t() | nil, String.t() | nil) :: position() | nil
  def from_columns(nil, nil), do: nil
  def from_columns(kind, nil), do: {:kind, String.to_existing_atom(kind)}
  def from_columns(_kind, gate), do: {:gate, gate}

  @doc """
  A stable string encoding for a position, safe to round-trip through a
  `phx-value-*`/query-string param and back through `decode_key/1`.
  `anchor` (§15.12) qualifies it `<anchor>.<name>` when given — omitted
  or `nil`, the encoding is exactly what it has always been.
  """
  @spec key(position(), String.t() | nil) :: String.t()
  def key(position, anchor \\ nil)
  def key({:kind, kind}, nil), do: "kind:" <> Atom.to_string(kind)
  def key({:kind, kind}, anchor), do: "kind:" <> anchor <> "." <> Atom.to_string(kind)
  def key({:gate, name}, nil), do: "gate:" <> name
  def key({:gate, name}, anchor), do: "gate:" <> anchor <> "." <> name

  @doc """
  The inverse of `key/1` — the bare position, an anchor `key/2` carried
  dropped rather than returned, so every existing caller (a decline or
  resume target, always a bare position) keeps working unchanged.
  `decode_anchor/1` is the qualifying anchor's own half of the pair.
  """
  @spec decode_key(String.t()) :: position()
  def decode_key(encoded), do: encoded |> split_key() |> elem(0)

  @doc "The qualifying anchor `key/2` encoded, or `nil` when `encoded` carries none."
  @spec decode_anchor(String.t()) :: String.t() | nil
  def decode_anchor(encoded), do: encoded |> split_key() |> elem(1)

  defp split_key("kind:" <> rest), do: split_rest(rest, &{:kind, String.to_existing_atom(&1)})
  defp split_key("gate:" <> rest), do: split_rest(rest, &{:gate, &1})

  defp split_rest(rest, to_position) do
    case String.split(rest, ".", parts: 2) do
      [anchor, name] -> {to_position.(name), anchor}
      [name] -> {to_position.(name), nil}
    end
  end

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

  @doc """
  The round-trippable `key/2` for one entry of `Sequence
  .annotated_positions/2`'s own list (ORC-116) — qualified
  `<anchor>.<name>` when this entry's own bare position recurs
  elsewhere in `positions` (its own `group_key`, the recurring
  sub-array's anchor), bare otherwise. The ordinary case — no `types/
  *.yaml` this system ships recurs a kind across two sub-arrays today
  (`workflow.md` #7's own namespace rule) — is unaffected: every
  position keeps the identical bare encoding `key/1` has always
  produced.
  """
  @spec lane_key([Sequence.annotated_position()], Sequence.annotated_position()) :: String.t()
  def lane_key(positions, %{position: position, group_key: group_key}) do
    if ambiguous?(positions, position) do
      key(position, group_key)
    else
      key(position)
    end
  end

  defp ambiguous?(positions, position) do
    Enum.count(positions, &(&1.position == position)) > 1
  end

  @doc """
  The lane/rail key a *resting* ticket's own bare `position()` maps to
  — the identical qualification `lane_key/2` gives the declared lane,
  resolved by finding that position inside the citing type's own
  `annotated_positions` (`systems/dashboard.md`'s own "what this
  system still has to compute" entry, ORC-116). First match,
  best-effort where the bare kind recurs: disambiguating *which*
  occurrence a resting ticket is actually at needs runtime
  position-tracking this system does not carry (`Sequence.name/3`'s
  own identical caveat). `nil` for `nil` (no resting position at all)
  or a position this type's own sequence does not contain.
  """
  @spec resting_key([Sequence.annotated_position()], position() | nil) :: String.t() | nil
  def resting_key(_positions, nil), do: nil

  def resting_key(positions, position) do
    case Enum.find(positions, &(&1.position == position)) do
      nil -> nil
      entry -> lane_key(positions, entry)
    end
  end
end
