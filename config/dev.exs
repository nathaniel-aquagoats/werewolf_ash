import Config

config :werewolf_ash, token_signing_secret: "H31EWbLdoB908DQLfRtc0/5nje5+X+wa"

config :werewolf_ash, WerewolfAsh.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "werewolf_ash_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :werewolf_ash, WerewolfAshWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-dev-only-secret-key-base-dev-only-secret-key-base"

config :ash, policies: [show_policy_breakdowns?: true]
