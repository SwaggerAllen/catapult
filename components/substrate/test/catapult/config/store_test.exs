defmodule Catapult.Config.StoreTest do
  @moduledoc """
  The store, which is process-global by construction (`:persistent_term`,
  written once before the root supervisor starts). One test, because
  load-once is the contract: the whole lifecycle is a sequence, and
  splitting it into cases that shuffle would be testing a store the
  layer does not offer.
  """
  # Not async: the store is one per VM.
  use ExUnit.Case, async: false

  alias Catapult.Config
  alias Catapult.Config.Static

  defmodule Stored do
    use Catapult.Component, slug: :stored

    def config do
      [
        {:url, "STORED_URL", []},
        {:size, "STORED_SIZE", [cast: :integer, default: "10"]}
      ]
    end
  end

  test "the store is written once, at load, and read only through the accessor" do
    refute Config.loaded?()

    assert_raise Config.LoadError, ~r/has not been loaded/, fn ->
      Config.fetch!(:stored, :url)
    end

    err = assert_raise Config.LoadError, fn -> Config.load!([Stored], {Static, %{}}) end
    assert err.message =~ "configuration problems:"
    assert err.message =~ "STORED_URL is not set"
    # A boot that failed its report wrote nothing.
    refute Config.loaded?()

    seed = %{"STORED_URL" => "ecto://localhost/x", "STORED_SIZE" => "20"}
    assert :ok = Config.load!([Stored], {Static, seed})

    assert Config.loaded?()
    assert Config.fetch!(:stored, :url) == "ecto://localhost/x"
    assert Config.fetch!(:stored, :size) == 20

    assert_raise Config.LoadError, ~r/declares no config key :nope/, fn ->
      Config.fetch!(:stored, :nope)
    end

    # Idempotent: config is read once and does not change until the next
    # boot, which is what lets a release task or a mix task ask for the
    # load without knowing whether the boot already did it.
    assert :ok = Config.load!([Stored], {Static, %{"STORED_URL" => "ecto://elsewhere/y"}})
    assert Config.fetch!(:stored, :url) == "ecto://localhost/x"
  end
end
