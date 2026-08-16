defmodule Catapult.Config.SecretTest do
  use ExUnit.Case, async: true

  alias Catapult.Config.Secret

  @value "postgres://user:hunter2@db/app"

  test "inspect redacts, which is what covers a crash dump" do
    secret = Secret.wrap(@value)

    refute inspect(secret) =~ "hunter2"
    assert inspect(secret) =~ "REDACTED"
    # And nested, which is the case a shallow check would miss.
    refute inspect(%{url: secret, size: 10}) =~ "hunter2"
  end

  test "interpolation redacts, which is what covers a Logger call" do
    refute "#{Secret.wrap(@value)}" =~ "hunter2"
    assert to_string(Secret.wrap(@value)) == Secret.redacted()
  end

  test "the value comes out at an explicit call site and nowhere else" do
    assert Secret.unwrap(Secret.wrap(@value)) == @value
  end

  test "a secret declaration is wrapped on resolution, so the store never holds one" do
    components = [Catapult.Config.SecretTest.Component]
    source = {Catapult.Config.Static, %{"SECRETY_TOKEN" => "s3kr1t", "SECRETY_HOST" => "db"}}

    assert {:ok, values} = Catapult.Config.resolve(components, source)

    assert %Secret{} = values[{:secrety, :token}]
    assert Secret.unwrap(values[{:secrety, :token}]) == "s3kr1t"
    # Only the flagged one: the wrapper is a declaration's property.
    assert values[{:secrety, :host}] == "db"
    refute inspect(values) =~ "s3kr1t"
  end

  test "an absent optional secret is still a secret, so consumers have one spelling" do
    components = [Catapult.Config.SecretTest.Component]
    source = {Catapult.Config.Static, %{"SECRETY_HOST" => "db"}}

    assert {:ok, values} = Catapult.Config.resolve(components, source)
    assert %Secret{} = values[{:secrety, :token}]
    assert Secret.unwrap(values[{:secrety, :token}]) == nil
  end

  defmodule Component do
    use Catapult.Component, slug: :secrety

    def config do
      [
        {:token, "SECRETY_TOKEN", secret: true, required: false},
        {:host, "SECRETY_HOST", []}
      ]
    end
  end
end
