defmodule WerewolfAsh.Games.Game.Validations.MaxPlayersNotBelowSeatedTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game.Validations.MaxPlayersNotBelowSeated

  describe "validate/3" do
    test "passes when the resulting max_players is above the seated count" do
      game = generate(game())
      # game() already seats the owner, so 2 more reaches 3 total.
      generate_many(player(game_id: game.id), 2)

      changeset =
        Changeset.for_update(game, :update_settings, %{max_players: 4}, authorize?: false)

      assert MaxPlayersNotBelowSeated.validate(changeset, [], %{}) == :ok
    end

    test "passes when the resulting max_players exactly equals the seated count" do
      game = generate(game())
      generate_many(player(game_id: game.id), 2)

      changeset =
        Changeset.for_update(game, :update_settings, %{max_players: 3}, authorize?: false)

      assert MaxPlayersNotBelowSeated.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :max_players, when it would drop below the seated count" do
      game = generate(game())
      generate_many(player(game_id: game.id), 2)

      changeset =
        Changeset.for_update(game, :update_settings, %{max_players: 2}, authorize?: false)

      assert {:error, error} = MaxPlayersNotBelowSeated.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :max_players
    end

    test "a nil resulting max_players is never subject to this check" do
      game = generate(game())
      generate_many(player(game_id: game.id), 2)

      changeset = Changeset.for_update(game, :update_settings, %{}, authorize?: false)

      assert MaxPlayersNotBelowSeated.validate(changeset, [], %{}) == :ok
    end
  end
end
