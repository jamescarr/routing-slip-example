import Config
config :routing_examples, token_signing_secret: "d/7Cs+IrWh6h6bB/QpnICgx7F55pHy00"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :routing_examples, RoutingExamples.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "routing_examples_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :routing_examples, RoutingExamplesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3xMf8Zyv2H3ztQXfVC3Pdt5kdCLaUPevt0ZXldB53TZ4107gO5CB0QTt2sn+oTcw",
  server: false

# In test we don't send emails
config :routing_examples, RoutingExamples.Mailer, adapter: Swoosh.Adapters.Test

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
