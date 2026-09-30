defmodule WerewolfAsh.Games.Announcement do
  @moduledoc """
  A public notice the game makes when the world changes: a dawn report, a dusk
  notice, a hunter's shot or the end of the game. Created only by game rules
  (`:announce`, always `authorize?: false`), readable by every seat of the
  game, dead included, and by no one else.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  alias WerewolfAsh.Games.Announcement.Death
  alias WerewolfAsh.Games.Announcement.Kind
  alias WerewolfAsh.Games.Announcement.LynchOutcome
  alias WerewolfAsh.Games.Game.Winner

  graphql do
    type :announcement
  end

  postgres do
    table "announcements"
    repo WerewolfAsh.Repo

    references do
      reference :game, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :announce do
      primary? true
      accept [:game_id, :kind, :announced_at, :deaths, :winner, :lynch_outcome, :night_starting]
    end

    read :in_game do
      description "Every announcement of one game, in the order they were made, game over last."
      argument :game_id, :uuid, allow_nil?: false
      filter expr(game_id == ^arg(:game_id))
      prepare WerewolfAsh.Games.Announcement.Preparations.InOrder
    end
  end

  policies do
    # rule 3 - any seat of the game, living or dead. Read policies filter, so
    # an outsider or no actor gets an empty list, never an error. No policy
    # allows an actor to create (rule 4).
    policy action_type(:read) do
      authorize_if expr(exists(game.players, user_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, Kind do
      allow_nil? false
      public? true
    end

    attribute :announced_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :deaths, {:array, Death} do
      allow_nil? false
      public? true
      default []
    end

    attribute :winner, Winner do
      public? true
    end

    attribute :lynch_outcome, LynchOutcome do
      public? true
    end

    attribute :night_starting, :boolean do
      allow_nil? false
      public? true
      default false
    end

    timestamps()
  end

  relationships do
    belongs_to :game, WerewolfAsh.Games.Game do
      allow_nil? false
      public? true
    end
  end

  calculations do
    # Private: what InOrder sorts on to keep game_over last.
    calculate :game_over, :boolean, expr(kind == :game_over)
  end
end
