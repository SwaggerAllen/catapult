defmodule Catapult.DataCase do
  @moduledoc """
  Sandbox-checked-out DB tests, async by default (conventions §9).
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Catapult.Repo
      import Catapult.DataCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Catapult.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
