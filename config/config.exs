# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dripstone, :scopes,
  user: [
    default: true,
    module: Dripstone.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Dripstone.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :dripstone,
  ecto_repos: [Dripstone.Repo],
  generators: [timestamp_type: :utc_datetime]

# Platform feeds, in display order. Adding a platform: write a module that
# implements Dripstone.Feeds.Feed and add it here (see openspec/docs/FEEDS.md).
config :dripstone, Dripstone.Feeds,
  feeds: [
    Dripstone.Feeds.X,
    Dripstone.Feeds.Reddit,
    Dripstone.Feeds.Bluesky,
    Dripstone.Feeds.Mastodon,
    Dripstone.Feeds.Telegram,
    Dripstone.Feeds.Facebook
  ]

# Alert trigger types, in display order. Ids are stable strings that detection
# reports findings with. Adding one: append an entry here (see openspec/docs/TRIGGERS.md).
config :dripstone, Dripstone.Alerts,
  trigger_types: [
    [
      id: "new_network",
      name: "New network",
      description: "A new group of linked accounts looks like a possible bot farm."
    ],
    [
      id: "network_growth",
      name: "Network growth",
      description: "A known network has gained new member accounts."
    ],
    [
      id: "network_reactivation",
      name: "Network reactivation",
      description: "A dormant network has started posting again."
    ],
    [
      id: "promotion_shift",
      name: "Promotion shift",
      description: "A network has changed the domain or promotion it spreads."
    ],
    [
      id: "coordination_rising",
      name: "Coordination rising",
      description: "An active network's coordination is increasing."
    ]
  ]

# Alert rules for detection findings (see openspec/docs/DETECTION_INTERFACE.md).
# Probabilities are 0–1: `yes` is the threshold for a yes answer; `severity` and
# `strength` are lower bounds of the bands (below the last band is Low / Weak).
# The caps bound what findings add to the in-memory store.
config :dripstone, Dripstone.Tracker.Rules,
  yes: 0.7,
  severity: [high: 0.9, medium: 0.8],
  strength: [strong: 0.85, moderate: 0.7],
  posts_per_account: 200,
  provenance_per_link: 20,
  findings_log: 500

# Configure the endpoint
config :dripstone, DripstoneWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DripstoneWeb.ErrorHTML, json: DripstoneWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dripstone.PubSub,
  live_view: [signing_salt: "rEODX5OF"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :dripstone, Dripstone.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  dripstone: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  dripstone: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# AI decision endpoint (OpenCode Console, TypeSafe AI). Static defaults only —
# real values come from the environment at boot (see runtime.exs). Never
# commit a key value here.
config :dripstone, Dripstone.AIClient,
  base_url: "https://opencode.ai/inference/systemone/v1",
  model: "jev-1.13-free"

# What an empty Live (database) dataset is seeded with on first boot: false
# (nothing: Live fills from real detection), :showcase (hand-built corpus, dev
# opt-in) or true (generated sample rows, used by tests). The sample data lives in
# the memory-only Demo dataset instead (DemoStore); prod.exs pins false (#50).
config :dripstone, :load_sample_data, false

# Live discovery (Bluesky Jetstream -> bursts -> DiscoverWorker). Off by default;
# prod.exs turns it on, dev turns it on with DRIPSTONE_DISCOVERY=1.
config :dripstone, Dripstone.Discovery, enabled: false

# Oban background jobs. Test env overrides with `testing: :manual`;
# prod re-asserts at runtime (see runtime.exs) so releases pick it up.
config :dripstone, Oban,
  repo: Dripstone.Repo,
  queues: [default: 10],
  plugins: [
    # Live networks get a trend re-check every 6 hours (add-bluesky-live-pipeline).
    {Oban.Plugins.Cron, crontab: [{"0 */6 * * *", Dripstone.Workers.TrendWorker}]},
    Oban.Plugins.Pruner
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
