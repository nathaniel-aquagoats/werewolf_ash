defmodule WerewolfAsh.Games.Action.Validations.ActorAliveTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.ActorAlive

  describe "validate/3" do
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
end
