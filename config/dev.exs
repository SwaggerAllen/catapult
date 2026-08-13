import Config

config :catapult, Catapult.Repo,
  username: "catapult",
  password: "catapult",
  hostname: "localhost",
  database: "catapult_dev",
  pool_size: 10

config :catapult, serve_health: true, health_port: 4000
