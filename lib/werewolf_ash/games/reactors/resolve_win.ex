defmodule WerewolfAsh.Games.Reactors.ResolveWin do
  @moduledoc """
  Runs the win check and, when someone has won, finishes the game.

  This is the "decide and apply" wrapper around
  `WerewolfAsh.Games.Reactors.CheckWin`: the day/night reactors compose this
  one at the end of their resolution and branch on the outcome (a finished game
  must not move on to the next phase). Compose `CheckWin` directly instead when
  you only want the verdict.

  ## Input

    * `game` — the `WerewolfAsh.Games.Game` being resolved. Pass the current
      record: the `finish` update is applied to it, so a stale struct would
      carry stale state into the transition.

  ## Result

  A map with three keys:

    * `outcome` — `:continue | :village_wins | :wolves_wins`
    * `counts` — the living `%{wolves: n, non_wolves: m}` the verdict was based on
    * `game` — the finished game (`state: :finished`, `winner` set) when there
      is a winner, otherwise the input game untouched

  ## Running it

      {:ok, %{outcome: :wolves_wins, game: %Game{state: :finished, winner: :wolves}}} =
        Reactor.run(WerewolfAsh.Games.Reactors.ResolveWin, %{game: game})
  """

  use Ash.Reactor

  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Reactors.CheckWin

  input :game

  compose :decision, CheckWin do
    argument :game_id, input(:game, [:id])
  end

  step :winner do
    argument :decision, result(:decision)
    run fn %{decision: decision}, _context -> {:ok, CheckWin.winner(decision)} end
  end

  switch :apply do
    on result(:winner)

    matches? &(&1 in [:village, :wolves]) do
      update :finish, Game, :finish do
        initial input(:game)
        inputs %{winner: result(:winner)}
      end

      return :finish
    end

    default do
      step :unchanged do
        argument :game, input(:game)
        run fn %{game: game}, _context -> {:ok, game} end
      end

      return :unchanged
    end
  end

  step :result do
    argument :decision, result(:decision)
    argument :game, result(:apply)

    run fn %{decision: {outcome, counts}, game: game}, _context ->
      {:ok, %{outcome: outcome, counts: counts, game: game}}
    end
  end

  return :result
end
