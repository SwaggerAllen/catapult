defmodule Catapult.FoundationTest do
  use ExUnit.Case, async: true

  alias Catapult.Foundation

  test "declares the values a deployment differs on, one of them external" do
    assert [
             {:database_url, "DATABASE_URL", database_opts},
             {:pool_size, "FOUNDATION_POOL_SIZE", _},
             {:health_port, "FOUNDATION_HEALTH_PORT", _},
             {:endpoint_secret_key_base, "FOUNDATION_ENDPOINT_SECRET_KEY_BASE", _}
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
end
