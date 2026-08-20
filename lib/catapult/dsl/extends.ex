defmodule Catapult.Dsl.Extends do
  @moduledoc """
  Content layering (dsl-syntax.md §11): a bundle naming `extends:
  <layer>` loads the layer first, then overlays. Declarations union;
  same-path files replace; layering never crosses axes; cycles in
  `extends:` chains are load errors.

  A layer is another bundle directory under the same `bundles/` root,
  of the same `kind` — "one language, two documents" (v5 §7.18): there
  is no separate layer-bundle file format, only more bundles.

  What §11 protects beyond this — "the automation protocol's own
  files never override" — has no file-shaped counterpart in this
  loader's model: the agent and queue states it names are
  `Catapult.Dsl.SystemStatus`'s fixed constants, never bundle content,
  so there is no bundle file a layer could override to reach them.
  Narrowed at v5 §7.16/§7.18, gates and environments *are* overlayable
  content like any other declaration.
  """

  alias Catapult.Dsl.Manifest
  alias Catapult.Dsl.Yaml

  @typedoc "One resolved layer: its directory and parsed manifest, base-first."
  @type layer :: {dir :: String.t(), Manifest.t()}

  @doc """
  Resolves the full `extends:` chain for the bundle at `dir` (already
  parsed as `manifest`), walking `bundles_root` for each named layer.

  Returns layers **base-first**, ending with `{dir, manifest}` itself —
  the order `resolve_files/2` needs so a later (more specific) layer's
  file replaces an earlier one's at the same relative path.
  """
  @spec chain(String.t(), String.t(), Manifest.t()) :: {:ok, [layer()]} | {:error, [String.t()]}
  def chain(bundles_root, dir, manifest) do
    walk(bundles_root, [{dir, manifest}], [manifest.name])
  end

  # Each further-base layer is prepended as it is discovered, so the
  # accumulator is already base-first by construction: the loop starts
  # at the requested bundle and walks outward, and every layer found
  # along the way is more base than everything already in `acc`.
  defp walk(_bundles_root, [{_dir, %{extends: nil}} | _] = acc, _seen) do
    {:ok, acc}
  end

  defp walk(bundles_root, [{_dir, %{extends: extends, kind: kind, file: file}} | _] = acc, seen) do
    if extends in seen do
      {:error,
       [
         "#{file}'s extends: chain cycles back to #{inspect(extends)} " <>
           "(#{Enum.join(Enum.reverse([extends | seen]), " -> ")})"
       ]}
    else
      with {:ok, layer_dir, layer_manifest} <- load_layer(bundles_root, extends, kind, file) do
        walk(bundles_root, [{layer_dir, layer_manifest} | acc], [extends | seen])
      end
    end
  end

  defp load_layer(bundles_root, name, expected_kind, requiring_file) do
    dir = Path.join(bundles_root, name)
    manifest_path = Path.join(dir, "bundle.yaml")

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw) do
      if manifest.kind == expected_kind do
        {:ok, dir, manifest}
      else
        {:error,
         [
           "#{requiring_file} extends #{inspect(name)}, a #{manifest.kind} bundle, across axes " <>
             "(extends: never crosses axes — dsl-syntax.md §11)"
         ]}
      end
    else
      {:error, reason} when is_binary(reason) ->
        {:error,
         ["#{requiring_file} extends #{inspect(name)}, which could not be loaded: #{reason}"]}

      {:error, problems} when is_list(problems) ->
        {:error, problems}
    end
  end

  @doc """
  Resolves every file matching `glob_key`'s globs across `layers`, base
  layer first: same relative path replaces, distinct relative paths
  union. Returns absolute paths, sorted for a reproducible load order.
  """
  @spec resolve_files([layer()], atom()) :: [String.t()]
  def resolve_files(layers, glob_key) do
    layers
    |> Enum.reduce(%{}, fn {dir, manifest}, acc ->
      manifest
      |> Map.fetch!(glob_key)
      |> Enum.flat_map(&Yaml.glob(dir, &1))
      |> Enum.reduce(acc, fn abs_path, acc2 ->
        Map.put(acc2, Path.relative_to(abs_path, dir), abs_path)
      end)
    end)
    |> Map.values()
    |> Enum.sort()
  end

  @doc "The union of `fragments:` across every layer (declarations union, §11)."
  @spec fragment_vocabulary([layer()]) :: [String.t()]
  def fragment_vocabulary(layers) do
    layers |> Enum.flat_map(fn {_dir, manifest} -> manifest.fragments end) |> Enum.uniq()
  end

  @doc """
  Resolves and loads the `extends:` chain for the bundle `bundle_name`
  under `bundles_root` directly — the same load `Catapult.Dsl.Chain
  .load/3` does internally, exposed for callers that need the layer
  list itself rather than a built `Chain.t()` (schema/prompt file
  resolution: `Catapult.Dsl.Grammar`, `Catapult.Generation
  .ContextAssembly`).
  """
  @spec load_layers(String.t(), String.t()) :: {:ok, [layer()]} | {:error, term()}
  def load_layers(bundles_root, bundle_name) do
    dir = Path.join(bundles_root, bundle_name)
    manifest_path = Path.join(dir, "bundle.yaml")

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw) do
      chain(bundles_root, dir, manifest)
    end
  end

  @doc """
  A bundle-relative content path (a prompt, a schema — anything a
  tier names by path rather than by declaration), resolved
  specific-first across `layers`: the leaf bundle's own copy of a
  file wins, and a file the leaf never copies (the platform-wide
  review grammar, living only in its base layer) still resolves —
  "same-path files replace" (dsl-syntax.md §11) applied to referenced
  content the same way it already applies to tier/edge/flow files.
  """
  @spec resolve_content_path([layer()], String.t()) :: String.t() | nil
  def resolve_content_path(layers, relative_path) do
    layers
    |> Enum.reverse()
    |> Enum.find_value(fn {layer_dir, _manifest} ->
      candidate = Path.join(layer_dir, relative_path)
      if File.regular?(candidate), do: candidate
    end)
  end
end
