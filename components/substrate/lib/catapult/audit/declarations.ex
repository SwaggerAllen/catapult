defmodule Catapult.Audit.Declarations do
  @moduledoc """
  The checks that hold a registry against a tree, rather than a tree
  against a rule (systems/substrate.md's enforcement roster).

  A `Catapult.Audit.Check` sees a scope and nothing else, which is what
  keeps a registered check from reaching across mix projects. These two
  need the composed inventory as well, so they are the audit task's own
  rather than entries in `policies/0` — and they live here rather than
  inside the task because a check nobody can call is a check nobody
  tests.

  Both are the same shape, and it is the third and fourth instance of it:

    * **declared↔applied** — a `processes/0` entry declaring a VM
      guardrail with no `Catapult.Guardrails.apply!/2` applying it. The
      composer cannot thread `spawn_opt` (see `Catapult.Guardrails`), so
      the declaration and the application are two facts and this is where
      they meet.
    * **declared↔constructed** — an `errors/0` kind nothing builds. The
      other direction is the generated constructor's (`Catapult.Error`);
      this is the half no constructor can see, and dead vocabulary in a
      catalog operators read is worth a line.

  Neither honours `catapult:allow`, deliberately: the escape excuses a
  *line* the parser found, and what these report is the absence of one.
  A declaration nobody uses is deleted, not excused.
  """

  alias Catapult.Audit.Source

  @doc """
  Guardrail declarations with no application under `scope`.

  `entries` are `processes/0` inventory entries; `enforceable` is the
  opts `Catapult.Guardrails` actually applies, so a threshold that is
  only sampled never asks for a call that would do nothing.
  """
  @spec guardrails([map()], [atom()], String.t()) :: [String.t()]
  def guardrails(entries, enforceable, scope) do
    entries
    |> Enum.filter(fn entry ->
      Enum.any?(entry.opts, fn {opt, _value} -> opt in enforceable end)
    end)
    |> unmatched(& &1.name, &guarded/1, scope, fn entry ->
      "#{inspect(entry.component)} declares VM guardrails for process #{inspect(entry.name)} " <>
        "and no Catapult.Guardrails.apply!/2 call applies them (conventions §5, v5 §2.5)"
    end)
  end

  @doc "Error kinds declared and never constructed under `scope`."
  @spec error_kinds([map()], String.t()) :: [String.t()]
  def error_kinds(entries, scope) do
    unmatched(entries, & &1.kind, &constructed/1, scope, fn entry ->
      "#{inspect(entry.component)} declares error kind #{inspect(entry.kind)} and nothing " <>
        "constructs it (dead vocabulary in the catalog; conventions §8)"
    end)
  end

  # The sweep runs only when something is declared, so the common case —
  # an empty registry, which is most of the roster today — parses nothing
  # at all.
  defp unmatched([], _key, _finder, _scope, _message), do: []

  defp unmatched(entries, key, finder, scope, message) do
    found =
      for path <- Path.wildcard(scope),
          {:ok, source} <- [Source.read(path)],
          name <- Source.collect(source.ast, finder),
          into: MapSet.new(),
          do: name

    for entry <- entries, not MapSet.member?(found, key.(entry)), do: message.(entry)
  end

  defp guarded({{:., _dot, [module, :apply!]}, _meta, [_component, name]}) when is_atom(name) do
    if Source.alias?(module, :Guardrails), do: [name], else: []
  end

  defp guarded(_node), do: []

  # Both spellings of a construction: the generated `new/2`, and the
  # struct literal conventions §8 shows at a boundary.
  defp constructed({{:., _dot, [_module, :new]}, _meta, [kind | _rest]}) when is_atom(kind) do
    [kind]
  end

  defp constructed({:%, _meta, [_module, {:%{}, _map, fields}]}) when is_list(fields) do
    case Keyword.get(fields, :kind) do
      kind when is_atom(kind) and not is_nil(kind) -> [kind]
      _other -> []
    end
  end

  defp constructed(_node), do: []
end
