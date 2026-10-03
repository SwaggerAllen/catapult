defmodule Mix.Tasks.Catapult.Dsl.KeysTest do
  @moduledoc """
  The key-set gate's reading and comparison, against fixture schemas:
  `mix test` never needs the `pipeline` binary (`systems/core_dsl.md`
  #ORC-253-1). `run/1` itself, which shells out, is exercised by the
  gate line.
  """

  use ExUnit.Case, async: true

  alias Catapult.Dsl.Fields
  alias Mix.Tasks.Catapult.Dsl.Keys

  @schema %{
    "properties" => %{
      "name" => %{"type" => "string"},
      "tiers" => %{
        "type" => "object",
        "additionalProperties" => %{
          "properties" => %{
            "scope" => %{"type" => "string"},
            "handle" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "allOf" => [
            %{
              # a gate's own test is not a declaration
              "if" => %{"properties" => %{"generator" => %{"const" => "supplied"}}},
              "then" => %{"properties" => %{"source" => %{"type" => "string"}}}
            }
          ]
        }
      },
      "edges" => %{
        "additionalProperties" => %{
          "properties" => %{
            "instances" => %{
              "items" => %{"properties" => %{"source" => %{"type" => "string"}}}
            }
          }
        }
      },
      "types" => %{
        "additionalProperties" => %{
          "properties" => %{
            "statuses" => %{
              "items" => %{"anyOf" => [%{"$ref" => "#/$defs/entry"}, %{"type" => "array"}]}
            }
          }
        }
      }
    },
    "$defs" => %{
      "entry" => %{"properties" => %{"fills" => %{"type" => "array"}}}
    }
  }

  test "declared_paths reads properties, *, [], gated members and $defs shapes" do
    assert Keys.declared_paths(@schema) == [
             "$entry.fills",
             "edges",
             "edges.*.instances",
             "edges.*.instances[].source",
             "name",
             "tiers",
             "tiers.*.handle",
             "tiers.*.scope",
             "tiers.*.source",
             "types",
             "types.*.statuses"
           ]
  end

  test "compare is empty when the two sides name the same keys" do
    assert Keys.compare("chain", ["a", "a.*", "a.*.b"], ["a", "a.*.b"]) == []
  end

  test "compare names every path and the side that lacks it, both directions" do
    assert Keys.compare("chain", ["a", "only.doc"], ["a", "only.loader"]) == [
             "only.doc: declared in docs/dsl/chain.md, not accepted by the loader",
             "only.loader: accepted by the loader, not declared in docs/dsl/chain.md"
           ]
  end

  test "the loader's key paths close each parser's own maps" do
    for doc <- [:bundle, :chain, :workflow] do
      assert [_ | _] = Catapult.Dsl.key_paths(doc)
    end

    assert "tiers.*.review.prompt" in Catapult.Dsl.key_paths(:chain)
    assert "edges.*.instances[].source" in Catapult.Dsl.key_paths(:chain)
    assert "$entry.fills" in Catapult.Dsl.key_paths(:workflow)
  end

  test "Fields.unknown_keys closes a map against the declared paths at its prefix" do
    set =
      {["tiers.*.review.prompt", "tiers.*.review.context.*", "tiers.*.scope"], "tiers.*.review"}

    assert [problem] =
             Fields.unknown_keys(%{"prompt" => "x", "extra" => 1}, set, "r")

    assert problem =~ ~s(unknown field "extra")
    assert problem =~ ~s(known: ["prompt"])
  end
end
