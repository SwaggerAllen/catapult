defmodule Catapult.Dsl.ExtendsTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Extends

  @moduletag :tmp_dir

  describe "resolve_content_path/2 containment" do
    setup %{tmp_dir: dir} do
      layer = Path.join(dir, "bundles/default")
      File.mkdir_p!(Path.join(layer, "prompts"))
      File.write!(Path.join(layer, "prompts/impl.md.liquid"), "body")

      # A sibling layer, so the "prefix of another directory's name"
      # case below has something real to reach for.
      File.mkdir_p!(Path.join(dir, "bundles/default-flow"))
      File.write!(Path.join(dir, "bundles/default-flow/bundle.yaml"), "name: default-flow")

      # Something worth stealing, outside every layer.
      File.write!(Path.join(dir, "secret.txt"), "not yours")

      {:ok, layers: [{layer, %{}}], dir: dir}
    end

    test "resolves content inside the layer", %{layers: layers} do
      assert path = Extends.resolve_content_path(layers, "prompts/impl.md.liquid")
      assert File.read!(path) == "body"
    end

    test "a missing file is nil, not an error", %{layers: layers} do
      assert Extends.resolve_content_path(layers, "prompts/absent.liquid") == nil
    end

    # The value being resolved is bundle-authored (a tier's `prompt:`), and a
    # bundle is the customer's own content at the hosted tier — so an escaping
    # path must read as "not found" rather than as a file. Before the
    # containment guard this returned the escaped path and
    # `ContextAssembly.parse_template/1` read it; sobelow found it, and it was
    # reproduced against /etc/passwd before being fixed.
    test "a traversal out of the layer resolves to nil", %{layers: layers} do
      assert Extends.resolve_content_path(layers, "../../secret.txt") == nil
      assert Extends.resolve_content_path(layers, "../../../../../etc/passwd") == nil
    end

    test "an absolute path resolves to nil", %{layers: layers} do
      assert Extends.resolve_content_path(layers, "/etc/passwd") == nil
    end

    # `default-flow` starts with `default`, so a containment check comparing
    # raw string prefixes without a separator would call this contained.
    test "a sibling layer whose name extends this one's is still outside",
         %{layers: layers} do
      assert Extends.resolve_content_path(layers, "../default-flow/bundle.yaml") == nil
    end

    test "a path that leaves and returns is still refused", %{layers: layers} do
      assert Extends.resolve_content_path(layers, "../default/../../secret.txt") == nil
    end
  end
end
