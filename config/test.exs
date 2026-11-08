import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dripstone, Dripstone.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dripstone_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # LiveView channel processes fan out full-state Store.load/Store.save
  # traffic over the single shared sandbox connection; tolerate the queue.
  pool_size: System.schedulers_online() * 2,
  queue_target: 5_000,
  queue_interval: 2_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dripstone, DripstoneWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "IJUFJ3HhrH62dFhXwutORWX3jVlD/RJWkGInQ99gO/PEH4d5TsgRA+9pWuaB+P/v",
  server: false

# In test we don't send emails
config :dripstone, Dripstone.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Oban runs inline in test — jobs never touch the DB or execute
# unless the test explicitly enqueues/performs them.
config :dripstone, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Tests seed the Live rows with the sample data, and start Demo without its
# simulator (tests drive the simulator themselves).
config :dripstone, :load_sample_data, true
config :dripstone, :demo_simulator, false
