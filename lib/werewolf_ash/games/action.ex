defmodule WerewolfAsh.Games.Action do
  @moduledoc """
  Something a player does during a phase: a lynch vote, a wolf vote, a seer
  investigation, a bodyguard protection or a hunter's shot. Every action is
  aimed at a `target` player.

  A player may hold at most one action of each `type` per phase (see the
  `one_per_actor_per_phase_per_type` identity); re-submitting replaces the
  earlier choice once the upsert is wired up in a later issue.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "actions"
    repo WerewolfAsh.Repo

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
    identity :one_per_actor_per_phase_per_type, [:phase_id, :actor_id, :type]
  end
end
