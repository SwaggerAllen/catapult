defmodule Catapult.Foundation do
  @moduledoc """
  Catapult's application root component (systems/foundation.md): the
  Repo, Oban, and infrastructure persistence. Oban's queues are claimed
  by the components that own them via `oban_queues/0`; the foundation
  only hosts the runtime.
  """
  use Catapult.Component, slug: :foundation

  alias Ecto.Adapters.SQL

  # The plane is reached over a network by people who are not its
  # operator — the hosted tier is the product — which is the case
  # `:service` exists to name, not `:internal` (ORC-51,
  # systems/foundation.md). `{:service, :listed}` arms no dependency
  # check, as it should: we offer source on AGPL's own terms.
  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def config do
    [
      # The one name imposed from outside: App Platform injects
      # DATABASE_URL under a name we do not choose, and
      # FOUNDATION_DATABASE_URL is not on offer (SETUP.md §2). That is
      # what `external: true` is for, and it confers nothing — it only
      # makes this case distinguishable from sloppiness, so the audit's
      # spine check can stay armed for the two below.
      {:database_url, "DATABASE_URL",
       cast: &__MODULE__.cast_database_url/1, secret: true, external: true},
      {:pool_size, "FOUNDATION_POOL_SIZE", cast: :integer, default: "2"},
      # Deliberately not PORT: this is the app's HTTP listener (the
      # health endpoint). App Platform routes public traffic to 8080 and
      # that isn't changeable in its UI, so 8080 is the default and this
      # variable is the explicit override.
      {:health_port, "FOUNDATION_HEALTH_PORT", cast: :integer, default: "8080"},
      # `CatapultWeb.Endpoint`'s own secret (ORC-35's dev pass): signs
      # the LiveView socket's connect tokens and the session cookie
      # `Plug.Session` needs to hang a CSRF token on. No default, like
      # `database_url` and `github_token` — a build without it fails at
      # boot with the config report naming it, the same failure mode
      # SETUP.md §2 already documents for the token. The cast enforces
      # `Plug.Session.Cookie`'s own 64-byte floor (ORC-132): without it,
      # a too-short value boots clean and only raises on the first
      # request through the `:browser` pipeline, instead of naming
      # itself in the boot report next to every other wrong variable.
      {:endpoint_secret_key_base, "FOUNDATION_ENDPOINT_SECRET_KEY_BASE",
       cast: &__MODULE__.cast_endpoint_secret_key_base/1, secret: true}
    ]
  end

  @doc """
  Casts a database URL into the options `Catapult.Repo` merges.

  This is where `runtime.exs`'s hand-parsing went (systems/foundation.md).
  DO managed Postgres injects a URL ending in `?sslmode=require`, and
  Ecto's URL parser rejects `sslmode` as an option, so the query string
  is stripped and TLS configured explicitly. `verify_none` is deliberate
  for now: the bindable URL points at the cluster over DO's network. The
  record of that choice, including the revisit condition, is
  `systems/foundation.md`'s TLS bullet (ORC-83) — not this docstring,
  and not the maintenance lane, which watches hex/GitHub advisories and
  has no way to see a `verify_none` literal in application code.

  It returns `{:error, _}` rather than raising, like every declared cast:
  a URL that cannot be parsed is one line in the boot report next to
  everything else that is wrong, not an `ArgumentError` from inside a
  config library with the other four problems still undiscovered. The
  reason names no part of the value — this one carries a password.
  """
  @spec cast_database_url(String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def cast_database_url(raw) do
    [base | _query] = String.split(raw, "?", parts: 2)

    case URI.new(base) do
      {:ok, %URI{scheme: scheme, host: host}}
      when is_binary(scheme) and is_binary(host) and host != "" ->
        {:ok, [url: base, ssl: ssl_option(raw)]}

      _ ->
        {:error, "is not a database URL (expected scheme://user:password@host/database)"}
    end
  end

  defp ssl_option(raw) do
    if String.contains?(raw, "sslmode=require"), do: [verify: :verify_none], else: false
  end

  # Plug.Session.Cookie's own floor (`byte_size(secret_key_base) < 64`
  # raises `ArgumentError` there, verified against its source rather
  # than assumed). Declaring the minimum where the value is declared is
  # what makes a too-short seed a boot-time report line rather than a
  # 500 on the first request through the `:browser` pipeline (ORC-132).
  # The reason names no part of the value, same as `cast_database_url/1`
  # above — the byte count is not the secret.
  @spec cast_endpoint_secret_key_base(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def cast_endpoint_secret_key_base(raw) when byte_size(raw) >= 64, do: {:ok, raw}

  def cast_endpoint_secret_key_base(raw) do
    {:error, "must be at least 64 bytes (Plug.Session.Cookie's minimum), is #{byte_size(raw)}"}
  end

  @impl Catapult.Component
  def policies do
    [
      {Catapult.Foundation.Policies.ErlangHttp, "lib/**/*.ex",
       policy: "conventions §11: no plane module calls a pure Erlang HTTP client"}
    ]
  end

  @impl Catapult.Component
  def children do
    if Application.get_env(:catapult, :start_persistence, true) do
      [Catapult.Repo, {Oban, Application.fetch_env!(:catapult, Oban)}]
    else
      []
    end
  end

  @impl Catapult.Component
  def ready? do
    if Application.get_env(:catapult, :start_persistence, true) do
      match?({:ok, _}, SQL.query(Catapult.Repo, "SELECT 1", []))
    else
      true
    end
  rescue
    _ -> false
  end
end
