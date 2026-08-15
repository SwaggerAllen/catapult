defmodule Catapult.Config.Source do
  @moduledoc """
  The config source port (systems/substrate.md): where declared values
  come from. One callback, called once, with every name every component
  declared — there is deliberately no per-key lookup.

  `load/2` is a pull, and the whole of it. A `fetch/1` port would be
  simpler only for the environment: a file or a remote source asked one
  key at a time must either re-read and re-parse per key (with no
  guarantee the reads saw one document), cache behind the layer's back
  in a store the boot report cannot see, or become a process whose
  lifecycle a two-callback port does not model. There is no `all/0`
  either, and that one is firmer: a source free to volunteer names
  nobody declared puts values into the system behind the registry's
  back, and the registry is the product (docs/non-goals.md).

  `opts` is the source's own settings, which cannot themselves come from
  the config layer — reading a config value to decide where config
  values come from is the circle it looks like. They ride the
  compile-time source selection instead, so their shape is the source's
  business: a keyword list for most (`path: "/etc/app.toml"`), and for
  `Catapult.Config.Static` the seeded map itself. Hence `term()` rather
  than `keyword()`.

  Values crossing the port are strings, always. A TOML `pool_size = 20`
  arrives here as `"20"` and the declared cast derives the integer: the
  alternative is `term()` values and casts that accept both shapes, so
  every component in every generated project pays a two-headed cast for
  a source it does not run. Present-but-empty is present — `""` is a
  value the source found, and whether empty is legal is the cast's
  business.

  **`{:error, problems}` is for the source failing, not for values being
  absent.** A name the source has no value for is simply missing from
  the returned map, and the layer reports it against the declaration
  that wanted it. A source that could not be read at all — an absent
  file, an unparseable document, an unreachable remote — returns
  `{:error, _}`, and the layer reports that and stops rather than
  falling through to the per-declaration pass: "DATABASE_URL is not set"
  is a false statement about a file that was never opened, and forty
  such lines bury the one true one.
  """

  @callback load(names :: [String.t()], opts :: term()) ::
              {:ok, %{optional(String.t()) => String.t()}}
              | {:error, problems :: [String.t()]}
end
