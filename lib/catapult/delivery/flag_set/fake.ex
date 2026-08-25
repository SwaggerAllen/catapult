defmodule Catapult.Delivery.FlagSet.Fake do
  @moduledoc """
  The in-memory `Catapult.Delivery.FlagSet` implementation (conventions
  §9: the fake ships with the port, not with the test file).

  Backed by the calling process's own dictionary rather than a named
  process, so the suite stays async: two tests flipping different sets
  cannot see each other's flags, and no test has to serialize on a
  shared table.
  """

  @behaviour Catapult.Delivery.FlagSet

  @key {__MODULE__, :enabled}

  @impl Catapult.Delivery.FlagSet
  def enable(flags) when is_list(flags) do
    Process.put(@key, Enum.uniq(enabled() ++ flags))
    :ok
  end

  @doc "Every flag enabled through this fake in the calling process, in first-enabled order."
  @spec enabled() :: [String.t()]
  def enabled, do: Process.get(@key, [])

  @doc "Forgets every flag — for a test that wants a clean slate mid-run."
  @spec reset() :: :ok
  def reset do
    Process.delete(@key)
    :ok
  end
end
