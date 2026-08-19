defmodule Catapult.Config.Static do
  @moduledoc """
  The config source fake (conventions §9): a map seeded at compile time,
  so no test reads the real environment.

  It ships in `lib/` rather than `test/support/`, deliberately.
  Conventions §9 says the fake ships with the port; for a package the
  sharper form is that it ships *in* the package. `test/support` is
  compiled only in this project's test env and is absent from the hex
  tarball, so a fake living there is a fake every generated project has
  to write again — and writing it again is exactly how a test ends up
  reading real env, which is the rule the fake exists to keep.

  The seed *is* the source's `opts`, which is why the fake needs no
  special case anywhere in the layer:

      config :catapult, :config_source,
        {Catapult.Config.Static, %{"DATABASE_URL" => "ecto://...", "FOUNDATION_POOL_SIZE" => "10"}}

  Keyed by name and valued with strings like any other source — a test
  seeds `"10"`, never `10`. Seeding post-cast values would be the
  obvious convenience and it is the wrong one: it would leave every
  declared cast unexercised by every test that is not about casts, which
  is most of them.

  The fake is not a hole. Its map is validated against the same
  declarations as any source — a missing name or a value that fails its
  cast is the same report — because a source that skipped validation
  would let a key enter the system undeclared, and the declaration is
  the product (systems/substrate.md).

  There is no `put/3` and no per-test override: a value that varies per
  test case is an argument wearing config's clothes, and the honest fix
  is the function taking it (systems/substrate.md).
  """

  @behaviour Catapult.Config.Source

  @impl Catapult.Config.Source
  def load(names, values) when is_map(values) do
    {:ok, Map.take(values, names)}
  end

  def load(_names, other) do
    {:error, ["seed must be a map of name => string, got #{inspect(other)}"]}
  end
end
