import Config

config :werewolf_ash, Oban, testing: :manual

config :werewolf_ash, WerewolfAsh.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "werewolf_ash_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
