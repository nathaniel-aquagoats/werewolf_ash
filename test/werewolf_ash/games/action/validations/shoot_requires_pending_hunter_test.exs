defmodule WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunterTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunter

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  describe "validate/3" do
    test "passes for a hunter-role actor whose game is :hunter_pending" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      Games.update_player!(hunter, %{alive: false})
      force_state(game, :hunter_pending)

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:actor_id, hunter.id)

      assert ShootRequiresPendingHunter.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :actor_id, for a non-hunter actor while the game is :hunter_pending" do
      game = generate(game())
      villager = generate(player(game_id: game.id, role: :villager))
      force_state(game, :hunter_pending)

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:actor_id, villager.id)

      assert {:error, error} = ShootRequiresPendingHunter.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :actor_id
    end

    test "fails for a hunter actor whose game is in any other state" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      Games.update_player!(hunter, %{alive: false})

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:actor_id, hunter.id)

      assert {:error, error} = ShootRequiresPendingHunter.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :actor_id
    end
  end
end
