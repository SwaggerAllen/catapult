defmodule Catapult.Config.Secret do
  @moduledoc """
  The wrapper a `secret: true` declaration resolves to (v5 §2.2,
  systems/substrate.md's enforcement roster).

  ## Why a type rather than a check

  "Never appears in logs or error payloads" is a claim about *values*,
  and an audit sees source. The honest static version is a shallow check
  one hop from the accessor, which misses every value bound to a variable
  first — and a check that misses the ordinary case while looking like
  coverage is worse than no check. The type holds it everywhere instead:
  interpolation, `inspect/1`, a `Logger` call, an error payload and a
  crash dump are all safe by construction, because the only way to a
  secret's contents is `unwrap/1`, written at the call site and visible
  in the diff. §2.2's "settings surfaces mask by construction" then stops
  being a separate rule about one screen.

  The residue the audit keeps is one hop and no inference: an `unwrap`
  inside a logging call (`Catapult.Audit.Checks.SecretInLog`).

  ## Wrapped on resolution, not on read

  `Catapult.Config` wraps while resolving, so the write-once store never
  holds a bare secret either — a strictly stronger placement than
  wrapping at `fetch!/2`, for the price of nothing, and one that covers
  the store's own appearance in a crash dump.

  ## The cost, paid once

  Every consumer of a secret must unwrap. There is exactly one in this
  tree today (`DATABASE_URL`, on its way into `Catapult.Repo.init/2`),
  which is the whole argument for doing it now: the wrapper is free while
  there is one reader and a migration once there are twenty.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @typedoc "A declared-secret value, redacted at every surface but `unwrap/1`."
  @opaque t :: %__MODULE__{value: term()}

  @redacted "[REDACTED]"

  @doc "Wraps a resolved value declared `secret: true`."
  @spec wrap(term()) :: t()
  def wrap(value), do: %__MODULE__{value: value}

  @doc """
  The value inside, at an explicit call site.

  The one way out, and deliberately not a protocol or an implicit cast:
  what makes the wrapper worth having is that reaching past it is a word
  a reviewer can see.
  """
  @spec unwrap(t()) :: term()
  def unwrap(%__MODULE__{value: value}), do: value

  @doc "What every surface but `unwrap/1` shows."
  @spec redacted() :: String.t()
  def redacted, do: @redacted

  defimpl Inspect do
    alias Catapult.Config.Secret

    def inspect(_secret, _opts) do
      Inspect.Algebra.concat(["#Catapult.Config.Secret<", Secret.redacted(), ">"])
    end
  end

  defimpl String.Chars do
    alias Catapult.Config.Secret

    def to_string(_secret), do: Secret.redacted()
  end
end
