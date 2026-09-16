defmodule Catapult.Dsl.Registry do
  @moduledoc """
  Aggregates a dialect's `Catapult.Dsl.Extension` modules into one
  registry (`bundle.md` #8): the union of every namespace,
  declaration kind, generator type, context source and enforcement
  profile they register, collision-checked the way
  `Catapult.Component.Composer` checks the component roster — a
  warning about a name collision is a collision that ships.

  "An annotation against an uninstalled extension is a load error
  naming the missing extension" (§12) is answered by `namespace/2`
  returning `:error` for anything this registry does not carry; the
  caller (`Catapult.Dsl.Bundle`) is what turns that into the message.
  """

  @enforce_keys [
    :namespaces,
    :declaration_kinds,
    :generator_types,
    :context_sources,
    :enforcement_profiles
  ]
  defstruct [
    :namespaces,
    :declaration_kinds,
    :generator_types,
    :context_sources,
    :enforcement_profiles
  ]

  @type t :: %__MODULE__{
          namespaces: %{String.t() => (term() -> [String.t()])},
          declaration_kinds: MapSet.t(String.t()),
          generator_types: MapSet.t(String.t()),
          context_sources: MapSet.t(String.t()),
          enforcement_profiles: MapSet.t(String.t())
        }

  @doc "Builds the registry for `extensions`, or every collision at once."
  @spec build([module()]) :: {:ok, t()} | {:error, [String.t()]}
  def build(extensions) do
    {namespaces, ns_problems} = collect_namespaces(extensions)
    {kinds, kind_problems} = collect_set(extensions, :declaration_kinds)
    {generators, gen_problems} = collect_set(extensions, :generator_types)
    {sources, source_problems} = collect_set(extensions, :context_sources)
    {profiles, profile_problems} = collect_set(extensions, :enforcement_profiles)

    problems = ns_problems ++ kind_problems ++ gen_problems ++ source_problems ++ profile_problems

    if problems == [] do
      {:ok,
       %__MODULE__{
         namespaces: Map.new(namespaces),
         declaration_kinds: MapSet.new(kinds),
         generator_types: MapSet.new(generators),
         context_sources: MapSet.new(sources),
         enforcement_profiles: MapSet.new(profiles)
       }}
    else
      {:error, problems}
    end
  end

  @doc "Whether `name` names a registered enforcement profile."
  @spec enforcement_profile?(t(), String.t()) :: boolean()
  def enforcement_profile?(%__MODULE__{} = registry, name),
    do: MapSet.member?(registry.enforcement_profiles, name)

  @doc "Whether `name` names a registered context source."
  @spec context_source?(t(), String.t()) :: boolean()
  def context_source?(%__MODULE__{} = registry, name),
    do: MapSet.member?(registry.context_sources, name)

  @doc "The registered validator for annotation namespace `name`, or `:error` if uninstalled."
  @spec namespace(t(), String.t()) :: {:ok, (term() -> [String.t()])} | :error
  def namespace(%__MODULE__{} = registry, name), do: Map.fetch(registry.namespaces, name)

  defp collect_set(extensions, callback) do
    entries = for ext <- extensions, entry <- apply(ext, callback, []), do: {entry, ext}
    duplicates(entries, "#{callback}")
  end

  defp collect_namespaces(extensions) do
    entries =
      for ext <- extensions, {name, validator} <- ext.namespaces(), do: {name, validator, ext}

    dup_problems = duplicate_names(entries, "namespaces")
    {for({name, validator, _ext} <- entries, do: {name, validator}), dup_problems}
  end

  defp duplicates(entries, label) do
    grouped = Enum.group_by(entries, &elem(&1, 0), &elem(&1, 1))

    problems =
      for {name, owners} <- grouped, length(owners) > 1 do
        "#{label} #{inspect(name)} is registered by more than one extension: #{inspect(owners)}"
      end

    {for({name, _owner} <- entries, do: name) |> Enum.uniq(), problems}
  end

  defp duplicate_names(entries, label) do
    grouped = Enum.group_by(entries, &elem(&1, 0), &elem(&1, 2))

    for {name, owners} <- grouped, length(owners) > 1 do
      "#{label} #{inspect(name)} is registered by more than one extension: #{inspect(owners)}"
    end
  end
end
