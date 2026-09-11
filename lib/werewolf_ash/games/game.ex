defmodule WerewolfAsh.Games.Game do
  @moduledoc """
  A single werewolf game.

  Day and night are wall-clock windows in the game's `timezone`; `day_start`
  and `day_end` are local times of day. `phase_ends_at` is the UTC instant at
  which the current phase is due to end. `state` is a plain atom here; the
  explicit transitions (`start`, `end_day`, `end_night`) and the state machine
  are layered on in a later issue.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  @states [:lobby, :day, :night, :hunter_pending, :finished]

  postgres do
    table "games"
    repo WerewolfAsh.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :join_code, :timezone, :day_start, :day_end, :owner_id]

      argument :players, {:array, :map} do
        description "Players to add to the game as it is created."
        allow_nil? false
        default []
      end

      change manage_relationship(:players, type: :create)
    end

    update :update do
      primary? true
      accept [:name, :timezone, :day_start, :day_end]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80, trim?: true
    end

    attribute :join_code, :string do
      description "Short code other users enter to join the game."
      allow_nil? false
      public? true
      constraints min_length: 4, max_length: 12, trim?: true
    end

    attribute :timezone, :string do
      description "IANA time zone name the day/night windows are expressed in."
      allow_nil? false
      public? true
      default "Etc/UTC"
    end

    attribute :day_start, :time do
      description "Local time of day at which day begins (night ends)."
      allow_nil? false
      public? true
      default ~T[08:00:00]
    end

    attribute :day_end, :time do
      description "Local time of day at which day ends (night begins)."
      allow_nil? false
      public? true
      default ~T[20:00:00]
    end

    attribute :phase_ends_at, :utc_datetime_usec do
      description "When the current phase is scheduled to end."
      public? true
    end

    attribute :state, :atom do
      allow_nil? false
      public? true
      default :lobby
      constraints one_of: @states
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, WerewolfAsh.Accounts.User do
      allow_nil? false
      public? true
    end

    has_many :players, WerewolfAsh.Games.Player do
      public? true
      sort joined_at: :asc
    end

    has_many :phases, WerewolfAsh.Games.Phase do
      public? true
      sort number: :asc
    end
  end

  identities do
    identity :unique_join_code, [:join_code]
  end
end
