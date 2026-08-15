defmodule Catapult.Audit.Checks.SecretInLog do
  @moduledoc """
  The one static residue of the secret rule (v5 §2.2, conventions §10):
  an explicit `Catapult.Config.Secret.unwrap/1` inside a `Logger` call.

  Almost none of "a secret-flagged value never appears in a log or an
  error payload" is checkable statically, and almost none of it needs to
  be: `Catapult.Config.fetch!/2` returns a wrapper whose `Inspect` and
  `String.Chars` implementations redact, so interpolation, `inspect/1`, a
  crash dump and a `Logger` call are safe by construction (see that
  module). An audit that chased values through variables instead would be
  a shallow check one hop from the accessor pretending to be a guarantee.

  What is left is exactly one hop and no inference: code that has already
  said `unwrap` and then hands the result to the operational channel. It
  is a small check because the type did the work; a big one here would be
  evidence the type had not.

  Escape: `# catapult:allow secret_in_log`, on the offending line or the
  comment line directly above it (`Catapult.Audit.Source`).
  """

  @behaviour Catapult.Audit.Check

  alias Catapult.Audit.Source

  @tag "secret_in_log"
  @levels [
    :alert,
    :critical,
    :debug,
    :emergency,
    :error,
    :info,
    :log,
    :notice,
    :warning
  ]

  @doc "The bare name a `catapult:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Catapult.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  defp violations(source) do
    Source.collect(source.ast, fn
      {{:., _dot, [module, level]}, _meta, args} = node when level in @levels and is_list(args) ->
        logged(module, args, node)

      _node ->
        []
    end)
  end

  defp logged(module, args, node) do
    if Source.alias?(module, :Logger) and Enum.any?(args, &unwraps?/1) do
      [
        {Source.line(node),
         "unwrapped secret in a Logger call (log the declaration's key, never its value; v5 §2.2)"}
      ]
    else
      []
    end
  end

  # `Catapult.Config.Secret.unwrap/1` however it is aliased: the module's
  # last segment plus the function name, which is the whole of "one hop".
  defp unwraps?(argument) do
    argument
    |> Source.collect(fn
      {{:., _dot, [module, :unwrap]}, _meta, args} when is_list(args) ->
        [Source.alias?(module, :Secret)]

      _node ->
        []
    end)
    |> Enum.any?()
  end
end
