defmodule Catapult.Dsl.ContextWalk do
  @moduledoc """
  Parses one `context:` entry (dsl-syntax.md §7): `self`, `self.parent`,
  `.<edge_name>` following a declared edge, `-> <tier>.<projection>`
  typing the target, and the v5 additions `input.<role>` / `input.*` /
  `ticket.<source>`.

  Parsing only — whether a named edge, target tier, fragment kind or
  `ticket.*` source actually exists is a cross-reference the loader
  checks with the rest of the bundle in view (dsl-syntax.md §13); this
  module reports only what a single walk string cannot possibly mean.

  Free-form names (edge, tier, role, fragment kind, ticket source) stay
  strings rather than atoms: they come from bundle content, and
  `String.to_atom/1` on content this module does not control is exactly
  the atom-table growth the closed-vocabulary discipline exists to make
  unnecessary. Only the walk's own fixed shape — source kind, projection
  kind — is atoms.
  """

  @enforce_keys [:raw, :source]
  defstruct raw: nil,
            source: nil,
            parent: false,
            edge: nil,
            target_tier: nil,
            projection: nil,
            role: nil,
            wildcard: false,
            ticket_source: nil

  @typedoc "`:handle`, `:synthesis`, or `{:fragments, kind}`."
  @type projection :: :handle | :synthesis | {:fragments, String.t()}

  @type t :: %__MODULE__{
          raw: String.t(),
          source: :self | :input | :ticket,
          parent: boolean(),
          edge: String.t() | nil,
          target_tier: String.t() | nil,
          projection: projection() | nil,
          role: String.t() | nil,
          wildcard: boolean(),
          ticket_source: String.t() | nil
        }

  @doc "Parses one context-walk string, or reports why it does not parse."
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    case split_arrow(trimmed) do
      {:ok, left, right} -> parse_source(trimmed, left, right)
      {:error, reason} -> {:error, "context walk #{inspect(raw)} #{reason}"}
    end
  end

  defp split_arrow(entry) do
    case String.split(entry, "->") do
      [left] ->
        {:ok, String.trim(left), nil}

      [left, right] ->
        {:ok, String.trim(left), String.trim(right)}

      _many ->
        {:error, "has more than one -> (exactly zero or one is legal)"}
    end
  end

  defp parse_source(raw, left, right) do
    case String.split(left, ".") do
      ["self" | rest] ->
        parse_self(raw, rest, right)

      ["input" | rest] ->
        parse_input(raw, rest, right)

      ["ticket" | rest] ->
        parse_ticket(raw, rest, right)

      [other | _rest] ->
        {:error,
         "context walk #{inspect(raw)} starts with #{inspect(other)} (expected self, input or ticket)"}

      [] ->
        {:error, "context walk #{inspect(raw)} is empty"}
    end
  end

  defp parse_self(raw, rest, right) do
    {parent?, rest} =
      case rest do
        ["parent" | tail] -> {true, tail}
        _ -> {false, rest}
      end

    case {rest, right} do
      {[], nil} ->
        {:ok, %__MODULE__{raw: raw, source: :self, parent: parent?}}

      {[edge], right} when edge != "" and not is_nil(right) ->
        with {:ok, target_tier, projection} <- parse_target(raw, right) do
          {:ok,
           %__MODULE__{
             raw: raw,
             source: :self,
             parent: parent?,
             edge: edge,
             target_tier: target_tier,
             projection: projection
           }}
        end

      {segments, nil} ->
        with {:ok, projection} <- parse_projection(raw, segments) do
          {:ok, %__MODULE__{raw: raw, source: :self, parent: parent?, projection: projection}}
        end

      {[], right} when not is_nil(right) ->
        {:error, "context walk #{inspect(raw)} has -> with no edge name before it"}

      {_many, _right} ->
        {:error,
         "context walk #{inspect(raw)} names more than one edge before -> " <>
           "(only one hop is legal before a target type)"}
    end
  end

  defp parse_target(raw, right) do
    case String.split(right, ".") do
      [tier | segments] when tier != "" and segments != [] ->
        with {:ok, projection} <- parse_projection(raw, segments) do
          {:ok, tier, projection}
        end

      _other ->
        {:error,
         "context walk #{inspect(raw)}'s target #{inspect(right)} is not <tier>.<projection>"}
    end
  end

  defp parse_projection(_raw, ["handle"]), do: {:ok, :handle}
  defp parse_projection(_raw, ["synthesis"]), do: {:ok, :synthesis}

  defp parse_projection(raw, ["handle", fragments]) do
    case Regex.run(~r/\Afragments\[([a-z0-9_]+)\]\z/, fragments) do
      [_whole, kind] ->
        {:ok, {:fragments, kind}}

      nil ->
        {:error,
         "context walk #{inspect(raw)}'s projection #{inspect(fragments)} is not fragments[<kind>]"}
    end
  end

  defp parse_projection(raw, other) do
    {:error,
     "context walk #{inspect(raw)}'s projection #{inspect(Enum.join(other, "."))} is not " <>
       "handle, handle.fragments[<kind>], or synthesis"}
  end

  defp parse_input(raw, ["*"], nil),
    do: {:ok, %__MODULE__{raw: raw, source: :input, wildcard: true}}

  defp parse_input(raw, [role], nil) when role != "" do
    {:ok, %__MODULE__{raw: raw, source: :input, role: role}}
  end

  defp parse_input(raw, _rest, right) when not is_nil(right) do
    {:error, "context walk #{inspect(raw)}'s input.* form takes no -> target"}
  end

  defp parse_input(raw, _rest, _right) do
    {:error, "context walk #{inspect(raw)} is not input.<role> or input.*"}
  end

  defp parse_ticket(raw, [source], nil) when source != "" do
    {:ok, %__MODULE__{raw: raw, source: :ticket, ticket_source: source}}
  end

  defp parse_ticket(raw, _rest, right) when not is_nil(right) do
    {:error, "context walk #{inspect(raw)}'s ticket.* form takes no -> target"}
  end

  defp parse_ticket(raw, _rest, _right) do
    {:error, "context walk #{inspect(raw)} is not ticket.<source>"}
  end
end
