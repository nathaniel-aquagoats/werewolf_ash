defmodule WerewolfAsh.Games.Reactors.ResolveWinTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.ResolveWin

  defp resolve(game), do: Reactor.run(ResolveWin, %{game: game}, %{}, async?: false)

  setup do
    %{game: generate(game())}
  end

  test "leaves a game alone while it continues", %{game: game} do
    generate(player(game_id: game.id, role: :werewolf))
    generate_many(player(game_id: game.id, role: :villager), 2)

    assert {:ok, %{outcome: :continue, counts: %{wolves: 1, non_wolves: 2}, game: returned}} =
             resolve(game)

    assert returned == game

    reloaded = Games.get_game!(game.id)
    assert reloaded.state == :lobby
    assert is_nil(reloaded.winner)
  end

  test "finishes the game for the village", %{game: game} do
    game = Games.start_game!(game)
    generate(player(game_id: game.id, role: :villager))

    assert {:ok, %{outcome: :village_wins, game: finished}} = resolve(game)

    assert finished.state == :finished
    assert finished.winner == :village
    assert Games.get_game!(game.id).winner == :village
  end

  test "finishes the game for the wolves", %{game: game} do
    game = Games.start_game!(game)
    generate(player(game_id: game.id, role: :werewolf))
    generate(player(game_id: game.id, role: :villager))

    assert {:ok, %{outcome: :wolves_wins, counts: %{wolves: 1, non_wolves: 1}, game: finished}} =
             resolve(game)

    assert finished.state == :finished
    assert finished.winner == :wolves
    assert Games.get_game!(game.id).state == :finished
  end

  test "finish_game is what it calls", %{game: game} do
    game = Games.start_game!(game)
    finished = Games.finish_game!(game, :wolves)

    assert finished.state == :finished
    assert finished.winner == :wolves

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :winner}]}} =
             Games.finish_game(game, :nobody)
  end
end
