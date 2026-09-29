defmodule WerewolfAsh.Games.Game do
  @moduledoc """
  A single werewolf game.

  Day and night are wall-clock windows in the game's `timezone`; `day_start`
  and `day_end` are local times of day. `phase_ends_at` is the UTC instant at
  which the current phase is due to end.

  `state` is an `AshStateMachine`: `lobby -> (day | night) -> night -> day ...`,
  ending at `finished`. Moving between phases only ever happens through the
  explicit `start`, `end_day` and `end_night` actions, each of which takes a
  `now` argument so the rules can be exercised without a clock. An open
  hunter window is `pending_hunter_id` plus `hunter_deadline_at`, a pointer
  on the game rather than a state (werewolf_ash-qss.7): the day or night in
  progress is untouched while it is open.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  alias WerewolfAsh.Games.Game.Changes.AdvancePhase
  alias WerewolfAsh.Games.Game.Changes.DealRoles
  alias WerewolfAsh.Games.Game.Changes.OpenHunterWindowAtDawn
  alias WerewolfAsh.Games.Game.Changes.OpenHunterWindowOnLynch
  alias WerewolfAsh.Games.Game.Changes.ResolveDayVote
  alias WerewolfAsh.Games.Game.Changes.ResolveHunterDeadline
  alias WerewolfAsh.Games.Game.Changes.ResolveNightWin
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

  @states [:lobby, :day, :night, :finished]

  postgres do
    table "games"
    repo WerewolfAsh.Repo
  end

  state_machine do
    initial_states [:lobby]
    default_initial_state :lobby
    extra_states [:finished]

    transitions do
      transition :start, from: :lobby, to: [:day, :night]
      transition :end_day, from: :day, to: :night
      transition :end_night, from: :night, to: :day
      transition :finish, from: [:day, :night], to: :finished
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

      validate ActorIsOwner, before_action?: true
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

      validate ActorIsOwner, before_action?: true
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

      # rules 3-5, 9 - opens the hunter's one-hour window at once when this
      # lynch itself killed the game's dealt hunter and the dusk win check
      # left the game running; registered after ResolveDayVote so it sees
      # the lynch and the win check both already resolved.
      change OpenHunterWindowOnLynch
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

      # werewolf_ash-qss.6 rules 9-11 - dawn's own win check, one more time,
      # before opening the new day.
      change ResolveNightWin

      # rules 7-9 - opens the hunter's one-hour window at dawn when the
      # wolves' kill (not a lynch) is what killed the dealt hunter;
      # registered after ResolveNightWin so it sees the dawn win check's own
      # verdict.
      change OpenHunterWindowAtDawn
    end

    update :finish do
      description "Closes the game, recording which team won."
      accept []
      argument :winner, WerewolfAsh.Games.Game.Winner, allow_nil?: false
      change set_attribute(:winner, arg(:winner))

      # rule 19 - a window cannot outlive the game, whichever route finished it.
      change set_attribute(:pending_hunter_id, nil)
      change set_attribute(:hunter_deadline_at, nil)
      change transition_state(:finished)
    end

    # The deadline is read against the window rather than any phase timer, so
    # this cannot run as a single atomic UPDATE either.
    update :resolve_hunter_deadline do
      description "Shoots one uniformly random living player in the hunter's place, once their one-hour window has expired (rules 16-18)."
      accept []
      require_atomic? false

      argument :now, :utc_datetime_usec do
        allow_nil? false
        default &DateTime.utc_now/0
      end

      argument :pick, :integer do
        description "Test-only: selects the fallback target deterministically (index modulo the living player count) instead of drawing at random."
        allow_nil? true
      end

      change ResolveHunterDeadline
    end
  end

  policies do
    # rule 1 - a game is readable only while the actor holds a seat in it,
    # any role, alive or dead. Read policies filter by default, so an actor
    # with no seat (or no actor at all) gets nothing back, never a hard
    # authorization error.
    policy action_type(:read) do
      authorize_if expr(exists(players, user_id == ^actor(:id)))
    end

    # rules 3a/3b - only the game's owner may start it or change its
    # settings. Layered on top of ActorIsOwner's own validation, now
    # `before_action?: true` above so this policy gets to decide first.
    policy action([:start, :update_settings]) do
      authorize_if relates_to_actor_via(:owner)
    end

    # rule 2 - every other Game action stays exactly as open as it is today;
    # named explicitly so adding the authorizer does not silently
    # default-deny them. rule 21 adds :resolve_hunter_deadline to this list.
    policy action([
             :create,
             :update,
             :destroy,
             :finish,
             :end_day,
             :end_night,
             :resolve_hunter_deadline
           ]) do
      authorize_if always()
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

    attribute :pending_hunter_id, :uuid do
      description "The dealt hunter's own player id while their one-hour shot window is open; nil when none is open. No foreign key (werewolf_ash-qss.7 rule 1's own out-of-scope note) - set only via force_change_attribute inside this bead's changes, never through any action's accept list."
      public? true
    end

    attribute :hunter_deadline_at, :utc_datetime_usec do
      description "When the open hunter window expires, at which point resolve_hunter_deadline shoots a random living player in the hunter's place. Set and cleared together with pending_hunter_id."
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
