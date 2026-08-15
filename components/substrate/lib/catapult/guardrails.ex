defmodule Catapult.Guardrails do
  @moduledoc """
  The VM guardrails a `processes/0` entry declares, applied by the process
  that declared them (v5 §2.5, systems/substrate.md's enforcement roster):

      @impl GenServer
      def init(arg) do
        Catapult.Guardrails.apply!(Engine.Component, :engine_sweeper)
        {:ok, build(arg)}
      end

  ## Why the process and not the composer

  A process flag can only be set from inside its own process —
  `Process.flag/3` covers `:save_calls` and nothing else — so the only
  external route is `spawn_opt` on the start call. That would require the
  composer to know the option conventions of start functions it did not
  write, and it has no answer at all for a child whose `start_link` takes
  no options. It is the same defect as a shipped task knowing this
  repository's layout, one level in: generic composition machinery
  holding specific knowledge about the things it composes
  (docs/non-goals.md).

  So the declaration stays in the registry, the application is one line
  in `init/1`, and *declared↔applied* is the check —
  `mix catapult.audit` reports a guardrail declared and never applied,
  which is the same shape as declared↔constructed and declared↔emitted.

  ## Two declarations, two grades

  `max_heap_size:` is a real BEAM process flag: the VM kills the process
  before it takes the node down, which is `runtime`-grade enforcement on
  the §4.5 ladder, and it is legal precisely because processes are never
  the state of record.

  `message_queue_alarm_len:` is **not applied here and is not
  enforcement**. There is no per-process message-queue flag in the VM —
  `:max_message_queue_len` raises `badarg` — and the only queue facility
  the VM offers, `:erlang.system_monitor/2`'s `long_message_queue`, is
  node-global, notify-only and singular: setting one discards the
  previous one, so any dependency reaching for `long_gc` would disable
  ours without a word. It is a declared threshold that observability
  samples and reports (`systems/observability.md`), and its name says so
  — `max_` is a promise the platform cannot keep. A full mailbox is
  reported, never killed: a process that is merely behind is usually the
  only thing holding the work.
  """

  @doc """
  Applies every enforceable guardrail `component` declares for `name`.

  Raises when `name` is not a process the component registered: a
  guardrail call naming a process nobody declared is the placement rule
  evaded from the other end, and it fails at the process's own `init/1`
  rather than silently doing nothing.
  """
  @spec apply!(module(), atom()) :: :ok
  def apply!(component, name) do
    component
    |> declared!(name)
    |> Enum.each(&apply_one/1)
  end

  @doc """
  The guardrail opts `component` declares for process `name`, or `[]`.

  The read half, for the audit and for a process that wants to report its
  own bounds; `nil` when the process is not declared at all, which is
  what lets `apply!/2` say so rather than guess.
  """
  @spec declared(module(), atom()) :: keyword() | nil
  def declared(component, name) do
    Enum.find_value(component.processes(), fn
      {^name, _placement, opts} when is_list(opts) -> opts
      {^name, _placement} -> []
      _other -> nil
    end)
  end

  @doc "The opts on a `processes/0` entry this module knows how to enforce."
  @spec enforceable() :: [atom()]
  def enforceable, do: [:max_heap_size]

  defp declared!(component, name) do
    case declared(component, name) do
      nil ->
        raise ArgumentError,
              "#{inspect(component)} declares no process #{inspect(name)} in processes/0 " <>
                "(register it before guarding it; conventions §5)"

      opts ->
        opts
    end
  end

  # `kill` and `error_logger` are set rather than inherited: the VM's
  # defaults are node settings, and a guardrail whose grade depends on how
  # the node was started is a guardrail nobody can read off the
  # declaration.
  defp apply_one({:max_heap_size, words}) when is_integer(words) and words > 0 do
    Process.flag(:max_heap_size, %{size: words, kill: true, error_logger: true})
    :ok
  end

  # Sampled by observability, never enforced here — see the moduledoc.
  defp apply_one({:message_queue_alarm_len, _length}), do: :ok

  defp apply_one({_opt, _value}), do: :ok
end
