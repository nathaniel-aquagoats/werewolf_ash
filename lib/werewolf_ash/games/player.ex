defmodule WerewolfAsh.Games.Player do
  @moduledoc """
  A user's seat in one game. `role` is nil until the game starts and roles are
  dealt; `alive` flips to false when the player is lynched or killed.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "players"
    repo WerewolfAsh.Repo

    references do
      reference :game, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:game_id, :user_id, :role]
    end

    update :update do
      primary? true
      accept [:role, :alive]
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
