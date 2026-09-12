defmodule WerewolfAsh.Games.Game.Changes.DealRolesTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.Changes.DealRoles

  describe "change/3" do
    test "stages a role update for every seated player matching rule 10's counts" do
      game = generate(game())
      # game() already seats the owner, so 4 more reaches the minimum of 5.
      generate_many(player(game_id: game.id), 4)

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      changeset = DealRoles.change(changeset, [], %{})

      assert [hook] = changeset.after_action
      assert {:ok, ^game} = hook.(changeset, game)

      roles =
        Games.list_players!(query: [filter: [game_id: game.id]])
        |> Enum.map(& &1.role)
        |> Enum.frequencies()

      assert roles == %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 1}
    end

    test "never touches players seated in another game" do
      game = generate(game())
      generate_many(player(game_id: game.id), 4)

      other_game = generate(game())
      other_player = List.first(Games.list_players!(query: [filter: [game_id: other_game.id]]))

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      changeset = DealRoles.change(changeset, [], %{})

      assert [hook] = changeset.after_action
      assert {:ok, _game} = hook.(changeset, game)

      assert is_nil(Games.get_player!(other_player.id).role)
    end
  end
end
