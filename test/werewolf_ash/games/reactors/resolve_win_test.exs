defmodule WerewolfAsh.Games.Reactors.ResolveWinTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.ResolveWin

  defp resolve(game), do: Reactor.run(ResolveWin, %{game: game}, %{}, async?: false)

  setup do
    %{game: generate(game())}
  end

  # `start_game!` now needs an owner actor and at least 5 seated players; the
  # game's own owner is already seated, so 4 more reaches the minimum.
  defp start(game) do
    owner = Games.get_game!(game.id, load: :owner, authorize?: false).owner
    generate_many(player(game_id: game.id), 4)
    Games.start_game!(game, actor: owner)
  end

  test "leaves a game alone while it continues", %{game: game} do
    generate(player(game_id: game.id, role: :werewolf))
    generate_many(player(game_id: game.id, role: :villager), 2)

    # the game's own auto-seated owner is one more living non-wolf.
    assert {:ok, %{outcome: :continue, counts: %{wolves: 1, non_wolves: 3}, game: returned}} =
             resolve(game)

    assert returned == game

    reloaded = Games.get_game!(game.id)
    assert reloaded.state == :lobby
    assert is_nil(reloaded.winner)
  end

  test "finishes the game for the village", %{game: game} do
    game = start(game)

    # Rule 10 always deals at least one living werewolf; kill it to reach
    # the village-wins state without pinning which seat held the role.
    wolf =
      Games.list_players!(query: [filter: [game_id: game.id]])
      |> Enum.find(&(&1.role == :werewolf))

    Games.update_player!(wolf, %{alive: false})

    assert {:ok, %{outcome: :village_wins, game: finished}} = resolve(game)

    assert finished.state == :finished
    assert finished.winner == :village
    assert Games.get_game!(game.id).winner == :village
  end

  test "finishes the game for the wolves", %{game: game} do
    game = start(game)

    # Kill non-wolves down to exactly one living non-wolf against the one
    # living wolf rule 10 always deals, without pinning specific seats.
    {[_wolf], non_wolves} =
      Games.list_players!(query: [filter: [game_id: game.id]])
      |> Enum.split_with(&(&1.role == :werewolf))

    [_keep_alive | to_kill] = non_wolves
    Enum.each(to_kill, &Games.update_player!(&1, %{alive: false}))

    assert {:ok, %{outcome: :wolves_wins, counts: %{wolves: 1, non_wolves: 1}, game: finished}} =
             resolve(game)

    assert finished.state == :finished
    assert finished.winner == :wolves
    assert Games.get_game!(game.id).state == :finished
  end

  test "finish_game is what it calls", %{game: game} do
    game = start(game)
    finished = Games.finish_game!(game, :wolves)

    assert finished.state == :finished
    assert finished.winner == :wolves

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :winner}]}} =
             Games.finish_game(game, :nobody)
  end
end
