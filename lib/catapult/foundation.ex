defmodule Catapult.Foundation do
  @moduledoc """
  Catapult's application root component (systems/foundation.md): the
  Repo, Oban, and infrastructure persistence. Oban's queues are claimed
  by the components that own them via `oban_queues/0`; the foundation
  only hosts the runtime.
  """
  use Catapult.Component, slug: :foundation

  alias Ecto.Adapters.SQL

  @impl Catapult.Component
  def children do
    if Application.get_env(:catapult, :start_persistence, true) do
      [Catapult.Repo, {Oban, Application.fetch_env!(:catapult, Oban)}]
    else
      []
    end
  end

  @impl Catapult.Component
  def ready? do
    if Application.get_env(:catapult, :start_persistence, true) do
      match?({:ok, _}, SQL.query(Catapult.Repo, "SELECT 1", []))
    else
      true
    end
  rescue
    _ -> false
  end
end
