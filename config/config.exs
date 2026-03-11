# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bravo_credit,
  ecto_repos: [BravoCredit.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :bravo_credit, :country_config_path, Path.expand("countries", __DIR__)

config :bravo_credit, BravoCredit.Cache,
  name: :bravo_credit_cache,
  default_ttl_ms: :timer.seconds(60)

config :bravo_credit, Oban,
  repo: BravoCredit.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ],
  queues: [
    default: 10,
    providers: 5,
    risk: 5,
    webhooks: 5,
    outbox: 5
  ]

config :cloak_ecto, json_library: Jason

# Configure the endpoint
config :bravo_credit, BravoCreditWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BravoCreditWeb.ErrorHTML, json: BravoCreditWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BravoCredit.PubSub,
  live_view: [signing_salt: "D4maaF+U"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bravo_credit, BravoCredit.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bravo_credit: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  bravo_credit: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
