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
    extensions: [AshStateMachine, AshGraphql.Resource, AshOban]

  alias WerewolfAsh.Games.Game.Calculations.MySeat
  alias WerewolfAsh.Games.Game.Changes.AdvancePhase
  alias WerewolfAsh.Games.Game.Changes.CancelScheduledJobs
  alias WerewolfAsh.Games.Game.Changes.DealRoles
  alias WerewolfAsh.Games.Game.Changes.EndPhaseOnSchedule
  alias WerewolfAsh.Games.Game.Changes.GenerateJoinCode
  alias WerewolfAsh.Games.Game.Changes.HunterDeadlineOnSchedule
  alias WerewolfAsh.Games.Game.Changes.OpenHunterWindowAtDawn
  alias WerewolfAsh.Games.Game.Changes.OpenHunterWindowOnLynch
  alias WerewolfAsh.Games.Game.Changes.ResolveDayVote
  alias WerewolfAsh.Games.Game.Changes.ResolveHunterDeadline
  alias WerewolfAsh.Games.Game.Changes.ResolveNightWin
  alias WerewolfAsh.Games.Game.Changes.SeatOwner
  alias WerewolfAsh.Games.Game.ScheduledJobs
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

  graphql do
    type :game

    # rule 3 - owner_id is exposed as a field and as the owner relationship,
    # but never as a query/filter input named ownerId; every other
    # filterable field keeps AshGraphql's own default.
    filterable_fields [
      :id,
      :name,
      :join_code,
      :timezone,
      :day_start,
      :day_end,
      :phase_ends_at,
      :state,
      :winner,
      :pending_hunter_id,
      :hunter_deadline_at,
      :role_distribution_mode,
      :manual_werewolf_count,
      :seer_enabled,
      :bodyguard_enabled,
      :hunter_enabled,
      :min_players,
      :max_players,
      :last_phase_number,
      :owner,
      :players,
      :phases,
      :current_phase,
      :my_seat
    ]
  end

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

  # No cron: each trigger is enqueued for its exact time by ScheduledJobs
  # when a phase or hunter window opens. `lock_for_update?` is off because the
  # actions lock the row themselves, inside their own transaction.
  oban do
    triggers do
      trigger :end_phase do
        action :end_phase_on_schedule
        where expr(state in [:day, :night])
        queue :game_clock
        scheduler_cron false
        max_attempts 1_000_000
        backoff &ScheduledJobs.backoff/1
        lock_for_update? false
        worker_module_name WerewolfAsh.Games.Game.Workers.EndPhase
      end

      trigger :hunter_deadline do
        action :hunter_deadline_on_schedule
        where expr(state in [:day, :night] and not is_nil(pending_hunter_id))
        queue :game_clock
        scheduler_cron false
        max_attempts 1_000_000
        backoff &ScheduledJobs.backoff/1
        lock_for_update? false
        worker_module_name WerewolfAsh.Games.Game.Workers.HunterDeadline
      end
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

    # rules 20-23 - the GraphQL-facing create: the server invents the join
    # code and seats the caller as owner; no client `joinCode`/`ownerId`.
    create :open do
      description "Creates a new game, generating its join code and seating the caller as owner."
      accept [:name, :timezone, :day_start, :day_end]

      argument :players, {:array, :map} do
        description "Players to add to the game as it is created."
        allow_nil? false
        default []
        public? false
      end

      # rule 21 - owner_id must be staged before SeatOwner reads it, and
      # before manage_relationship builds the :players argument from it;
      # relate_actor is too late for that ordering.
      change set_attribute(:owner_id, actor(:id))
      change SeatOwner
      change manage_relationship(:players, type: :create)

      # rules 22-23 - draws the join code the client never supplies.
      change GenerateJoinCode
    end

    # rule 7 - myGames: no filter of its own (an actor-referencing filter on
    # a read action raises ReadActionRequiresActor with no token); only a
    # sort. The existing action_type(:read) policy is what narrows the
    # result to the caller's own games.
    read :mine do
      description "Every game the caller is seated in, newest created first."
      prepare build(sort: [inserted_at: :desc, id: :desc])
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
      require_atomic? false
      argument :winner, WerewolfAsh.Games.Game.Winner, allow_nil?: false
      change set_attribute(:winner, arg(:winner))

      # rule 19 - a window cannot outlive the game, whichever route finished it.
      change set_attribute(:pending_hunter_id, nil)
      change set_attribute(:hunter_deadline_at, nil)
      change transition_state(:finished)

      # werewolf_ash-qss.9 rule 22 - no timer outlives the game.
      change CancelScheduledJobs
    end

    # werewolf_ash-qss.9 - the scheduler's entry points. Each takes the
    # boundary it was enqueued for as `at` and re-checks it under a row lock.
    update :end_phase_on_schedule do
      description "Scheduler only: ends the current phase as of its recorded boundary `at`."
      accept []
      require_atomic? false

      argument :at, :utc_datetime_usec, allow_nil?: false

      change EndPhaseOnSchedule
    end

    update :hunter_deadline_on_schedule do
      description "Scheduler only: shoots a random living player once the hunter's window closes at `at`."
      accept []
      require_atomic? false

      argument :at, :utc_datetime_usec, allow_nil?: false

      change HunterDeadlineOnSchedule
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
    # werewolf_ash-qss.9 rule 19 - the AshOban worker runs with no actor.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

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

    # rule 21 - only a signed-in caller may open a game; :mine needs no
    # entry of its own, since it is a :read action already covered above.
    policy action(:open) do
      authorize_if actor_present()
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
             :resolve_hunter_deadline,
             :end_phase_on_schedule,
             :hunter_deadline_on_schedule
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

  calculations do
    # rule 9 - the caller's own seat in this game (mySeat), or nil; a module
    # calculation doing its own authorized Games.list_players read, like
    # Phase.Calculations.VoteTally.
    calculate :my_seat, :struct, {MySeat, []} do
      public? true
      allow_nil? true
      filterable? false
      constraints instance_of: WerewolfAsh.Games.Player
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
