defmodule WerewolfAsh.Games.Action.Actions.WithdrawOwnTest do
  @moduledoc """
  `Games.withdraw_own_vote/2` and `withdraw_own_protection/2` (rules 17,
  17a, werewolf_ash-27w.3): delete the caller's own row in an open day,
  no-op with none, refused for a dead caller and refused on `:game_id` when
  the open phase is not a day.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]

  defp started_game do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))
    generate_many(player(game_id: game.id), 4)
    game = Games.start_game!(game, %{now: @start}, actor: owner)

    players =
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> Map.new(&{&1.role, &1})

    %{game: game, players: players}
  end

  defp actor_for(player), do: %{id: player.user_id}

  describe "withdraw_own_vote/2" do
    setup do
      started_game()
    end

    test "deletes the caller's own row in an open day", %{game: game, players: p} do
      Games.cast_vote!(game.id, p.hunter.id, actor: actor_for(p.villager))

      Games.withdraw_own_vote!(game.id, actor: actor_for(p.villager))

      assert Games.list_actions!(
               query: [filter: [actor_id: p.villager.id, type: :vote]],
               authorize?: false
             ) == []
    end

    test "succeeds as a no-op with none", %{game: game, players: p} do
      assert Games.withdraw_own_vote!(game.id, actor: actor_for(p.villager)) == :ok
    end

    test "refused for a dead caller", %{game: game, players: p} do
      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.withdraw_own_vote(game.id, actor: actor_for(p.villager))
    end

    test "refused on :game_id when the open phase is a night, vote row untouched", %{
      game: game,
      players: p
    } do
      Games.cast_vote!(game.id, p.hunter.id, actor: actor_for(p.villager))
      game = Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.withdraw_own_vote(game.id, actor: actor_for(p.villager))

      assert [_row] =
               Games.list_actions!(
                 query: [filter: [actor_id: p.villager.id, type: :vote]],
                 authorize?: false
               )
    end

    test "fails on :game_id when there is no open phase" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      seat = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.withdraw_own_vote(game.id, actor: actor_for(seat))
    end
  end

  describe "withdraw_own_protection/2" do
    setup do
      started_game()
    end

    test "deletes the caller's own row in an open day", %{game: game, players: p} do
      Games.cast_protection!(game.id, p.villager.id, actor: actor_for(p.bodyguard))

      Games.withdraw_own_protection!(game.id, actor: actor_for(p.bodyguard))

      assert Games.list_actions!(
               query: [filter: [actor_id: p.bodyguard.id, type: :protect]],
               authorize?: false
             ) == []
    end

    test "succeeds as a no-op with none", %{game: game, players: p} do
      assert Games.withdraw_own_protection!(game.id, actor: actor_for(p.bodyguard)) == :ok
    end

    test "refused for a dead caller", %{game: game, players: p} do
      Games.update_player!(p.bodyguard, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.withdraw_own_protection(game.id, actor: actor_for(p.bodyguard))
    end

    test "refused on :game_id when the open phase is a night, protection row untouched", %{
      game: game,
      players: p
    } do
      Games.cast_protection!(game.id, p.villager.id, actor: actor_for(p.bodyguard))
      game = Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.withdraw_own_protection(game.id, actor: actor_for(p.bodyguard))

      assert [_row] =
               Games.list_actions!(
                 query: [filter: [actor_id: p.bodyguard.id, type: :protect]],
                 authorize?: false
               )
    end
  end
end
