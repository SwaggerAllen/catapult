defmodule Catapult.RepoTest do
  use Catapult.DataCase, async: true

  alias Ecto.Adapters.SQL

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
