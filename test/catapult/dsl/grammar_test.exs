defmodule Catapult.Dsl.GrammarTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Grammar

  @bundles_root "bundles"
  @bundle "default"

  test "validates a well-formed body against its tier's schema" do
    body = "<vocab-entry><definition>A term.</definition></vocab-entry>"

    assert :ok =
             Grammar.validate(@bundles_root, @bundle, "vocab-entry", "schemas/vocab.xsd", body)
  end

  test "rejects a body missing a mandatory element" do
    body = "<vocab-entry><not-a-field/></vocab-entry>"

    assert {:error, {:schema_invalid, _reasons}} =
             Grammar.validate(@bundles_root, @bundle, "vocab-entry", "schemas/vocab.xsd", body)
  end

  test "rejects a mismatched root tag before even loading the schema" do
    body = "<wrong-root><definition>x</definition></wrong-root>"

    assert {:error, {:root_tag_mismatch, expected: "vocab-entry", found: "wrong-root"}} =
             Grammar.validate(@bundles_root, @bundle, "vocab-entry", "schemas/vocab.xsd", body)
  end

  test "rejects malformed XML as typed feedback, not a crash" do
    assert {:error, {:malformed_xml, _reason}} =
             Grammar.validate(
               @bundles_root,
               @bundle,
               "vocab-entry",
               "schemas/vocab.xsd",
               "<not-xml"
             )
  end

  test "reports a missing schema file" do
    assert {:error, {:schema_not_found, "schemas/does-not-exist.xsd"}} =
             Grammar.validate(
               @bundles_root,
               @bundle,
               "vocab-entry",
               "schemas/does-not-exist.xsd",
               "<vocab-entry/>"
             )
  end

  test "resolves a schema across the extends chain (the review grammar lives only in the base layer)" do
    # `default` extends `platform-elixir`, which owns `schemas/review.xsd`;
    # `default` itself carries no copy — proves specific-first-with-
    # base-fallback resolution finds it rather than reporting
    # `:schema_not_found`. Whether this particular body satisfies the
    # schema's own required attributes is exercised by the review
    # bodies `Catapult.Generation.CommitPathTest` sends through
    # `Catapult.Dsl.validate_draft/5`; this test only proves the file
    # resolves.
    body = "<review><summary>ok</summary><score>80</score></review>"

    refute match?(
             {:error, {:schema_not_found, _}},
             Grammar.validate(@bundles_root, @bundle, "review", "schemas/review.xsd", body)
           )
  end
end
