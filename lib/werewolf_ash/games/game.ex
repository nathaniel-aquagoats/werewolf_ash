defmodule WerewolfAsh.Games.Game do
  @moduledoc """
  A single werewolf game.

  Day and night are wall-clock windows in the game's `timezone`; `day_start`
  and `day_end` are local times of day. `phase_ends_at` is the UTC instant at
  which the current phase is due to end.

  `state` is an `AshStateMachine`: `lobby -> (day | night) -> night -> day ...`.
  Moving between phases only ever happens through the explicit `start`,
  `end_day` and `end_night` actions, each of which takes a `now` argument so
  the rules can be exercised without a clock. `hunter_pending` and `finished`
  are declared now and reached by later issues.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  alias WerewolfAsh.Games.Game.Changes.AdvancePhase
  alias WerewolfAsh.Games.Game.Changes.DealRoles
  alias WerewolfAsh.Games.Game.Changes.ResolveDayVote
  alias WerewolfAsh.Games.Game.Changes.SeatOwner
  alias WerewolfAsh.Games.Game.Validations.ActorIsOwner
  alias WerewolfAsh.Games.Game.Validations.CompositionFitsAtCap
  alias WerewolfAsh.Games.Game.Validations.KnownTimezone
  alias WerewolfAsh.Games.Game.Validations.ManualWerewolfCountValid
  alias WerewolfAsh.Games.Game.Validations.MaxPlayersNotBelowSeated
  alias WerewolfAsh.Games.Game.Validations.MinimumPlayers
  alias WerewolfAsh.Games.Game.Validations.MinNotAboveMax
  alias WerewolfAsh.Games.Game.Validations.PositivePlayerBounds
  alias WerewolfAsh.Games.Game.Validations.RoleCompositionFits

  @states [:lobby, :day, :night, :hunter_pending, :finished]

  postgres do
    table "games"
    repo WerewolfAsh.Repo
  end

  state_machine do
    initial_states [:lobby]
    default_initial_state :lobby
    extra_states [:hunter_pending, :finished]

    transitions do
      transition :start, from: :lobby, to: [:day, :night]
      transition :end_day, from: :day, to: :night
      transition :end_night, from: :night, to: :day
      transition :finish, from: [:day, :night, :hunter_pending], to: :finished
    end
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

      change SeatOwner
      change manage_relationship(:players, type: :create)
    end

    update :update do
      primary? true
      accept [:name, :timezone, :day_start, :day_end]
    end

    # The consistency validations (rules 4-7) read resulting attribute
    # values the same way ActorIsOwner does, and MaxPlayersNotBelowSeated
    # (rule 18) is a before_action? validation, which cannot run atomically.
    update :update_settings do
      description "The owner's controls over role distribution and player bounds; locks once the game leaves the lobby."
      require_atomic? false

      accept [
        :role_distribution_mode,
        :manual_werewolf_count,
        :seer_enabled,
        :bodyguard_enabled,
        :hunter_enabled,
        :min_players,
        :max_players
      ]

      validate ActorIsOwner
      validate attribute_equals(:state, :lobby)
      validate PositivePlayerBounds
      validate MinNotAboveMax
      validate ManualWerewolfCountValid
      validate CompositionFitsAtCap
      validate MaxPlayersNotBelowSeated, before_action?: true
    end

    # The transitions read the game's windows and phases, so they cannot run
    # as a single atomic UPDATE.
    update :start do
      description "Leave the lobby for whichever window the game's clock is in."
      accept []
      require_atomic? false

      argument :now, :utc_datetime_usec do
        allow_nil? false
        default &DateTime.utc_now/0
      end

      validate ActorIsOwner
      validate MinimumPlayers
      validate RoleCompositionFits

      change DealRoles
      change {AdvancePhase, to: :by_clock}
    end

    update :end_day do
      description "Resolve the day's vote, then close the day and open the night (unless the vote just ended the game)."
      accept []
      require_atomic? false

      argument :now, :utc_datetime_usec do
        allow_nil? false
        default &DateTime.utc_now/0
      end

      change {AdvancePhase, to: :night}
      change ResolveDayVote
    end

    update :end_night do
      description "Close the night and open the day."
      accept []
      require_atomic? false

      argument :now, :utc_datetime_usec do
        allow_nil? false
        default &DateTime.utc_now/0
      end

      change {AdvancePhase, to: :day}
    end

    update :finish do
      description "Closes the game, recording which team won."
      accept []
      argument :winner, WerewolfAsh.Games.Game.Winner, allow_nil?: false
      change set_attribute(:winner, arg(:winner))
      change transition_state(:finished)
    end
  end

  validations do
    validate {KnownTimezone, attribute: :timezone}
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

    attribute :winner, WerewolfAsh.Games.Game.Winner do
      description "Set by the `finish` action once the game is over; nil while it is being played."
      public? true
    end

    attribute :role_distribution_mode, WerewolfAsh.Games.Game.RoleDistributionMode do
      description "How the werewolf count is decided: from the seated player count, or a fixed manual count."
      allow_nil? false
      public? true
      default :automatic
    end

    attribute :manual_werewolf_count, :integer do
      description "The werewolf count to deal when role_distribution_mode is :manual; read only in that mode."
      public? true
    end

    attribute :seer_enabled, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :bodyguard_enabled, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :hunter_enabled, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :min_players, :integer do
      description "The minimum number of seated players start requires."
      allow_nil? false
      public? true
      default 5
    end

    attribute :max_players, :integer do
      description "The maximum number of players who may ever be seated; nil means no cap."
      public? true
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

    has_one :current_phase, WerewolfAsh.Games.Phase do
      description "The phase that is open right now; nil in the lobby and once finished."
      public? true
      filter expr(is_nil(ended_at))
      sort number: :desc
    end
  end

  aggregates do
    max :last_phase_number, :phases, :number do
      public? true
    end
  end

  identities do
    identity :unique_join_code, [:join_code]
  end
end
