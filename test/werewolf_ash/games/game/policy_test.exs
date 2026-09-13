defmodule WerewolfAsh.Games.Game.PolicyTest do
  @moduledoc """
  Rule 1 (werewolf_ash-27w.2): a `Game` is readable only while the reading
  actor holds a seat in it, any role, alive or dead. Rules 2/3a/3b (open
  actions, the owner-only gate on `:start`/`:update_settings`) are pinned in
  `games_test.exs`, whose fixtures were already set up for them.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  describe "rule 1 - Game read policy" do
    test "a seated player, alive, can read their game" do
      game = generate(game())
      player = generate(player(game_id: game.id))

      assert Games.get_game!(game.id, actor: %{id: player.user_id}).id == game.id
      assert [_] = Games.list_games!(actor: %{id: player.user_id})

      assert Games.get_game_by_join_code!(game.join_code, actor: %{id: player.user_id}).id ==
               game.id
    end

    test "a seated player, dead, can still read their game" do
      game = generate(game())
      player = generate(player(game_id: game.id))
      Games.update_player!(player, %{alive: false})

      assert Games.get_game!(game.id, actor: %{id: player.user_id}).id == game.id
    end

    test "a user with no seat in the game gets nothing back, not an error" do
      game = generate(game())
      outsider = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_game(game.id, actor: %{id: outsider.id})

      assert Games.list_games!(actor: %{id: outsider.id}) == []

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_game_by_join_code(game.join_code, actor: %{id: outsider.id})
    end

    test "an anonymous actor gets nothing back, not an error" do
      game = generate(game())

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_game(game.id)

      assert Games.list_games!() == []

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_game_by_join_code(game.join_code)
    end
  end

  describe "rule 4 (forced consequence) - join_game keeps working once Game gains a read policy" do
    test "a user with no prior seat can still join a lobby game by its join_code with no actor" do
      game = generate(game())
      user = generate(user())

      # No actor and no `authorize?: false`: real authorization runs end to
      # end. Without rule 4's `authorize?: false` fix on
      # `ResolveGameByJoinCode`'s internal `get_game_by_join_code` lookup,
      # this fails on every join code, valid or not, because the lookup runs
      # under `actor: nil` against Game's own seat-gated read policy (rule
      # 1) before the joining user holds a seat to satisfy it.
      player = Games.join_game!(game.join_code, user.id)

      assert player.user_id == user.id
      assert player.game_id == game.id
    end
  end
end
