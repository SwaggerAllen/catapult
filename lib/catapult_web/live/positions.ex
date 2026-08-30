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
  the vocabulary has to exist here first. Computing a real anchor for
  a *resting* ticket — as opposed to accepting one a caller already
  has — is not built by this pass: `Catapult.Delivery.FeatureLifecycle
  .Projection`'s own `passed`/`pinned_to`/`blocked_from` are keyed on
  the bare `position()` tuple throughout, so two occurrences of the
  identical kind in one effective sequence are already indistinguishable
  upstream of this module, a gap ORC-116 (or whichever pass gives
  runtime position-tracking the identical namespace awareness) closes
  before this encoding's `anchor` argument has real per-ticket data to
  carry on the read path.
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
end
