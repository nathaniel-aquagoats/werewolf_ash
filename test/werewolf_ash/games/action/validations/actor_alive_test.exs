defmodule WerewolfAsh.Games.Action.Validations.ActorAliveTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.ActionInput
  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.ActorAlive

  describe "validate/3 against a Changeset" do
    test "passes for a living actor" do
      game = generate(game())
      actor = generate(player(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:actor_id, actor.id)

      assert ActorAlive.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :actor_id, for a dead actor" do
      game = generate(game())
      actor = generate(player(game_id: game.id))
      Games.update_player!(actor, %{alive: false})

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:actor_id, actor.id)

      assert {:error, error} = ActorAlive.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :actor_id
    end
  end

  describe "validate/3 against an Ash.ActionInput" do
    # Built via `for_action/3`, not a bare `new/1` + `set_argument/3` (that
    # combination silently drops the argument, since `set_argument/3` only
    # casts against a bound action's own declared arguments) - mirroring
    # `Changeset.new/1` + `change_attribute/3`'s role for the
    # Changeset-based tests above as closely as the two APIs allow.
    test "passes for a living actor's id supplied as the :actor_id argument" do
      game = generate(game())
      actor = generate(player(game_id: game.id))

      input = ActionInput.for_action(Action, :withdraw, %{actor_id: actor.id})

      assert ActorAlive.validate(input, [], %{}) == :ok
    end

    test "fails, on :actor_id, for a dead actor's id" do
      game = generate(game())
      actor = generate(player(game_id: game.id))
      Games.update_player!(actor, %{alive: false})

      input = ActionInput.for_action(Action, :withdraw, %{actor_id: actor.id})

      assert {:error, error} = ActorAlive.validate(input, [], %{})
      assert Keyword.fetch!(error, :field) == :actor_id
    end
  end
end
