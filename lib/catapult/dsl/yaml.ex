defmodule Catapult.Dsl.Yaml do
  @moduledoc """
  The loader's one YAML entry point (systems/core_dsl.md): every bundle
  file is read here, so callers reason about maps with string keys and
  never about `YamlElixir`'s own error shapes.

  Keys stay strings, deliberately: `String.to_atom/1` on bundle content
  this module does not control would grow the atom table on every
  malformed or hostile file (`Catapult.Dsl.Fields`).
  """

  @doc """
  Reads `path` as YAML, or reports why it could not be read as one.

  A file that parses to something other than a map (a bare list, a
  scalar, an empty document) is reported here rather than passed on —
  every declaration kind this loader reads is a mapping at the top
  level, so that is the one shape worth checking generically.
  """
  @spec read(String.t()) :: {:ok, map()} | {:error, String.t()}
  def read(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, %{} = map} ->
        {:ok, map}

      {:ok, other} ->
        {:error, "#{path} does not contain a YAML mapping (got #{inspect(other)})"}

      {:error, %YamlElixir.FileNotFoundError{}} ->
        {:error, "#{path} does not exist"}

      {:error, reason} ->
        {:error, "#{path} could not be parsed: #{Exception.message(reason)}"}
    end
  rescue
    exception -> {:error, "#{path} could not be parsed: #{Exception.message(exception)}"}
  end
end
