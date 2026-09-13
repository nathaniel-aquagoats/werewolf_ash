defmodule WerewolfAsh.Games.Game.Validations.RoleCompositionFitsTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.Validations.RoleCompositionFits

  describe "validate/3" do
    test "passes when specials + wolves exactly fills the seated count (automatic mode)" do
      game = generate(game())
      # game() already seats the owner, so 3 more reaches 4 total: 3 specials
      # + max(1, div(4,4))=1 wolf == 4.
      generate_many(player(game_id: game.id), 3)

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert RoleCompositionFits.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :players, when short by one seat" do
      game = generate(game())
      generate_many(player(game_id: game.id), 2)

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)

      assert {:error, error} = RoleCompositionFits.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :players
    end

    test "manual mode uses the configured wolf count against the seated total" do
      game = generate(game())
      generate_many(player(game_id: game.id), 3)

      game =
        Games.update_game_settings!(
          game,
          %{role_distribution_mode: :manual, manual_werewolf_count: 1},
          actor: %{id: game.owner_id}
        )

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert RoleCompositionFits.validate(changeset, [], %{}) == :ok

      game =
        Games.update_game_settings!(game, %{manual_werewolf_count: 2},
          actor: %{id: game.owner_id}
        )

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert {:error, error} = RoleCompositionFits.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :players
    end

    test "a below-5 seat count that fits exactly passes (rule 8's guard removal)" do
      game = generate(game())
      generate_many(player(game_id: game.id), 3)

      game =
        Games.update_game_settings!(game, %{min_players: 4}, actor: %{id: game.owner_id})

      changeset = Changeset.for_update(game, :update, %{}, authorize?: false)
      assert RoleCompositionFits.validate(changeset, [], %{}) == :ok
    end
  end
end
