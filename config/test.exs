import Config

test_database_url = System.get_env("TEST_DATABASE_URL")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bravo_credit, BravoCredit.Repo,
  url: test_database_url,
  username: if(test_database_url, do: nil, else: "postgres"),
  password: if(test_database_url, do: nil, else: "postgres"),
  hostname: if(test_database_url, do: nil, else: "localhost"),
  database:
    if(test_database_url,
      do: nil,
      else: "bravo_credit_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bravo_credit, BravoCreditWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

# In test we don't send emails
config :bravo_credit, BravoCredit.Mailer, adapter: Swoosh.Adapters.Test

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

config :bravo_credit, Oban,
  repo: BravoCredit.Repo,
  testing: :manual,
  plugins: false,
  queues: false
