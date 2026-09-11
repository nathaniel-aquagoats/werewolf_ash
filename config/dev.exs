import Config

config :werewolf_ash, WerewolfAsh.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "werewolf_ash_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true]
