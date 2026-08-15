defmodule Catapult.Component.RegistriesTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Registries

  defp row(key), do: Enum.find(Registries.rows(), &(&1.key == key))

  describe "the table" do
    test "covers the v5 §2.2 roster, config/0 deliberately excluded" do
      assert Registries.keys() == [
               :pubsub_topics,
               :oban_queues,
               :telemetry_events,
               :events,
               :processes,
               :errors,
               :externals,
               :feature_flags,
               :permissions,
               :api_surface,
               :admin,
               :policies
             ]

      refute :config in Registries.keys()
    end

    test "every row's claim and identity name fields it actually has" do
      for row <- Registries.rows(), part <- row.claim ++ row.identity do
        known =
          case part do
            {:opt, opt} -> Keyword.has_key?(row.opts, opt)
            {:route, field} -> Keyword.has_key?(row.fields, field)
            field -> Keyword.has_key?(row.fields, field)
          end

        assert known, "#{row.key} keys on #{inspect(part)}, which is not one of its columns"
      end
    end

    test "every row's required opts are opts it knows" do
      for row <- Registries.rows(), opt <- row.required_opts do
        assert Keyword.has_key?(row.opts, opt),
               "#{row.key} requires #{inspect(opt)}, which is not in its vocabulary"
      end
    end
  end

  describe "normalization" do
    test "a sugared row takes the bare name, the tuple and the opts tail" do
      queues = row(:oban_queues)

      assert {:ok, %{queue: :a_work, opts: []}} = Registries.normalize(queues, :a_work)

      assert {:ok, %{queue: :a_work, opts: [cron: [{"* * * * *", Enum}]]}} =
               Registries.normalize(queues, {:a_work, cron: [{"* * * * *", Enum}]})
    end

    test "a sugared multi-field row may omit only the opts tail" do
      processes = row(:processes)

      assert {:ok, %{name: :a, placement: :local, opts: []}} =
               Registries.normalize(processes, {:a, :local})

      assert {:ok, %{name: :a, placement: :local, opts: [max_heap_size: 100]}} =
               Registries.normalize(processes, {:a, :local, max_heap_size: 100})

      # The bare form belongs to one-field rows only.
      assert :error = Registries.normalize(processes, :a)
    end

    test "mandatory opts get no sugar" do
      externals = row(:externals)

      assert :error = Registries.normalize(externals, :stripe)

      assert {:ok, %{name: :stripe, opts: [adapter: Foo]}} =
               Registries.normalize(externals, {:stripe, adapter: Foo})
    end

    test "events take no bare form and no default version" do
      events = row(:events)

      assert :error = Registries.normalize(events, :thing_created)

      assert {:ok, %{type: :thing_created, version: 2}} =
               Registries.normalize(events, {:thing_created, 2})
    end

    test "a telemetry path is one field, not a positional list" do
      assert {:ok, %{event: [:catapult, :a, :thing], opts: []}} =
               Registries.normalize(row(:telemetry_events), [:catapult, :a, :thing])
    end

    test "an opts tail that is not a keyword list does not normalize" do
      assert :error = Registries.normalize(row(:oban_queues), {:a_work, "nightly"})
    end

    test "the expected form is derived from the row, never written twice" do
      assert Registries.expected_form(row(:pubsub_topics)) == "topic"
      assert Registries.expected_form(row(:oban_queues)) == "queue or {queue, opts}"
      assert Registries.expected_form(row(:events)) == "{type, version}"

      assert Registries.expected_form(row(:processes)) ==
               "{name, placement} or {name, placement, opts}"

      assert Registries.expected_form(row(:errors)) == "{kind, meaning, opts}"
    end
  end

  describe "collision keys" do
    test "an event's claim is its type; its identity carries the version" do
      events = row(:events)
      {:ok, v1} = Registries.normalize(events, {:thing, 1})
      {:ok, v2} = Registries.normalize(events, {:thing, 2})

      assert Registries.claim(events, v1) == Registries.claim(events, v2)
      refute Registries.identity(events, v1) == Registries.identity(events, v2)
    end

    test "a process claims its name, whatever its placement" do
      processes = row(:processes)
      {:ok, singleton} = Registries.normalize(processes, {:server, :singleton})
      {:ok, local} = Registries.normalize(processes, {:server, :local})

      assert Registries.claim(processes, singleton) == Registries.claim(processes, local)
    end

    test "a route's identity is the path's shape, not its parameter names" do
      api = row(:api_surface)

      entry = fn path ->
        {:ok, e} = Registries.normalize(api, {{:f, 1}, :get, path, version: "v1"})
        e
      end

      assert Registries.claim(api, entry.("/projects/:id")) ==
               Registries.claim(api, entry.("/projects/:project_id"))

      refute Registries.claim(api, entry.("/projects/:id")) ==
               Registries.claim(api, entry.("/projects/:id/members"))
    end

    test "a route at two versions is two routes" do
      api = row(:api_surface)

      entry = fn v ->
        {:ok, e} = Registries.normalize(api, {{:f, 1}, :get, "/x", version: v})
        e
      end

      refute Registries.claim(api, entry.("v1")) == Registries.claim(api, entry.("v2"))
    end
  end
end
