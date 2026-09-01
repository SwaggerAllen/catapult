defmodule Catapult.Dsl.BundlePathTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.BundlePath

  @moduletag :tmp_dir

  describe "resolve/2 containment" do
    setup %{tmp_dir: dir} do
      bundle = Path.join(dir, "bundles/default")
      File.mkdir_p!(Path.join(bundle, "prompts"))
      File.write!(Path.join(bundle, "prompts/impl.md.liquid"), "body")

      # A sibling bundle, so the "prefix of another directory's name"
      # case below has something real to reach for.
      File.mkdir_p!(Path.join(dir, "bundles/default-flow"))
      File.write!(Path.join(dir, "bundles/default-flow/bundle.yaml"), "name: default-flow")

      # Something worth stealing, outside every bundle.
      File.write!(Path.join(dir, "secret.txt"), "not yours")

      {:ok, bundle: bundle, dir: dir}
    end

    test "resolves content inside the bundle", %{bundle: bundle} do
      assert path = BundlePath.resolve(bundle, "prompts/impl.md.liquid")
      assert File.read!(path) == "body"
    end

    test "a missing file is nil, not an error", %{bundle: bundle} do
      assert BundlePath.resolve(bundle, "prompts/absent.liquid") == nil
    end

    # The value being resolved is bundle-authored (a tier's `prompt:`), and a
    # bundle is the customer's own content at the hosted tier — so an escaping
    # path must read as "not found" rather than as a file. Before the
    # containment guard this returned the escaped path and
    # `ContextAssembly.parse_template/1` read it; sobelow found it, and it was
    # reproduced against /etc/passwd before being fixed.
    test "a traversal out of the bundle resolves to nil", %{bundle: bundle} do
      assert BundlePath.resolve(bundle, "../../secret.txt") == nil
      assert BundlePath.resolve(bundle, "../../../../../etc/passwd") == nil
    end

    test "an absolute path resolves to nil", %{bundle: bundle} do
      assert BundlePath.resolve(bundle, "/etc/passwd") == nil
    end

    # `default-flow` starts with `default`, so a containment check comparing
    # raw string prefixes without a separator would call this contained.
    test "a sibling bundle whose name extends this one's is still outside",
         %{bundle: bundle} do
      assert BundlePath.resolve(bundle, "../default-flow/bundle.yaml") == nil
    end

    test "a path that leaves and returns is still refused", %{bundle: bundle} do
      assert BundlePath.resolve(bundle, "../default/../../secret.txt") == nil
    end
  end
end
