defmodule Catapult.Dsl.EdgeLocator do
  @moduledoc """
  Decides how an edge instance's `source`/`target` endpoint that isn't
  the tier committing the draft `declared_in` names is located
  (dsl-syntax.md §4.2): `self`, `self.parent`, `fanout(<edge>)`, a
  `scope: singleton` endpoint, or an explicit path. Shared between
  `Catapult.Dsl.Chain` (load-time legality — does a locator exist at
  all) and `Catapult.Generation.Extraction` (runtime resolution — the
  actual node an instance's source/target names), so the two can never
  drift on what a given instance's locator means.

  **Source resolves before target, always** (`systems/core_dsl.md`'s
  ORC-236 entry): the one case this ordering matters is a same-tier
  self-referencing instance (`navigation`'s own `screen -> screen`) —
  letting both sides independently match the identical structural
  locator (the same `fanout(decomposition)` element) would make source
  and target the same node on every instance. Resolving source first
  and only then asking whether target needs the trailing-`.@attr`
  default instead of its own structural search is what keeps the two
  distinct.
  """

  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.Tier

  @typedoc "`:self` (the declaring tier), `:self_parent`, `{:fanout, edge_name}`, `:singleton`, or `{:path, raw}`."
  @type kind :: :self | :self_parent | {:fanout, String.t()} | :singleton | {:path, String.t()}

  @doc "Parses a raw `source_ref:`/`target_ref:` string into its closed-vocabulary kind."
  @spec parse(String.t()) :: kind()
  def parse("self"), do: :self
  def parse("self.parent"), do: :self_parent

  def parse(raw) do
    case Regex.run(~r/\Afanout\(([a-z0-9_]+)\)\z/, raw) do
      [_whole, edge] -> {:fanout, edge}
      nil -> {:path, raw}
    end
  end

  @typedoc "One instance's resolved pair, or the unresolved side name(s)."
  @type resolution :: {:ok, kind(), kind()} | {:error, [:source | :target]}

  @doc """
  Resolves both endpoints of one edge instance. `declaring_tier` is
  `declared_in`'s own leading segment (the tier whose draft carries the
  relationship); `trailing_attr` is `declared_in`'s trailing `.@attr`
  segment, if it has one. `explicit_source`/`explicit_target` are the
  instance's own parsed `source_ref:`/`target_ref:`, or `nil` when
  omitted.
  """
  @typedoc "The bundle's own tier/edge maps — `Catapult.Dsl.Chain.t()`'s two fields, bundled so this module's own arity stays under credo's cap."
  @type graph :: %{edges: %{String.t() => Edge.t()}, tiers: %{String.t() => Tier.t()}}

  @spec resolve(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          kind() | nil,
          kind() | nil,
          graph()
        ) :: resolution()
  def resolve(
        source_tier,
        target_tier,
        declaring_tier,
        declared_in,
        trailing_attr,
        explicit_source,
        explicit_target,
        %{edges: edges, tiers: tiers}
      ) do
    source =
      resolve_side(source_tier, declaring_tier, explicit_source, declared_in, edges, tiers)

    target =
      resolve_side(target_tier, declaring_tier, explicit_target, declared_in, edges, tiers)

    # A same-tier self-reference where both sides would otherwise match
    # the identical *fanout* anchor (`navigation`'s own `screen ->
    # screen`, both resolving to the same minting element): source
    # keeps it, target is forced back to :none so the trailing-attr
    # default (below) applies instead — never a second copy of the
    # same locator. `:self` is exempt: when both sides genuinely name
    # the declaring tier itself, that is an ordinary, bundle-authored
    # self-loop (`graph_constraint: acyclic`/`no_self_loop`'s own job
    # at projection time to allow or refuse), not an artifact of
    # locator matching.
    target =
      if source_tier == target_tier and match?({:fanout, _}, source) and explicit_target == nil and
           target == source do
        :none
      else
        target
      end

    apply_trailing_default(source, target, trailing_attr)
  end

  defp apply_trailing_default(:none, :none, _trailing_attr), do: {:error, [:source, :target]}

  defp apply_trailing_default(:none, target, trailing_attr) do
    case default_from_trailing(trailing_attr) do
      {:ok, locator} -> {:ok, locator, target}
      :error -> {:error, [:source]}
    end
  end

  defp apply_trailing_default(source, :none, trailing_attr) do
    case default_from_trailing(trailing_attr) do
      {:ok, locator} -> {:ok, source, locator}
      :error -> {:error, [:target]}
    end
  end

  defp apply_trailing_default(source, target, _trailing_attr), do: {:ok, source, target}

  defp default_from_trailing(nil), do: :error
  defp default_from_trailing(attr), do: {:ok, {:path, "@" <> attr}}

  # `:none` means "no locator applies yet" — resolved either by the
  # trailing-attr default above, or reported as unresolved.
  defp resolve_side(side_tier, declaring_tier, _explicit, _declared_in, _edges, _tiers)
       when side_tier == declaring_tier,
       do: :self

  defp resolve_side(_side_tier, _declaring_tier, :self, _declared_in, _edges, _tiers), do: :self

  defp resolve_side(side_tier, declaring_tier, :self_parent, _declared_in, _edges, tiers) do
    if self_parent_match?(declaring_tier, side_tier, tiers), do: :self_parent, else: :none
  end

  defp resolve_side(
         side_tier,
         _declaring_tier,
         {:fanout, edge_name} = explicit,
         declared_in,
         edges,
         _tiers
       ) do
    if fanout_prefix_instance(edges, edge_name, side_tier, declared_in), do: explicit, else: :none
  end

  defp resolve_side(
         _side_tier,
         _declaring_tier,
         {:path, _} = explicit,
         _declared_in,
         _edges,
         _tiers
       ),
       do: explicit

  defp resolve_side(side_tier, declaring_tier, nil, declared_in, edges, tiers) do
    cond do
      self_parent_match?(declaring_tier, side_tier, tiers) ->
        :self_parent

      singleton?(side_tier, tiers) ->
        :singleton

      edge_name = matching_fanout_edge(edges, side_tier, declared_in) ->
        {:fanout, edge_name}

      true ->
        :none
    end
  end

  defp self_parent_match?(declaring_tier, side_tier, tiers) do
    case Map.fetch(tiers, declaring_tier) do
      {:ok, %Tier{scope: {:per, ^side_tier}}} -> true
      {:ok, %Tier{scope: {:child_of, ^side_tier}}} -> true
      _other -> false
    end
  end

  defp singleton?(side_tier, tiers) do
    match?({:ok, %Tier{scope: {:singleton}}}, Map.fetch(tiers, side_tier))
  end

  # The (at most one, by construction — two fanout instances minting
  # the same tier from overlapping loci would be a bundle-content bug
  # of its own) `type: fanout` edge whose own instance both targets
  # `side_tier` and strictly prefixes `declared_in` — auto-detected the
  # identical way an explicit `fanout(<edge>)` locator is checked
  # (`fanout_prefix_instance/4` below).
  defp matching_fanout_edge(edges, side_tier, declared_in) do
    Enum.find_value(edges, fn {name, edge} ->
      if edge.type == "fanout" and fanout_prefix_instance(edges, name, side_tier, declared_in),
        do: name
    end)
  end

  @doc """
  Whether some `type: fanout` instance in `edges` names `edge_name`,
  targets `side_tier`, and its own `declared_in` is a strict
  path-prefix of `declared_in` — the actual anchor a `fanout(<edge>)`
  locator resolves against, both at load time (does one exist) and at
  runtime (which element is it).
  """
  @spec fanout_prefix_instance(%{String.t() => Edge.t()}, String.t(), String.t(), String.t()) ::
          Edge.instance() | nil
  def fanout_prefix_instance(edges, edge_name, side_tier, declared_in) do
    case Map.fetch(edges, edge_name) do
      {:ok, %Edge{type: "fanout", instances: instances}} ->
        Enum.find(instances, fn instance ->
          instance.target == side_tier and strict_prefix?(instance.declared_in, declared_in)
        end)

      _other ->
        nil
    end
  end

  defp strict_prefix?(prefix, whole) do
    prefix != whole and String.starts_with?(whole, prefix)
  end
end
