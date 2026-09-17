defmodule Catapult.Dsl.PredicatesFile do
  @moduledoc """
  `predicates.yaml` (`chain.md` #37): named predicates composing the
  expression language, referenced by name from any of the language's
  four slots (`scope_filter`, `cardinality.when`, an edge `constraint`,
  a flow `completion`).

  Not a glob-listed manifest key (`bundle.yaml`'s §2 example carries no
  `predicates:` list) — a fixed filename at the bundle's own directory
  root, present or absent (`bundle.md` #3).
  """

  alias Catapult.Dsl.Predicate
  alias Catapult.Dsl.Yaml

  @doc "`predicates.yaml`'s absolute path under `dir`, or `nil` if it does not exist."
  @spec resolve(String.t()) :: String.t() | nil
  def resolve(dir) do
    path = Path.join(dir, "predicates.yaml")
    if File.exists?(path), do: path
  end

  @doc "Parses `predicates.yaml` at `path` into `{name => predicate}`, or every problem at once."
  @spec parse(String.t()) :: {:ok, %{String.t() => Predicate.t()}} | {:error, [String.t()]}
  def parse(nil), do: {:ok, %{}}

  def parse(path) do
    case Yaml.read(path) do
      {:ok, raw} -> parse_entries(raw, path)
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp parse_entries(raw, path) do
    results = for {name, expr} <- raw, do: {name, parse_one(name, expr, path)}
    problems = for {_name, {:error, reason}} <- results, do: reason

    if problems == [] do
      {:ok, Map.new(results, fn {name, {:ok, predicate}} -> {name, predicate} end)}
    else
      {:error, problems}
    end
  end

  defp parse_one(_name, expr, _path) when is_binary(expr), do: Predicate.parse(expr)

  defp parse_one(name, expr, path) do
    {:error,
     "#{path}'s predicate #{inspect(name)} is #{inspect(expr)}, expected a string expression"}
  end
end
