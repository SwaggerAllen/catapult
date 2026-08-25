defmodule CatapultWeb.ConnCase do
  @moduledoc """
  The harness `CatapultWeb`'s own tests need: a sandboxed `Repo`
  connection (`Catapult.DataCase`'s own pattern) plus
  `Phoenix.ConnTest`/`Phoenix.LiveViewTest` wired to `CatapultWeb.Endpoint`.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn

      @endpoint CatapultWeb.Endpoint
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Catapult.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
