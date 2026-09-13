defmodule WerewolfAsh.Games.Player do
  @moduledoc """
  A user's seat in one game. `role` is nil until the game starts and roles are
  dealt; `alive` flips to false when the player is lynched or killed.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias WerewolfAsh.Games.Player.Changes.ResolveGameByJoinCode
  alias WerewolfAsh.Games.Player.Validations.GameInLobby
  alias WerewolfAsh.Games.Player.Validations.GameNotFull
  alias WerewolfAsh.Games.Player.Validations.UserHasName

  postgres do
    table "players"
    repo WerewolfAsh.Repo

    references do
      reference :game, on_delete: :delete
    end
  end

  field_policies do
    # rule 5 - a player's role is visible on their own seat; to a fellow
    # werewolf seat, for a werewolf row; to anyone once the game has
    # finished; and to any seat that has itself died ("the dead see
    # everything"). Hidden in every other case.
    field_policy :role do
      authorize_if expr(user_id == ^actor(:id))

      authorize_if expr(
                     role == :werewolf and
                       exists(game.players, user_id == ^actor(:id) and role == :werewolf)
                   )

      authorize_if expr(game.state == :finished)

      authorize_if expr(exists(game.players, user_id == ^actor(:id) and not alive))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    read :living_in_game do
      description "The players of one game that are still alive."
      argument :game_id, :uuid, allow_nil?: false
      filter expr(game_id == ^arg(:game_id) and alive)
    end

    create :create do
      primary? true
      accept [:game_id, :user_id]
      validate UserHasName
      validate {GameNotFull, field: :game_id}, before_action?: true
    end

    create :join do
      description "Seat the given user into the game named by its join_code."
      accept [:user_id]

      argument :join_code, :string do
        allow_nil? false
      end

      change ResolveGameByJoinCode
      validate {GameInLobby, field: :join_code}
      validate UserHasName
      validate {GameNotFull, field: :join_code}, before_action?: true
    end

    update :update do
      primary? true
      accept [:role, :alive]
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      validate {GameInLobby, field: :game_id}
    end
  end

  policies do
    # rule 4 - a Player row is readable only while the reading actor
    # themselves holds a seat, any role, alive or dead, in that row's game.
    # `action_type(:read)` covers both the bare `:read` default and
    # `:living_in_game`.
    policy action_type(:read) do
      authorize_if expr(exists(game.players, user_id == ^actor(:id)))
    end

    # rule 6 - every write action stays exactly as open as it is today.
    policy action([:create, :join, :update, :destroy]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, WerewolfAsh.Games.Player.Role do
      description "Assigned when the game starts; nil while in the lobby."
      public? true
    end

    attribute :alive, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, WerewolfAsh.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :game, WerewolfAsh.Games.Game do
      allow_nil? false
      public? true
    end

    has_many :performed_actions, WerewolfAsh.Games.Action do
      public? true
      destination_attribute :actor_id
    end

    has_many :targeted_by_actions, WerewolfAsh.Games.Action do
      public? true
      destination_attribute :target_id
    end
  end

  identities do
    identity :unique_user_per_game, [:game_id, :user_id]
  end
end
