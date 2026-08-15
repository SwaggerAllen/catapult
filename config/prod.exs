import Config

# Values a deployment differs on are declared in a component's `config/0`
# and loaded once at boot through `Catapult.Config.Env` — the compile-time
# default, so a real build cannot get a fake by omission
# (`Catapult.Boot`). What stays here is what selects the *build*: this one
# serves the health endpoint.
config :catapult, serve_health: true
