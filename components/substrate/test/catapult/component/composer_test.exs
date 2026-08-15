defmodule Catapult.Component.ComposerTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Composer
  alias Catapult.Component.Registries

  defmodule CompA do
    use Catapult.Component, slug: :a
    def pubsub_topics, do: [:shared_topic, :a_only]
    def oban_queues, do: [:a_work]
    def processes, do: [{:a_server, :singleton}]
  end

  defmodule CompB do
    use Catapult.Component, slug: :b
    def pubsub_topics, do: [:shared_topic]
    def processes, do: [{:a_server, :local}]
  end

  defmodule CompBSlugDup do
    use Catapult.Component, slug: :a
  end

  defmodule NotAComponent do
    def slug, do: :nope
  end

  defmodule ConfigA do
    use Catapult.Component, slug: :cfg_a
    def config, do: [{:url, "DATABASE_URL", external: true}, {:size, "CFG_A_SIZE", []}]
  end

  defmodule ConfigB do
    use Catapult.Component, slug: :cfg_b
    def config, do: [{:url, "DATABASE_URL", external: true}]
  end

  defmodule ConfigSloppy do
    use Catapult.Component, slug: :sloppy

    def config do
      [
        {:off_spine, "POOL_SIZE", []},
        {:unknown, "SLOPPY_UNKNOWN", [secrit: true]},
        {:bad_default, "SLOPPY_BAD_DEFAULT", [cast: :integer, default: 10]},
        {:both, "SLOPPY_BOTH", [default: "x", required: false]},
        {:bad_cast, "SLOPPY_BAD_CAST", [cast: :atom]},
        {:lowercase, "sloppy_lowercase", []},
        {:dup, "SLOPPY_DUP", []},
        {:dup, "SLOPPY_DUP_TWO", []},
        :not_a_declaration
      ]
    end
  end

  test "clean set validates" do
    assert :ok = Composer.validate!([CompA])
  end

  test "collisions are reported all at once, per registry" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([CompA, CompB]) end
    assert err.message =~ "pubsub topic :shared_topic"
    assert err.message =~ "process name :a_server"
  end

  test "duplicate slugs and missing behaviour are problems" do
    err =
      assert_raise Composer.CollisionError, fn ->
        Composer.validate!([CompA, CompBSlugDup, NotAComponent])
      end

    assert err.message =~ "slug :a claimed by"
    assert err.message =~ "does not `use Catapult.Component`"
  end

  test "an env var claimed twice is a collision like a queue or a topic" do
    assert :ok = Composer.validate!([ConfigA])

    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([ConfigA, ConfigB]) end
    assert err.message =~ ~s(env var "DATABASE_URL" claimed by)
  end

  test "declaration structure is reported at build time, all at once" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([ConfigSloppy]) end

    # A name off the slug spine, without the flag that says something
    # outside this codebase imposed it.
    assert err.message =~ "POOL_SIZE is off the slug spine (expected SLOPPY_*"
    assert err.message =~ "unknown config opt :secrit"
    assert err.message =~ "non-string default 10"
    assert err.message =~ "declares both a default and required: false"
    assert err.message =~ "unusable cast :atom"
    assert err.message =~ ~s("sloppy_lowercase" is not a SCREAMING_SNAKE env var name)
    assert err.message =~ "declares config key :dup more than once"
    assert err.message =~ "malformed config declaration :not_a_declaration"
  end

  test "readiness maps slugs" do
    assert Composer.readiness([CompA, CompB]) == %{a: true, b: true}
  end

  ## The rest of the v5 §2.2 roster (ORC-22)

  defmodule Payments do
    @callback charge(pos_integer()) :: :ok
  end

  defmodule Adapter do
    @behaviour Payments
    @impl Payments
    def charge(_cents), do: :ok
  end

  defmodule Fake do
    @behaviour Payments
    @impl Payments
    def charge(_cents), do: :ok
  end

  # A fake that never adopted the adapter's contract: a test lying about
  # a system it never called.
  defmodule DriftedFake do
    def charge(_cents), do: :ok
  end

  defmodule SweepWorker do
    def __opts__, do: [queue: :roster_nightly]
  end

  defmodule ElsewhereWorker do
    def __opts__, do: [queue: :roster_work]
  end

  defmodule NotAWorker do
    def perform(_job), do: :ok
  end

  defmodule Dashboard do
    def render, do: :ok
  end

  defmodule PurityCheck do
    @behaviour Catapult.Audit.Check

    @impl Catapult.Audit.Check
    def run(_scope), do: []
  end

  defmodule NotACheck do
    def other, do: :ok
  end

  defmodule Roster do
    use Catapult.Component, slug: :roster

    defexport fetch_thing(id) do
      {:ok, id}
    end

    def oban_queues do
      [:roster_work, {:roster_nightly, cron: [{"0 3 * * *", SweepWorker}]}]
    end

    def telemetry_events, do: [[:catapult, :roster, :thing, :built]]
    # One type at two versions: ordinary, and permanent.
    def events, do: [{:thing_created, 1}, {:thing_created, 2}]

    def processes do
      [{:roster_server, :singleton}, {:roster_cache, :local, max_heap_size: 100_000}]
    end

    def errors do
      [
        {:roster_not_found, "no thing with that id",
         remedy: "check the id", runbook: "ops/roster"}
      ]
    end

    def feature_flags, do: [:roster_new_thing]
    def permissions, do: [:roster_read]

    def externals do
      [
        {:stripe,
         adapter: Adapter, fake: Fake, kill_switch: :roster_new_thing, classification: :personal}
      ]
    end

    def api_surface do
      [{{:fetch_thing, 1}, :get, "/things/:id", version: "v1", audience: :public}]
    end

    def admin, do: [{"roster", Dashboard, label: "Roster"}]
    def policies, do: [{PurityCheck, "lib/**/*.ex", policy: "es-purity"}]
  end

  defmodule RosterRival do
    use Catapult.Component, slug: :rival

    defexport fetch_thing(id) do
      {:ok, id}
    end

    # Every claim below is Roster's, spelled from another component.
    def events, do: [{:thing_created, 7}]
    def errors, do: [{:roster_not_found, "mine now", remedy: "argue"}]
    def feature_flags, do: [:roster_new_thing]
    def permissions, do: [:roster_read]
    def admin, do: [{"roster", Dashboard}]
    def policies, do: [{PurityCheck, "lib/**/*.ex", policy: "es-purity"}]

    def api_surface do
      # Same route to any router; two strings to a naive check.
      [{{:fetch_thing, 1}, :get, "/things/:thing_id", version: "v1", audience: :public}]
    end
  end

  defmodule SloppyRoster do
    use Catapult.Component, slug: :sloppy

    def oban_queues, do: [:not_on_spine]
    def telemetry_events, do: [[:catapult, :elsewhere, :thing]]
    def events, do: [:unversioned]
    def processes, do: [{:sloppy_server, :everywhere}]
    def errors, do: [{:sloppy_broken, "it broke", []}]
    def feature_flags, do: [:flag_off_spine]
    def permissions, do: [:perm_off_spine]
    def externals, do: [{:stripe, adapter: No.Such.Module, kill_switch: :sloppy_absent}]
    def api_surface, do: [{{:never_exported, 1}, :get, "things", version: "v1"}]
    def admin, do: [{"/admin/sloppy", Dashboard}]
    def policies, do: [{NotACheck, "../lib/**/*.ex", policy: 42}]
  end

  # Each declaration is well-formed on its own row; what is wrong with
  # them is a second declaration somewhere else.
  defmodule Drifting do
    use Catapult.Component, slug: :drift

    def feature_flags, do: [:drift_off]

    def oban_queues do
      [
        {:drift_nightly, cron: [{"0 3 * * *", ElsewhereWorker}]},
        {:drift_hourly, cron: [{"0 * * * *", NotAWorker}]}
      ]
    end

    def externals do
      [
        {:stripe,
         adapter: Adapter, fake: DriftedFake, kill_switch: :drift_off, classification: :none}
      ]
    end
  end

  defmodule BareCron do
    use Catapult.Component, slug: :bare
    def oban_queues, do: [{:bare_nightly, cron: "0 3 * * *"}]
  end

  defmodule NotAList do
    use Catapult.Component, slug: :notalist
    def permissions, do: :oops
  end

  defmodule Twice do
    use Catapult.Component, slug: :twice
    def permissions, do: [:twice_read, :twice_read]
    def events, do: [{:thing, 1}, {:thing, 1}]
  end

  test "a fully populated roster validates" do
    assert :ok = Composer.validate!([Roster])
  end

  test "every registry collides across components, all at once" do
    err =
      assert_raise Composer.CollisionError, fn -> Composer.validate!([Roster, RosterRival]) end

    assert err.message =~ "event type :thing_created claimed by"
    assert err.message =~ "error kind :roster_not_found claimed by"
    assert err.message =~ "feature flag :roster_new_thing claimed by"
    assert err.message =~ "permission :roster_read claimed by"
    assert err.message =~ "admin mount \"roster\" claimed by"
    assert err.message =~ "policy check {Catapult.Component.ComposerTest.PurityCheck"
    assert err.message =~ ~s(api route {"v1", :get, "/things/:param"} claimed by)
  end

  test "one component may declare one event type at two versions, forever" do
    # The claim is the type; the identity carries the version. Old
    # shapes live as long as the log does.
    assert :ok = Composer.validate!([Roster])
  end

  test "a claim held twice inside one component is a duplicate, not a collision" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([Twice]) end

    assert err.message =~ "declares permission :twice_read more than once"
    assert err.message =~ "declares event type {:thing, 1} more than once"
    refute err.message =~ "claimed by"
  end

  test "the spine check is armed wherever a claimed name is a global atom" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "oban queue :not_on_spine is off the slug spine (expected sloppy_*)"
    assert err.message =~ "feature flag :flag_off_spine is off the slug spine"
    assert err.message =~ "permission :perm_off_spine is off the slug spine"
    assert err.message =~ "telemetry event [:catapult, :elsewhere, :thing] is off the slug spine"
  end

  test "pubsub topics are the exception that proves the spine rule" do
    # The composer renders `slug:name` from a bare atom, so a prefix in
    # the atom would be the slug written twice.
    assert :ok = Composer.validate!([CompA])
  end

  test "shape problems are reported per registry, all at once" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "malformed event type entry :unversioned (expected {type, version})"
    assert err.message =~ "placement that is not one of [:local, :singleton, :sharded]"
    assert err.message =~ "error kind :sloppy_broken is missing required opt :remedy"
    assert err.message =~ "api route {:never_exported, 1} is missing required opt :audience"
    assert err.message =~ "path that is not a path beginning with /"
  end

  test "an adapter or fake that does not load is a hole the build finds" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "external :stripe is missing required opt :fake"
    assert err.message =~ "external :stripe is missing required opt :classification"
    assert err.message =~ "adapter that names a module that does not load"
  end

  test "a kill switch must name a flag its own component declares" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~
             "external :stripe names kill switch :sloppy_absent, " <>
               "which it does not declare in feature_flags/0"
  end

  test "a cron entry is {schedule, worker}, and a bare string is not one" do
    err =
      assert_raise Composer.CollisionError, fn ->
        Composer.validate!([BareCron])
      end

    assert err.message =~ "has a cron that is not a non-empty list of {schedule, worker} pairs"
  end

  test "a scheduled worker must run on the queue it was declared under" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([Drifting]) end

    assert err.message =~
             "oban queue :drift_nightly schedules " <>
               "Catapult.Component.ComposerTest.ElsewhereWorker, which runs on queue :roster_work"

    assert err.message =~
             "oban queue :drift_hourly schedules Catapult.Component.ComposerTest.NotAWorker, " <>
               "which is not an Oban worker (no __opts__/0)"
  end

  test "an external's adapter and fake must share a behaviour" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([Drifting]) end

    assert err.message =~
             "external :stripe declares adapter Catapult.Component.ComposerTest.Adapter and " <>
               "fake Catapult.Component.ComposerTest.DriftedFake, which share no behaviour"
  end

  test "api_surface accepts only functions the component exports with defexport" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "names never_exported/1, which this component does not export"
  end

  test "an admin mount is relative to a root the component does not own" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "path that is absolute (mounts are relative to the admin root)"
  end

  test "a policy scope may not leave the working directory" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([SloppyRoster]) end

    assert err.message =~ "scope that climbs out of the working directory"
    assert err.message =~ "does not implement Catapult.Audit.Check"
    assert err.message =~ "policy that is not a string"
  end

  test "a callback that does not return a list is reported, not raised through" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([NotAList]) end

    assert err.message =~ "permissions/0 returned :oops, expected a list"
  end

  describe "inventory" do
    test "every roster key is present, empty registries included" do
      inventory = Composer.inventory([])

      assert Enum.sort(Map.keys(inventory)) == Enum.sort(Registries.keys())
      assert Enum.all?(Map.values(inventory), &(&1 == []))
    end

    test "both spellings normalize into one wide form" do
      queues = Composer.inventory([Roster]).oban_queues

      assert %{queue: :roster_work, opts: []} = Enum.find(queues, &(&1.queue == :roster_work))

      assert %{queue: :roster_nightly, opts: [cron: [{"0 3 * * *", SweepWorker}]]} =
               Enum.find(queues, &(&1.queue == :roster_nightly))

      processes = Composer.inventory([Roster]).processes
      assert %{name: :roster_server, placement: :singleton, opts: []} = Enum.at(processes, 0)

      assert %{name: :roster_cache, placement: :local, opts: [max_heap_size: 100_000]} =
               Enum.at(processes, 1)
    end

    test "entries carry their owner, which is what a census counts" do
      inventory = Composer.inventory([Roster])

      assert [%{component: Roster, slug: :roster, permission: :roster_read}] =
               inventory.permissions

      assert length(inventory.events) == 2
    end

    test "malformed entries are absent — validate!/1 is what reports them" do
      assert Composer.inventory([SloppyRoster]).events == []
    end
  end
end
