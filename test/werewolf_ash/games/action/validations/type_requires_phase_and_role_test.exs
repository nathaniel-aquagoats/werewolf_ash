defmodule WerewolfAsh.Games.Action.Validations.TypeRequiresPhaseAndRoleTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.TypeRequiresPhaseAndRole

  describe "init/1" do
    test "accepts an atom phase_kind, with or without an atom role" do
      assert TypeRequiresPhaseAndRole.init(phase_kind: :day) == {:ok, [phase_kind: :day]}

      assert TypeRequiresPhaseAndRole.init(phase_kind: :night, role: :seer) ==
               {:ok, [phase_kind: :night, role: :seer]}
    end

    test "rejects a non-atom or nil phase_kind" do
      assert {:error, _reason} = TypeRequiresPhaseAndRole.init(phase_kind: "day")
      assert {:error, _reason} = TypeRequiresPhaseAndRole.init(phase_kind: nil)
    end
  end

  describe "validate/3" do
    test "a matching phase_kind with no role opt passes regardless of the actor's role" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      actor = generate(player(game_id: game.id, role: :villager))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, day.id)
        |> Changeset.change_attribute(:actor_id, actor.id)

      assert TypeRequiresPhaseAndRole.validate(changeset, [phase_kind: :day], %{}) == :ok
    end

    test "a mismatched phase_kind fails on :type regardless of role" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      actor = generate(player(game_id: game.id, role: :seer))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, night.id)
        |> Changeset.change_attribute(:actor_id, actor.id)

      assert {:error, error} =
               TypeRequiresPhaseAndRole.validate(changeset, [phase_kind: :day, role: :seer], %{})

      assert Keyword.fetch!(error, :field) == :type
    end

    test "a matching phase_kind plus role passes when the actor's role matches, fails otherwise" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      seer = generate(player(game_id: game.id, role: :seer))
      villager = generate(player(game_id: game.id, role: :villager))

      matching =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, night.id)
        |> Changeset.change_attribute(:actor_id, seer.id)

      assert TypeRequiresPhaseAndRole.validate(
               matching,
               [phase_kind: :night, role: :seer],
               %{}
             ) == :ok

      mismatched =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, night.id)
        |> Changeset.change_attribute(:actor_id, villager.id)

      assert {:error, error} =
               TypeRequiresPhaseAndRole.validate(
                 mismatched,
                 [phase_kind: :night, role: :seer],
                 %{}
               )

      assert Keyword.fetch!(error, :field) == :type
    end
  end
end
