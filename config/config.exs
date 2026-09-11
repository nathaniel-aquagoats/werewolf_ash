import Config

config :ash_graphql, authorize_update_destroy_with_error?: true
config :ash_oban, pro?: false

config :werewolf_ash, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: WerewolfAsh.Repo,
  plugins: [{Oban.Plugins.Cron, []}]

config :werewolf_ash,
  ecto_repos: [WerewolfAsh.Repo],
  ash_domains: [WerewolfAsh.Games, WerewolfAsh.Accounts]

config :werewolf_ash, WerewolfAshWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: WerewolfAshWeb.ErrorJSON], layout: false],
  pubsub_server: WerewolfAsh.PubSub

config :phoenix, :json_library, Jason

# Credentials travel as GraphQL variables under client-chosen names, so
# name-based filtering of a single "password" key is not enough: redact the
# whole variables map from Phoenix request logs and disable Absinthe's own
# query/variables logging.
config :phoenix, :filter_parameters, ["password", "variables"]
config :absinthe, log: false

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :graphql,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:graphql, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

import_config "#{config_env()}.exs"
