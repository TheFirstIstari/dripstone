import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/dripstone start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :dripstone, DripstoneWeb.Endpoint, server: true
end

# Blank env (e.g. `PORT=`) must fall back, not raise at boot.
port =
  case Integer.parse(System.get_env("PORT", "4000")) do
    {n, _} -> n
    :error -> 4000
  end

config :dripstone, DripstoneWeb.Endpoint, http: [port: port]

# AI decision endpoint — re-read at boot in all envs so releases pick up
# the host environment. Never commit a key value.
ai_base_url = System.get_env("INTERNAL_AI_URL", "https://opencode.ai/inference/systemone/v1")
ai_model = System.get_env("INTERNAL_AI_MODEL", "jev-1.13-free")

config :dripstone, Dripstone.AIClient,
  base_url: ai_base_url,
  model: ai_model,
  api_key: System.get_env("OPENCODE_API_KEY")

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :dripstone, DripstoneWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/dripstone_web/router\.ex$"E,
        ~r"lib/dripstone_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  unless is_binary(ai_base_url) and String.starts_with?(ai_base_url, "https") do
    IO.warn("AI decision base_url is not https — credentials would travel in cleartext")
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :dripstone, Dripstone.Repo,
    # ssl: true,
    url: database_url,
    # Blank env (e.g. `POOL_SIZE=`) must fall back, not raise at boot.
    pool_size:
      (case Integer.parse(System.get_env("POOL_SIZE", "10")) do
         {n, _} -> n
         :error -> 10
       end),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  config :dripstone, Oban,
    repo: Dripstone.Repo,
    queues: [default: 10],
    plugins: [
      {Oban.Plugins.Cron, crontab: [{"0 */6 * * *", Dripstone.Workers.TrendWorker}]},
      Oban.Plugins.Pruner
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      For example: PHX_HOST=dripstone.dev
      """

  config :dripstone, DripstoneWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :dripstone, DripstoneWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :dripstone, DripstoneWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Production delivers via SMTP, configured from the environment so no
  # credentials live in the repo. Dev/test keep the Local/Test adapters.
  # Unauthenticated relays (e.g. local forwarder) must not attempt AUTH LOGIN
  # with blank credentials, and STARTTLS must stay opportunistic unless asked.
  smtp_username = System.get_env("SMTP_USERNAME", "")

  config :dripstone, Dripstone.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_HOST", "localhost"),
    # Blank env (e.g. `SMTP_PORT=`) must fall back, not raise at boot.
    port:
      (case Integer.parse(System.get_env("SMTP_PORT", "25")) do
         {n, _} -> n
         :error -> 25
       end),
    username: smtp_username,
    password: System.get_env("SMTP_PASSWORD", ""),
    tls:
      (case System.get_env("SMTP_TLS", "if_available") do
         "never" -> :never
         "always" -> :always
         _ -> :if_available
       end),
    ssl: System.get_env("SMTP_SSL", "false") in ~w(true 1),
    auth: if(smtp_username == "", do: :never, else: :always),
    from: System.get_env("MAIL_FROM", "noreply@localhost")
end
