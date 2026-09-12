import Config

config :werewolf_ash, token_signing_secret: "lrngqyv3t+hJHae+6rfOT+blEue3dH9w"
config :werewolf_ash, Oban, testing: :manual

config :werewolf_ash, WerewolfAsh.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "werewolf_ash_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :werewolf_ash, WerewolfAshWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "test-only-secret-key-base-test-only-secret-key-base-test-only-secret-key"

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true
