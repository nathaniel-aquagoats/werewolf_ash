defmodule WerewolfAsh.Games.Reactors.CheckWinTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.CheckWin

  defp check(game), do: Reactor.run(CheckWin, %{game_id: game.id}, %{}, async?: false)

  defp seat(game, role, opts \\ []) do
    player = generate(player(game_id: game.id, role: role))

    if Keyword.get(opts, :alive, true),
      do: player,
      else: Games.update_player!(player, %{alive: false})
  end

  describe "run/1 against a real game" do
    setup do
      %{game: generate(game())}
    end

    test "continues while wolves are outnumbered", %{game: game} do
      seat(game, :werewolf)
      for role <- [:villager, :seer, :bodyguard], do: seat(game, role)

      assert {:ok, {:continue, %{wolves: 1, non_wolves: 3}}} = check(game)
    end

    test "the village wins once no wolf is alive", %{game: game} do
      seat(game, :werewolf, alive: false)
      seat(game, :villager)
      seat(game, :hunter)

      assert {:ok, {:village_wins, %{wolves: 0, non_wolves: 2}}} = check(game)
    end

    test "the wolves win once they outnumber the rest", %{game: game} do
      seat(game, :werewolf)
      seat(game, :werewolf)
      seat(game, :villager)
      seat(game, :villager, alive: false)

      assert {:ok, {:wolves_wins, %{wolves: 2, non_wolves: 1}}} = check(game)
    end

    test "equal numbers is a wolf win", %{game: game} do
      seat(game, :werewolf)
      seat(game, :seer)

      assert {:ok, {:wolves_wins, %{wolves: 1, non_wolves: 1}}} = check(game)
    end

    test "only counts the living, and only in this game", %{game: game} do
      seat(game, :werewolf, alive: false)
      seat(game, :werewolf, alive: false)
      seat(game, :werewolf)
      seat(game, :villager, alive: false)
      seat(game, :villager)
      seat(game, :villager)

      other = generate(game())
      seat(other, :werewolf)
      seat(other, :werewolf)

      assert {:ok, {:continue, %{wolves: 1, non_wolves: 2}}} = check(game)
    end

    test "players without a role yet count as non-wolves", %{game: game} do
      seat(game, nil)
      seat(game, nil)
      seat(game, :werewolf)

      assert {:ok, {:continue, %{wolves: 1, non_wolves: 2}}} = check(game)
    end

    test "a game with no players does not crash: no wolves means the village wins", %{
      game: game
    } do
      assert {:ok, {:village_wins, %{wolves: 0, non_wolves: 0}}} = check(game)
    end

    test "also runs with Reactor's default async steps", %{game: game} do
      seat(game, :werewolf)
      seat(game, :villager)
      seat(game, :villager)

      assert {:ok, {:continue, %{wolves: 1, non_wolves: 2}}} =
               Reactor.run(CheckWin, %{game_id: game.id})
    end

    test "never touches the game", %{game: game} do
      seat(game, :werewolf)

      assert {:ok, {:wolves_wins, _}} = check(game)

      game = Games.get_game!(game.id)
      assert game.state == :lobby
      assert is_nil(game.winner)
    end
  end

  describe "decide/1 (pure rules)" do
    test "no wolves: village" do
      assert {:village_wins, _} = CheckWin.decide(%{wolves: 0, non_wolves: 5})
    end

    test "wolves >= non-wolves: wolves" do
      assert {:wolves_wins, _} = CheckWin.decide(%{wolves: 3, non_wolves: 2})
      assert {:wolves_wins, _} = CheckWin.decide(%{wolves: 2, non_wolves: 2})
    end

    test "wolves < non-wolves: continue" do
      assert {:continue, _} = CheckWin.decide(%{wolves: 2, non_wolves: 3})
    end

    test "nobody alive: rule one wins" do
      assert {:village_wins, _} = CheckWin.decide(%{wolves: 0, non_wolves: 0})
    end

    test "counts are passed through" do
      counts = %{wolves: 1, non_wolves: 4}
      assert {:continue, ^counts} = CheckWin.decide(counts)
    end
  end

  describe "winner/1" do
    test "maps a decision onto Game.winner" do
      assert CheckWin.winner({:village_wins, %{}}) == :village
      assert CheckWin.winner({:wolves_wins, %{}}) == :wolves
      assert is_nil(CheckWin.winner({:continue, %{}}))
    end
  end
end
