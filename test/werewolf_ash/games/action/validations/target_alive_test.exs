defmodule WerewolfAsh.Games.Action.Validations.TargetAliveTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.TargetAlive

  describe "validate/3" do
    test "passes for a living target" do
      game = generate(game())
      target = generate(player(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:target_id, target.id)

      assert TargetAlive.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :target_id, for a dead target" do
      game = generate(game())
      target = generate(player(game_id: game.id))
      Games.update_player!(target, %{alive: false})

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:target_id, target.id)

      assert {:error, error} = TargetAlive.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "passes when target_id is absent" do
      changeset = Changeset.new(%Action{})

      assert TargetAlive.validate(changeset, [], %{}) == :ok
    end
  end
end
