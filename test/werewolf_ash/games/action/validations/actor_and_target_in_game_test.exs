defmodule WerewolfAsh.Games.Action.Validations.ActorAndTargetInGameTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.ActorAndTargetInGame

  describe "validate/3" do
    test "passes when actor, target and phase all share one game" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))
      actor = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, phase.id)
        |> Changeset.change_attribute(:actor_id, actor.id)
        |> Changeset.change_attribute(:target_id, target.id)

      assert ActorAndTargetInGame.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :actor_id, when the actor belongs to a different game than the phase" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))
      other_actor = generate(player())
      target = generate(player(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, phase.id)
        |> Changeset.change_attribute(:actor_id, other_actor.id)
        |> Changeset.change_attribute(:target_id, target.id)

      assert {:error, error} = ActorAndTargetInGame.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :actor_id
    end

    test "fails, on :target_id, when the target belongs to a different game than the phase" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))
      actor = generate(player(game_id: game.id))
      other_target = generate(player())

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, phase.id)
        |> Changeset.change_attribute(:actor_id, actor.id)
        |> Changeset.change_attribute(:target_id, other_target.id)

      assert {:error, error} = ActorAndTargetInGame.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "passes when actor_id, target_id or phase_id is absent" do
      changeset = Changeset.new(%Action{})

      assert ActorAndTargetInGame.validate(changeset, [], %{}) == :ok
    end
  end
end
