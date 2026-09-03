defmodule Catapult.FoundationTest do
  use ExUnit.Case, async: true

  alias Catapult.Foundation

  test "declares the values a deployment differs on, one of them external" do
    assert [
             {:database_url, "DATABASE_URL", database_opts},
             {:pool_size, "FOUNDATION_POOL_SIZE", _},
             {:health_port, "FOUNDATION_HEALTH_PORT", _},
             {:endpoint_secret_key_base, "FOUNDATION_ENDPOINT_SECRET_KEY_BASE", _},
             {:operator_token, "FOUNDATION_OPERATOR_TOKEN", _},
             {:clock, "FOUNDATION_CLOCK", _}
           ] = Foundation.config()

    # DATABASE_URL is the one name imposed from outside; the other two
    # ride the slug spine, which is what keeps the audit's prefix check
    # armed instead of turned off to accommodate this one case.
    assert database_opts[:external]
    assert database_opts[:secret]
  end

  test "registers the Erlang-egress check over the whole plane tree" do
    assert [{Catapult.Foundation.Policies.ErlangHttp, "lib/**/*.ex", opts}] =
             Foundation.policies()

    assert opts[:policy]
  end

  describe "seeded FOUNDATION_ENDPOINT_SECRET_KEY_BASE values" do
    test "every seeded environment clears Plug.Session.Cookie's own 64-byte floor" do
      # config/dev.exs and config/test.exs are pure (`import Config`, no
      # `System.get_env`, no `Mix.env`), so each reads cleanly on its
      # own without the parent config.exs. A conn-booting test proves
      # nothing here (ORC-132): every seeded environment already carries
      # a value cast through `Foundation.cast_endpoint_secret_key_base/1`
      # at boot, so the only way this regresses is a *seed* dropping
      # below the floor again — which is exactly what config/dev.exs did
      # while every request-level test stayed green.
      for {env, path} <- [dev: "config/dev.exs", test: "config/test.exs"] do
        config = Config.Reader.read!(path, env: env)
        {Catapult.Config.Static, seed} = config[:catapult][:config_source]
        value = Map.fetch!(seed, "FOUNDATION_ENDPOINT_SECRET_KEY_BASE")

        assert {:ok, ^value} = Foundation.cast_endpoint_secret_key_base(value)
      end
    end
  end

  describe "cast_database_url/1" do
    test "strips the sslmode query and configures TLS explicitly" do
      assert {:ok, opts} = Foundation.cast_database_url("ecto://u:p@host/db?sslmode=require")
      assert opts[:url] == "ecto://u:p@host/db"
      assert opts[:ssl] == [verify: :verify_none]
    end

    test "a URL without sslmode gets no TLS" do
      assert {:ok, opts} = Foundation.cast_database_url("ecto://u:p@host/db")
      assert opts == [url: "ecto://u:p@host/db", ssl: false]
    end

    test "refuses instead of raising, and its reason names no part of the value" do
      assert {:error, reason} = Foundation.cast_database_url("garbage s3cret")
      refute reason =~ "s3cret"
    end

    test "a URL with no host is refused" do
      assert {:error, _} = Foundation.cast_database_url("ecto:///db")
      assert {:error, _} = Foundation.cast_database_url("")
    end
  end

  describe "cast_endpoint_secret_key_base/1" do
    test "a value at least 64 bytes passes through" do
      value = String.duplicate("a", 64)
      assert {:ok, ^value} = Foundation.cast_endpoint_secret_key_base(value)

      longer = String.duplicate("a", 65)
      assert {:ok, ^longer} = Foundation.cast_endpoint_secret_key_base(longer)
    end

    test "a value under 64 bytes is refused, and its reason names no part of the value" do
      assert {:error, reason} = Foundation.cast_endpoint_secret_key_base("s3cret")
      refute reason =~ "s3cret"
      assert reason =~ "64"
    end
  end
end
