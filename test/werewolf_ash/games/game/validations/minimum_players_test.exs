defmodule WerewolfAsh.Games.Game.Validations.MinimumPlayersTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.Validations.MinimumPlayers

  describe "validate/3" do
    test "passes at exactly 5 seated players" do
      game = generate(game())
      # game() already seats the owner, so 4 more reaches the minimum of 5.
      generate_many(player(game_id: game.id), 4)

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)

      assert MinimumPlayers.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :players, below 5 seated players" do
      game = generate(game())
      generate_many(player(game_id: game.id), 2)

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)

      assert {:error, error} = MinimumPlayers.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :players
    end

    test "reads a non-default configured min_players, including one below 5" do
      game = generate(game())
      # game() already seats the owner; 2 more reaches 3 total.
      generate_many(player(game_id: game.id), 2)

      game =
        Games.update_game_settings!(game, %{min_players: 3}, actor: %{id: game.owner_id})

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert MinimumPlayers.validate(changeset, [], %{}) == :ok

      game =
        Games.update_game_settings!(game, %{min_players: 10}, actor: %{id: game.owner_id})

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert {:error, error} = MinimumPlayers.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :players
    end
  end
end
