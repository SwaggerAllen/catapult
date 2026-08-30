defmodule CatapultWeb.Live.PositionsTest do
  @moduledoc """
  `key/2`'s own round-trip, with and without a namespace-qualifying
  anchor (dsl-syntax.md §15.12, ORC-155) — the encoding this ticket
  extends so `ORC-116` has vocabulary to consume rather than derive
  its own (`docs/ui-spec.md` §2 rule 2). Every other function here is
  a pure reshape already covered end to end through `board_live_test
  .exs`/`ticket_live_test.exs`; this file is only the encoding's own
  contract.
  """

  use ExUnit.Case, async: true

  alias CatapultWeb.Live.Positions

  describe "key/1,2 and decode_key/1 without an anchor — unchanged from before ORC-155" do
    test "a kind position round-trips" do
      assert Positions.key({:kind, :pending}) == "kind:pending"
      assert Positions.decode_key("kind:pending") == {:kind, :pending}
    end

    test "a gate position round-trips" do
      assert Positions.key({:gate, "ux-review"}) == "gate:ux-review"
      assert Positions.decode_key("gate:ux-review") == {:gate, "ux-review"}
    end

    test "decode_anchor/1 is nil for a bare key" do
      assert Positions.decode_anchor("kind:pending") == nil
      assert Positions.decode_anchor("gate:ux-review") == nil
    end
  end

  describe "key/2 and decode_key/1, decode_anchor/1 with an anchor" do
    test "a kind position qualified by its sub-array anchor round-trips" do
      key = Positions.key({:kind, :pending}, "retro")
      assert key == "kind:retro.pending"
      assert Positions.decode_key(key) == {:kind, :pending}
      assert Positions.decode_anchor(key) == "retro"
    end

    test "a gate position qualified by its sub-array anchor round-trips" do
      key = Positions.key({:gate, "product-review"}, "architecture")
      assert key == "gate:architecture.product-review"
      assert Positions.decode_key(key) == {:gate, "product-review"}
      assert Positions.decode_anchor(key) == "architecture"
    end

    test "nil anchor is the identical encoding as key/1" do
      assert Positions.key({:kind, :checks}, nil) == Positions.key({:kind, :checks})
    end
  end

  describe "lane_key/2 and resting_key/2 (ORC-116)" do
    test "an unambiguous position keeps the identical bare encoding key/1 has always produced" do
      positions = [
        %{position: {:kind, :pending}, group_key: "generation", group_anchor: false},
        %{position: {:kind, :generation}, group_key: "generation", group_anchor: true},
        %{position: {:kind, :checks}, group_key: nil, group_anchor: false}
      ]

      assert Positions.lane_key(positions, Enum.at(positions, 0)) == "kind:pending"
      assert Positions.lane_key(positions, Enum.at(positions, 2)) == "kind:checks"
    end

    test "a bare kind recurring across two entries is qualified by its own group" do
      positions = [
        %{position: {:kind, :pending}, group_key: "setup", group_anchor: false},
        %{position: {:kind, :setup}, group_key: "setup", group_anchor: true},
        %{position: {:kind, :pending}, group_key: "retro", group_anchor: false},
        %{position: {:kind, :retro}, group_key: "retro", group_anchor: true}
      ]

      assert Positions.lane_key(positions, Enum.at(positions, 0)) == "kind:setup.pending"
      assert Positions.lane_key(positions, Enum.at(positions, 2)) == "kind:retro.pending"
    end

    test "resting_key/2 finds a bare resting position's own lane key, first match" do
      positions = [
        %{position: {:kind, :pending}, group_key: "generation", group_anchor: false},
        %{position: {:kind, :generation}, group_key: "generation", group_anchor: true}
      ]

      assert Positions.resting_key(positions, {:kind, :generation}) == "kind:generation"
    end

    test "resting_key/2 is nil for nil or a position the list does not contain" do
      positions = [%{position: {:kind, :checks}, group_key: nil, group_anchor: false}]

      assert Positions.resting_key(positions, nil) == nil
      assert Positions.resting_key(positions, {:kind, :merge}) == nil
    end
  end
end
