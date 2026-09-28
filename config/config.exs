# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :posbd,
  ecto_repos: [Posbd.Repo],
  generators: [timestamp_type: :utc_datetime]

# Phase 2 SaaS subscription defaults (AGENTS.md / Phase 2 §4) - kept as
# config, not hardcoded, so the trial length can change without touching
# application logic.
config :posbd, :subscriptions, trial_period_days: 30

# Razorpay powers real subscription checkout (Phase 2 §10/§11). Real keys
# are supplied per-environment (config/dev.exs reads env vars; prod comes
# from config/runtime.exs); `req_options` lets tests swap in `Req.Test`
# instead of hitting the network.
config :posbd, :razorpay,
  key_id: nil,
  key_secret: nil,
  webhook_secret: nil,
  req_options: []

# WhatsApp Business Platform (Meta Cloud API - Phase 2 §23-§29). Real
# credentials come from config/dev.exs (env vars) or config/runtime.exs
# (prod); `req_options` lets tests swap in `Req.Test`.
config :posbd, :whatsapp,
  access_token: nil,
  phone_number_id: nil,
  app_secret: nil,
  webhook_verify_token: nil,
  api_version: "v21.0",
  req_options: []

# Background jobs (Phase 2 §35) - WhatsApp sends and campaign fan-out run
# here so they never block the HTTP request (a bill notification must
# never slow down or fail a sale) or a campaign send loop. The `:whatsapp`
# queue is separate from `:default` so a large campaign can never starve
# transactional sends (bill/payment/loyalty notifications) behind it.
config :posbd, Oban,
  repo: Posbd.Repo,
  queues: [default: 10, whatsapp: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Birthday/win-back retention automation (Phase 2 §31), once a day for
    # every business. 09:00 UTC is a reasonable single fixed time for an
    # MVP; a genuinely per-business-timezone send time is a natural
    # follow-up once this needs to feel precisely "morning" everywhere.
    {Oban.Plugins.Cron, crontab: [{"0 9 * * *", Posbd.Marketing.RetentionWorker}]}
  ]

# Business-local report date ranges (e.g. "today") need real IANA time
# zone rules to convert to/from UTC correctly (see AGENTS.md §22).
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configures the endpoint
config :posbd, PosbdWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PosbdWeb.ErrorHTML, json: PosbdWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Posbd.PubSub,
  live_view: [signing_salt: "r4dYXjAs"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :posbd, Posbd.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  posbd: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  posbd: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
