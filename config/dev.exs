import Config

# Dev reads its values through the static source, not the environment
# (systems/foundation.md). That is also what settles `.env` files: a
# dotenv file exists to feed environment variables to a process that
# reads the environment, and this one does not — the values live in the
# file a developer edits, under review, with no untracked local file to
# explain when someone's machine behaves differently from everyone
# else's (docs/non-goals.md).
#
# A seeded value is a string, like any value from any source: dev then
# exercises the same declared cast the deployment does. Seeding
# `DATABASE_URL` rather than Ecto's discrete `username`/`hostname` keys
# is the same point — one declaration, one shape for `Repo.init/2` to
# merge, in every environment.
config :catapult,
       :config_source,
       {Catapult.Config.Static,
        %{
          "DATABASE_URL" => "ecto://catapult:catapult@localhost/catapult_dev",
          "FOUNDATION_HEALTH_PORT" => "4000"
        }}

config :catapult, serve_health: true
