import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :polticool, Polticool.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "polticool_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :polticool, PolticoolWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "lDEgNmtP5kGgTfQcpsyRBHa2zH2DClSYYrBLEPavjSK7WgPUV+SzMMMdS9FU0O32",
  server: false

# In test we don't send emails
config :polticool, Polticool.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

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

config :polticool, Polticool.Anthropic,
  api_key: "test-key",
  req_options: [plug: {Req.Test, Polticool.Anthropic}, retry: false]

config :polticool,
  research_mode: :live,
  research_replay_delay_ms: 0,
  research_cache_dir: Path.expand("../test/fixtures/research_cache", __DIR__)
