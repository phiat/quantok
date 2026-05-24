# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :quantok,
  ecto_repos: [Quantok.Repo],
  ecto_adapter: Ecto.Adapters.SQLite3,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :quantok, QuantokWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: QuantokWeb.ErrorHTML, json: QuantokWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Quantok.PubSub,
  live_view: [signing_salt: "NcB/mbJF"]

# Configure esbuild (the version is required). Bundles both JS and CSS:
# outputs land at priv/static/assets/js/app.js and priv/static/assets/css/app.css.
config :esbuild,
  version: "0.25.4",
  quantok: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
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
