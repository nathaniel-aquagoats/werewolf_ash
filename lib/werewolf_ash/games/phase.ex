defmodule WerewolfAsh.Games.Phase do
  @moduledoc """
  One day or night of a game. Phases are numbered per game in the order they
  happen; `ended_at` and `summary` are filled in when the phase is resolved.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "phases"
    repo WerewolfAsh.Repo

    references do
      reference :game, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:game_id, :kind, :number, :started_at]
    end

    update :update do
      primary? true
      accept [:ended_at, :summary]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, WerewolfAsh.Games.Phase.Kind do
      allow_nil? false
      public? true
    end

    attribute :number, :integer do
      description "1-based position of this phase within its game."
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    attribute :ended_at, :utc_datetime_usec do
      public? true
    end

    attribute :summary, :map do
      description "Structured outcome of the phase once resolved (who died, etc.)."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :game, WerewolfAsh.Games.Game do
      allow_nil? false
      public? true
    end

    has_many :actions, WerewolfAsh.Games.Action do
      public? true
    end
  end

  identities do
    identity :unique_number_per_game, [:game_id, :number]
  end
end
