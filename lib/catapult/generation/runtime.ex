defmodule Catapult.Generation.Runtime do
  @moduledoc """
  The kind → runtime map v5 §7.10 describes for ticket-delivery agent
  kinds, generalized to Catapult's own chain (`systems/generation.md`'s
  ORC-215 entry): `:generation` is the one kind this chain dispatches
  today, and this module is what a runtime bound to that kind is
  allowed to be — a runtime name and the model-credential names it
  accepts.

  Claude Code is the only entry. Supporting a second agent
  implementation is a new entry in `@runtimes` below, never a rewrite
  of `cast/1` or `Catapult.Generation.cast_credential_order/1` — both
  read the map rather than naming Claude Code's two credentials
  themselves, which is what makes "a new bindings entry and zero
  protocol or bundle change" (v5 §7.10) literal here too.
  """

  @runtimes %{
    claude_code: ~w(claude_code_oauth_token anthropic_api_key)
  }

  @doc "Casts the configured runtime name to its atom key in `@runtimes`."
  @spec cast(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def cast("claude_code"), do: {:ok, :claude_code}

  def cast(other),
    do: {:error, "is #{inspect(other)}, expected one of #{inspect(runtime_names())}"}

  @doc "The model-credential names `runtime` accepts, in no particular order."
  @spec credential_names(atom()) :: [String.t()]
  def credential_names(runtime), do: Map.fetch!(@runtimes, runtime)

  @doc "Whether `name` is a model-credential name any known runtime accepts."
  @spec known_credential_name?(String.t()) :: boolean()
  def known_credential_name?(name), do: name in Enum.flat_map(@runtimes, fn {_k, v} -> v end)

  @doc "Every model-credential name any known runtime accepts — for an error message, never a validation set of its own."
  @spec known_credential_names() :: [String.t()]
  def known_credential_names, do: Enum.flat_map(@runtimes, fn {_k, v} -> v end)

  defp runtime_names, do: Map.keys(@runtimes) |> Enum.map(&Atom.to_string/1)
end
