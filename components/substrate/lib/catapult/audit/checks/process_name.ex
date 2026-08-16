defmodule Catapult.Audit.Checks.ProcessName do
  @moduledoc """
  The placement ban at AST grade (conventions §5, v5 §2.5): a process
  started under `name: __MODULE__` rather than a name registered through
  `processes/0`.

  The registry is what makes placement — `:local`, `:singleton`,
  `:sharded` — a designed and reviewed fact instead of an improvised one,
  and a bare `name:` option is how a single-node stateful GenServer gets
  past it. At AST grade the option is a keyword pair the parser found, so
  the same two words inside a docstring or a heredoc are not a finding.

  Escape: `# catapult:allow name_module`, on the offending line or the
  comment line directly above it (`Catapult.Audit.Source`).
  """

  @behaviour Catapult.Audit.Check

  alias Catapult.Audit.Source

  @tag "name_module"
  @message "process registered under its own module name " <>
             "(register via processes/0; conventions §5)"

  @doc "The bare name a `catapult:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Catapult.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  # Keyword pairs survive into the quoted form as plain two-tuples, which
  # `Macro.prewalk/3` descends into — so the option is matched where it
  # is written rather than wherever the enclosing call happens to start.
  defp violations(source) do
    Source.collect(source.ast, fn
      {:name, {:__MODULE__, meta, context}} when is_atom(context) ->
        [{Keyword.get(meta, :line, 0), @message}]

      _node ->
        []
    end)
  end
end
