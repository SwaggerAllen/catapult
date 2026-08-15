defmodule Catapult.RepoTest do
  use Catapult.DataCase, async: true

  alias Ecto.Adapters.SQL

  test "connection settings are assembled from the config layer" do
    config = Repo.config()

    # The declared cast's output, merged in by init/2 and then expanded
    # by Ecto's own URL parsing — which is why there is no `:url` key
    # left to assert on, and why config/*.exs must not also set the
    # discrete keys: the URL wins. One reader of DATABASE_URL in the
    # tree (systems/foundation.md).
    assert config[:database] == "catapult_test"
    assert config[:pool_size] == 10
    # And the harness switch config/test.exs keeps for itself survives.
    assert config[:pool] == Ecto.Adapters.SQL.Sandbox
  end

  test "the database round-trips" do
    assert {:ok, %{rows: [[1]]}} = SQL.query(Repo, "SELECT 1", [])
  end

  test "oban's infra migration is applied" do
    assert {:ok, %{rows: [[true]]}} =
             SQL.query(
               Repo,
               "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'oban_jobs')",
               []
             )
  end
end
