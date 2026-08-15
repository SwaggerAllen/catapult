defmodule Catapult.ConfigTest do
  @moduledoc """
  The layer's report, exercised through `resolve/2` — the pure half.
  The store is a side effect and has its own (non-async) test; the
  report is the product, and it is what every one of these asserts.
  """
  use ExUnit.Case, async: true

  alias Catapult.Config
  alias Catapult.Config.Static

  defmodule Demo do
    use Catapult.Component, slug: :demo

    def config do
      [
        {:url, "DEMO_URL", []},
        {:pool_size, "DEMO_POOL_SIZE", [cast: :integer, default: "10"]},
        {:verbose, "DEMO_VERBOSE", [cast: :boolean, default: "false"]},
        {:note, "DEMO_NOTE", [required: false]}
      ]
    end
  end

  defmodule Other do
    use Catapult.Component, slug: :other
    def config, do: [{:url, "OTHER_URL", []}]
  end

  defmodule Casting do
    use Catapult.Component, slug: :casting

    def config do
      [
        {:doubled, "CASTING_DOUBLED", cast: &__MODULE__.double/1},
        {:buggy, "CASTING_BUGGY", cast: fn raw -> {:ok, String.to_integer(raw)} end}
      ]
    end

    def double(raw), do: {:ok, raw <> raw}
  end

  defmodule Refusing do
    use Catapult.Component, slug: :refusing
    def config, do: [{:never, "REFUSING_NEVER", cast: fn _raw -> {:error, "not acceptable"} end}]
  end

  defmodule UnreadableSource do
    @behaviour Catapult.Config.Source
    @impl Catapult.Config.Source
    def load(_names, _opts), do: {:error, ["/etc/app.toml: no such file"]}
  end

  defmodule NonsenseSource do
    @behaviour Catapult.Config.Source
    @impl Catapult.Config.Source
    def load(_names, _opts), do: :nonsense
  end

  defp static(seed), do: {Static, seed}

  describe "resolve/2" do
    test "casts every declared value and keys it by slug" do
      seed = %{"DEMO_URL" => "ecto://localhost/x", "DEMO_POOL_SIZE" => "20"}

      assert {:ok, values} = Config.resolve([Demo], static(seed))

      assert values == %{
               {:demo, :url} => "ecto://localhost/x",
               {:demo, :pool_size} => 20,
               {:demo, :verbose} => false,
               {:demo, :note} => nil
             }
    end

    test "defaults go through the declared cast" do
      seed = %{"DEMO_URL" => "ecto://localhost/x"}

      assert {:ok, %{{:demo, :pool_size} => 10, {:demo, :verbose} => false}} =
               Config.resolve([Demo], static(seed))
    end

    test "every missing value is reported, in one pass" do
      assert {:error, problems} = Config.resolve([Demo, Other], static(%{}))

      assert problems == [
               "DEMO_URL is not set (:demo.url)",
               "OTHER_URL is not set (:other.url)"
             ]
    end

    test "missing and uncastable values are collected together" do
      seed = %{"DEMO_POOL_SIZE" => "twenty", "DEMO_VERBOSE" => "yes"}

      assert {:error, problems} = Config.resolve([Demo], static(seed))

      assert problems == [
               "DEMO_URL is not set (:demo.url)",
               "DEMO_POOL_SIZE is not an integer (:demo.pool_size)",
               "DEMO_VERBOSE is not \"true\" or \"false\" (:demo.verbose)"
             ]
    end

    test "the report names the variable and the reason, never the value" do
      seed = %{"DEMO_URL" => "ecto://localhost/x", "DEMO_POOL_SIZE" => "hunter2"}

      assert {:error, [problem]} = Config.resolve([Demo], static(seed))
      assert problem =~ "DEMO_POOL_SIZE"
      refute problem =~ "hunter2"
    end

    test "present-but-empty is present" do
      seed = %{"DEMO_URL" => "", "DEMO_POOL_SIZE" => ""}

      assert {:error, problems} = Config.resolve([Demo], static(seed))
      # No "is not set" line for the empty URL: it is a value the source
      # found. Whether empty is legal is the cast's business, and
      # :string accepts it where :integer does not.
      assert problems == ["DEMO_POOL_SIZE is not an integer (:demo.pool_size)"]
    end

    test "an absent required: false value resolves to nil, uncast" do
      seed = %{"DEMO_URL" => "ecto://localhost/x"}
      assert {:ok, %{{:demo, :note} => nil}} = Config.resolve([Demo], static(seed))
    end

    test "custom casts derive the value" do
      seed = %{"CASTING_DOUBLED" => "ab", "CASTING_BUGGY" => "1"}

      assert {:ok, %{{:casting, :doubled} => "abab", {:casting, :buggy} => 1}} =
               Config.resolve([Casting], static(seed))
    end

    test "a custom cast refuses by reason" do
      assert {:error, [problem]} = Config.resolve([Refusing], static(%{"REFUSING_NEVER" => "x"}))
      assert problem == "REFUSING_NEVER is invalid: not acceptable (:refusing.never)"
    end

    test "a cast that raises is a problem like any other, named by exception only" do
      seed = %{"CASTING_DOUBLED" => "a", "CASTING_BUGGY" => "eleven"}

      assert {:error, [problem]} = Config.resolve([Casting], static(seed))
      assert problem == "CASTING_BUGGY cast raised ArgumentError (:casting.buggy)"
      refute problem =~ "eleven"
    end

    test "a source that fails is the whole report" do
      # Not one "is not set" line per declaration: those would be false
      # statements about a file that was never opened.
      assert {:error, problems} = Config.resolve([Demo, Other], {UnreadableSource, []})

      assert problems == [
               "config source Catapult.ConfigTest.UnreadableSource: /etc/app.toml: no such file"
             ]
    end

    test "the static fake validates its seed like any other source" do
      assert {:error, [problem]} = Config.resolve([Other], static(%{}))
      assert problem == "OTHER_URL is not set (:other.url)"

      assert {:error, [seed_problem]} = Config.resolve([Other], static("not a map"))
      assert seed_problem =~ "seed must be a map"
    end

    test "a source answering with something else is reported, not matched on" do
      assert {:error, [problem]} = Config.resolve([Other], {NonsenseSource, []})
      assert problem =~ "returned :nonsense"
    end
  end
end
