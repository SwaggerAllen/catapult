defmodule Catapult.Dsl.Fields do
  @moduledoc """
  Shared field accessors for the per-declaration parsers (tier, edge,
  flow, gate, environment, bundle.yaml): every accessor returns
  `{value, problems}` rather than raising or short-circuiting, so a
  parser can read every field it needs and report every problem at
  once (dsl-syntax.md §13's all-problems-at-once style, `Catapult
  .Config`'s idiom applied to YAML maps).

  YAML maps keep string keys throughout (`Catapult.Dsl.Yaml`):
  `String.to_atom/1` on bundle-supplied content is exactly the
  atom-table growth the closed-vocabulary discipline exists to avoid.
  """

  @typedoc "A field problem list, empty on success."
  @type problems :: [String.t()]

  @doc "A required string field."
  @spec require_string(map(), String.t(), String.t()) :: {String.t() | nil, problems()}
  def require_string(map, key, where) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {value, []}

      {:ok, value} ->
        {nil, ["#{where} #{inspect(key)} is #{inspect(value)}, expected a non-empty string"]}

      :error ->
        {nil, ["#{where} is missing required field #{inspect(key)}"]}
    end
  end

  @doc "An optional string field with a default."
  @spec optional_string(map(), String.t(), String.t(), String.t() | nil) ::
          {String.t() | nil, problems()}
  def optional_string(map, key, where, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) ->
        {value, []}

      {:ok, value} ->
        {default, ["#{where} #{inspect(key)} is #{inspect(value)}, expected a string"]}

      :error ->
        {default, []}
    end
  end

  @doc "A required field whose value must be one of `allowed`."
  @spec require_one_of(map(), String.t(), [String.t()], String.t()) ::
          {String.t() | nil, problems()}
  def require_one_of(map, key, allowed, where) do
    case require_string(map, key, where) do
      {nil, problems} ->
        {nil, problems}

      {value, []} ->
        if value in allowed do
          {value, []}
        else
          {nil,
           ["#{where} #{inspect(key)} is #{inspect(value)}, expected one of #{inspect(allowed)}"]}
        end
    end
  end

  @doc "An optional field whose value, if present, must be one of `allowed`."
  @spec optional_one_of(map(), String.t(), [String.t()], String.t(), String.t()) ::
          {String.t(), problems()}
  def optional_one_of(map, key, allowed, where, default) do
    case Map.fetch(map, key) do
      :error ->
        {default, []}

      {:ok, value} when is_binary(value) ->
        if value in allowed do
          {value, []}
        else
          {default,
           ["#{where} #{inspect(key)} is #{inspect(value)}, expected one of #{inspect(allowed)}"]}
        end

      {:ok, value} ->
        {default,
         ["#{where} #{inspect(key)} is #{inspect(value)}, expected one of #{inspect(allowed)}"]}
    end
  end

  @doc "A required boolean field."
  @spec optional_boolean(map(), String.t(), String.t(), boolean()) :: {boolean(), problems()}
  def optional_boolean(map, key, where, default) do
    case Map.fetch(map, key) do
      :error ->
        {default, []}

      {:ok, value} when is_boolean(value) ->
        {value, []}

      {:ok, value} ->
        {default, ["#{where} #{inspect(key)} is #{inspect(value)}, expected true or false"]}
    end
  end

  @doc "A required map field."
  @spec require_map(map(), String.t(), String.t()) :: {map() | nil, problems()}
  def require_map(map, key, where) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> {value, []}
      {:ok, value} -> {nil, ["#{where} #{inspect(key)} is #{inspect(value)}, expected a map"]}
      :error -> {nil, ["#{where} is missing required field #{inspect(key)}"]}
    end
  end

  @doc "An optional map field, defaulting to `nil` when absent."
  @spec optional_map(map(), String.t(), String.t()) :: {map() | nil, problems()}
  def optional_map(map, key, where) do
    case Map.fetch(map, key) do
      :error -> {nil, []}
      {:ok, value} when is_map(value) -> {value, []}
      {:ok, value} -> {nil, ["#{where} #{inspect(key)} is #{inspect(value)}, expected a map"]}
    end
  end

  @doc "A required list of strings."
  @spec require_string_list(map(), String.t(), String.t()) :: {[String.t()], problems()}
  def require_string_list(map, key, where) do
    case Map.fetch(map, key) do
      {:ok, value} when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          {value, []}
        else
          {[], ["#{where} #{inspect(key)} has a non-string entry (expected a list of strings)"]}
        end

      {:ok, value} ->
        {[], ["#{where} #{inspect(key)} is #{inspect(value)}, expected a list of strings"]}

      :error ->
        {[], ["#{where} is missing required field #{inspect(key)}"]}
    end
  end

  @doc "An optional list of strings, defaulting to `[]`."
  @spec optional_string_list(map(), String.t(), String.t()) :: {[String.t()], problems()}
  def optional_string_list(map, key, where) do
    case Map.fetch(map, key) do
      :error ->
        {[], []}

      {:ok, value} when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          {value, []}
        else
          {[], ["#{where} #{inspect(key)} has a non-string entry (expected a list of strings)"]}
        end

      {:ok, value} ->
        {[], ["#{where} #{inspect(key)} is #{inspect(value)}, expected a list of strings"]}
    end
  end

  @typedoc "A fan-out ceiling: one depth, or `{first, rest}` (dsl-syntax.md §7.19's pair)."
  @type depth :: non_neg_integer() | {non_neg_integer(), non_neg_integer()}

  @doc """
  A `depth:` field (dsl-syntax.md §13): a non-negative integer, or a
  2-element list of non-negative integers (`[first, rest]`, §7.19) —
  the same grammar checked the same way on a gate, an environment and
  `critique.yaml` (§15.2, §15.4, §15.5). Omitted defaults to `0`.
  """
  @spec depth(map(), String.t()) :: {depth(), problems()}
  def depth(map, where) do
    case Map.fetch(map, "depth") do
      :error ->
        {0, []}

      {:ok, value} when is_integer(value) and value >= 0 ->
        {value, []}

      {:ok, [first, rest]}
      when is_integer(first) and first >= 0 and is_integer(rest) and
             rest >= 0 ->
        {{first, rest}, []}

      {:ok, value} ->
        {0,
         [
           "#{where} depth is #{inspect(value)}, expected a non-negative integer or a list of exactly two non-negative integers"
         ]}
    end
  end

  @doc "Every key in `map` outside `known`, as an unknown-field problem list."
  @spec unknown_keys(map(), [String.t()], String.t()) :: problems()
  def unknown_keys(map, known, where) do
    for key <- Map.keys(map), key not in known do
      "#{where} carries unknown field #{inspect(key)} (known: #{inspect(known)})"
    end
  end
end
