defmodule Catapult.Dsl.BundlePath do
  @moduledoc """
  Resolves a bundle-relative content path (a prompt, a schema —
  anything a tier names by path rather than by declaration) against
  the one directory a bundle now is (dsl-syntax.md §11: no `extends:`
  layering on either axis).

  **A path that escapes its bundle directory resolves to `nil`**, so a
  caller sees "not found" rather than a file outside the bundle. The
  value being resolved is bundle-authored — a tier's `prompt:` or
  `grammar:` — and a bundle is the customer's own content at the
  hosted tier, so without this guard the plane reads whatever such a
  path names. The guard is unrelated to layering and survives its
  retirement intact: confirmed rather than theorised, before it
  existed `resolve("bundles/default", "../../../../../etc/passwd")`
  returned that path and `Catapult.Generation.ContextAssembly
  .parse_template/1` read it.
  """

  @doc "The absolute path to `relative_path` inside `dir`, or `nil` if it does not exist or escapes `dir`."
  @spec resolve(String.t(), String.t()) :: String.t() | nil
  def resolve(dir, relative_path) do
    candidate = Path.join(dir, relative_path)
    if within?(dir, candidate) and File.regular?(candidate), do: candidate
  end

  # `Path.expand/1` rather than string comparison on the raw join: the
  # traversal only shows up once `..` segments are collapsed. The
  # trailing separator on the root is what keeps `bundles/default-flow`
  # from reading as inside `bundles/default`.
  defp within?(dir, candidate) do
    root = Path.expand(dir)
    String.starts_with?(Path.expand(candidate), root <> "/")
  end
end
