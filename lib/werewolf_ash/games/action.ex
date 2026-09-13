defmodule WerewolfAsh.Games.Action do
  @moduledoc """
  Something a player does during a phase: a lynch vote, a werewolf kill, a
  seer investigation, a bodyguard protection or a hunter's shot. Every
  action is aimed at a `target` player.

  A player may hold at most one action of each `type` per phase (the
  `one_per_actor_per_phase_per_type` identity): submitting the same type
  again in the same phase is refused outright — no upsert, no replacing the
  earlier choice — the actor has used up that action for the phase.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  alias WerewolfAsh.Games.Action.Changes.ApplyKill
  alias WerewolfAsh.Games.Action.Changes.RecordInvestigationResult
  alias WerewolfAsh.Games.Action.Changes.ResolveKillWin
  alias WerewolfAsh.Games.Action.Validations.ActorAlive
  alias WerewolfAsh.Games.Action.Validations.ActorAndTargetInGame
  alias WerewolfAsh.Games.Action.Validations.NoConsecutiveProtect
  alias WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunter
  alias WerewolfAsh.Games.Action.Validations.TargetAlive
  alias WerewolfAsh.Games.Action.Validations.TypeRequiresPhaseAndRole

  postgres do
    table "actions"
    repo WerewolfAsh.Repo

    identity_wheres_to_sql one_kill_per_phase: "type = 'kill'"

    references do
      reference :phase, on_delete: :delete
      reference :actor, on_delete: :delete
      reference :target, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:phase_id, :actor_id, :target_id, :type]

      # rule 12 - :kill lives on its own action, never this one.
      validate one_of(:type, [:vote, :investigate, :protect, :shoot])

      # rule 1 - the actor must be alive, except for :shoot (rule 7 governs
      # that one instead).
      validate ActorAlive, where: [one_of(:type, [:vote, :investigate, :protect])]

      # werewolf_ash-qss.18 rule 1 - the target must be alive too, except
      # for :shoot (deferred to werewolf_ash-qss.7).
      validate TargetAlive, where: [one_of(:type, [:vote, :investigate, :protect])]

      # werewolf_ash-qss.18 rules 2, 3 - actor and target must both be
      # seated in the phase's game, for every type.
      validate ActorAndTargetInGame

      # rules 2, 4, 5 - each type requires its own phase kind and (except
      # :vote) the actor's dealt role.
      validate {TypeRequiresPhaseAndRole, phase_kind: :day},
        where: [attribute_equals(:type, :vote)]

      validate {TypeRequiresPhaseAndRole, phase_kind: :night, role: :seer},
        where: [attribute_equals(:type, :investigate)]

      validate {TypeRequiresPhaseAndRole, phase_kind: :day, role: :bodyguard},
        where: [attribute_equals(:type, :protect)]

      # rule 6 - a bodyguard may never protect themselves.
      validate compare(:target_id, is_not_equal: {:ref, :actor_id}),
        where: [attribute_equals(:type, :protect)]

      # werewolf_ash-qss.18 rule 4 - a bodyguard may not protect the same
      # player two days in a row.
      validate NoConsecutiveProtect, where: [attribute_equals(:type, :protect)]

      # rule 7 - a shot requires the actor to be the game's pending hunter.
      validate ShootRequiresPendingHunter, where: [attribute_equals(:type, :shoot)]

      # rule 8 - the seer's answer is computed the instant the row is created.
      change RecordInvestigationResult
    end

    create :kill do
      description "The pack's one kill for the night; see the one_kill_per_phase identity."
      accept [:phase_id, :actor_id, :target_id]

      change set_attribute(:type, :kill)

      # rules 1 and 3, unconditionally - this action is never anything but a
      # kill, so neither validation needs a `where:`.
      validate ActorAlive
      validate {TypeRequiresPhaseAndRole, phase_kind: :night, role: :werewolf}

      # werewolf_ash-qss.18 rules 1, 2, 3, unconditionally - same as above,
      # :kill is never anything else.
      validate TargetAlive
      validate ActorAndTargetInGame

      # rule 13 - the kill's immediate effect.
      change ApplyKill

      # werewolf_ash-qss.6 rules 1, 3, 4 - the immediate win check that
      # follows a landed kill; a spent kill runs no check at all.
      change ResolveKillWin
    end

    update :update do
      primary? true
      accept [:result]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, WerewolfAsh.Games.Action.Type do
      allow_nil? false
      public? true
    end

    attribute :result, :map do
      description "Outcome recorded when the action resolves (e.g. a seer's answer)."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :phase, WerewolfAsh.Games.Phase do
      allow_nil? false
      public? true
    end

    belongs_to :actor, WerewolfAsh.Games.Player do
      allow_nil? false
      public? true
    end

    belongs_to :target, WerewolfAsh.Games.Player do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_actor_per_phase_per_type, [:phase_id, :actor_id, :type],
      message: "you've already used this action for this phase"

    # rule 11 - at most one :kill per phase, enforced by the database via a
    # partial unique index (see `identity_wheres_to_sql` above).
    identity :one_kill_per_phase, [:phase_id], where: expr(type == :kill)
  end
end
