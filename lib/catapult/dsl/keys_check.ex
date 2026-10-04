defmodule Mix.Tasks.Catapult.Dsl.Keys do
  @moduledoc """
  The key-set gate (`systems/core_dsl.md` #ORC-253-1, `bundle.md`
  #ORC-253-3): compares the keys `docs/dsl/`'s declarations admit with
  the keys the loader's parsers accept, in both directions, and fails
  naming every path and the side that lacks it.

  The doc side is `pipeline schema --root . dsl:<doc>` for `bundle`,
  `chain` and `workflow`, read as JSON Schema: `properties` names a
  key, `additionalProperties` a `*` segment, `items` a `[]` segment,
  `$defs` a shape (`$entry`, compared once, not expanded where
  `$ref`'d), and the members inside `allOf`/`anyOf`/`oneOf`/`if`'s
  `then`/`else` gates count as declared. The loader side is
  `Catapult.Dsl.key_paths/1` — each parser's own key data, the list
  its `Fields.unknown_keys/3` closes maps against, never a scrape of
  its source.

  Keys only: a type or condition the doc and the loader disagree on is
  the loader's own load error on a bundle that exercises it. Paths
  ending in `*` or `[]` are structure (the element of a map or list),
  not keys, and are compared on neither side.

  With `pipeline` absent from `PATH` the task **fails, never skips**: a
  skipping gate goes silent on exactly the author branches that rewrite
  the grammar (the `mix catapult.audit.all` precedent).
  """

  use Mix.Task
  use Boundary, classify_to: Catapult

  @shortdoc "Fails when docs/dsl/'s declared keys and the loader's accepted keys differ"

  @docs [bundle: "bundle", chain: "chain", workflow: "workflow"]

  @impl Mix.Task
  def run(_args) do
    binary =
      System.find_executable("pipeline") ||
        Mix.raise(
          "mix catapult.dsl.keys needs the `pipeline` binary on PATH to compile docs/dsl/'s " <>
            "declarations (`pipeline schema`); this gate fails rather than skips"
        )

    problems =
      Enum.flat_map(@docs, fn {doc, name} ->
        declared = binary |> schema(name) |> declared_paths()
        compare(name, declared, Catapult.Dsl.key_paths(doc))
      end)

    report(problems)
  end

  @doc """
  The key paths a decoded JSON Schema declares, sorted: `tiers.*.review`,
  `edges.*.instances[].source`, `$entry.fills`. Structure paths (ending
  in `*` or `[]`) are dropped.
  """
  @spec declared_paths(map()) :: [String.t()]
  def declared_paths(%{} = schema) do
    shapes =
      for {name, shape} <- Map.get(schema, "$defs", %{}),
          path <- walk(shape, "$" <> name),
          do: path

    (walk(schema, "") ++ shapes) |> keys_only() |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  The problems comparing the doc's declared paths with the loader's:
  one line per path, naming which side lacks it.
  """
  @spec compare(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def compare(doc, declared, loader) do
    declared = keys_only(declared)
    loader = keys_only(loader)

    for(
      path <- Enum.sort(declared -- loader),
      do: "#{path}: declared in docs/dsl/#{doc}.md, not accepted by the loader"
    ) ++
      for(
        path <- Enum.sort(loader -- declared),
        do: "#{path}: accepted by the loader, not declared in docs/dsl/#{doc}.md"
      )
  end

  defp keys_only(paths),
    do: Enum.reject(paths, &(String.ends_with?(&1, "*") or String.ends_with?(&1, "[]")))

  defp walk(%{} = node, prefix) do
    properties =
      for {key, sub} <- Map.get(node, "properties", %{}),
          path <- [join(prefix, key) | walk(sub, join(prefix, key))],
          do: path

    open_map = node |> Map.get("additionalProperties") |> walk_child(join(prefix, "*"))
    items = node |> Map.get("items") |> walk_child(prefix <> "[]")

    gated =
      for keyword <- ~w(allOf anyOf oneOf), sub <- List.wrap(Map.get(node, keyword)), do: sub

    gated = gated ++ for keyword <- ~w(then else), sub <- [Map.get(node, keyword)], do: sub

    properties ++ open_map ++ items ++ Enum.flat_map(gated, &walk(&1, prefix))
  end

  defp walk(_other, _prefix), do: []

  defp walk_child(%{} = node, prefix), do: [prefix | walk(node, prefix)]
  defp walk_child(_other, _prefix), do: []

  defp join("", segment), do: segment
  defp join(prefix, segment), do: prefix <> "." <> segment

  # sobelow_skip ["CI.System"]
  #
  # `binary` is `System.find_executable("pipeline")` and `name` is one
  # of this module's own `@docs` constants, never bundle content or any
  # other external input.
  defp schema(binary, name) do
    case System.cmd(binary, ["schema", "--root", ".", "dsl:" <> name], stderr_to_stdout: true) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, %{} = schema} -> schema
          _ -> Mix.raise("`pipeline schema dsl:#{name}` printed no JSON object:\n#{out}")
        end

      {out, status} ->
        Mix.raise("`pipeline schema dsl:#{name}` exited #{status}:\n#{out}")
    end
  end

  defp report([]), do: Mix.shell().info("mix catapult.dsl.keys: docs/dsl/ and the loader agree")

  defp report(problems) do
    Mix.shell().error("mix catapult.dsl.keys: docs/dsl/ and the loader's key sets differ:")
    for problem <- problems, do: Mix.shell().error("  - #{problem}")
    Mix.raise("docs/dsl/'s declarations and the loader's accepted keys are unequal")
  end
end
