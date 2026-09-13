defmodule WerewolfAsh.Games.Reactors.CheckWin do
  @moduledoc """
  Decides whether a game is over. Pure decision: it reads the living players
  and reports the outcome, but never changes the game. Compose it wherever a
  resolution has just happened (end of day, end of night, after the hunter's
  shot) and let the caller act on the verdict —
  `WerewolfAsh.Games.Reactors.ResolveWin` does exactly that.

  ## Input

    * `game_id` — the id of the game to check.

  ## Result

  A tagged tuple `{outcome, counts}` where `counts` is
  `%{wolves: non_neg_integer, non_wolves: non_neg_integer}` (living players only):

    * `{:village_wins, counts}` — no living wolves.
    * `{:wolves_wins, counts}` — living wolves are at least as many as living
      non-wolves (equal counts is a wolf win).
    * `{:continue, counts}` — otherwise; the game goes on.

  Rules are applied in that order, exactly as the epic states them. A player
  with no role yet counts as a non-wolf.

  ### No living players

  A game with no living players is only reachable through a mutual kill (the
  hunter shooting the last wolf as they die). Rule one applies first: there
  are no living wolves, so the village wins. That also holds for a game with
  no players at all; the reactor never raises over an empty village.

  ## Running it

      {:ok, {:continue, %{wolves: 1, non_wolves: 3}}} =
        Reactor.run(WerewolfAsh.Games.Reactors.CheckWin, %{game_id: game.id})

  `count/1` and `decide/1` are the pure halves of the two steps and can be
  unit tested without a database.
  """

  use Ash.Reactor

  alias WerewolfAsh.Games.Player

  @type counts :: %{wolves: non_neg_integer, non_wolves: non_neg_integer}
  @type outcome :: :continue | :village_wins | :wolves_wins
  @type decision :: {outcome, counts}

  input :game_id

  read :living_players, Player, :living_in_game do
    description "Only living players count towards the outcome."
    inputs %{game_id: input(:game_id)}

    # This step runs with no request actor at all (the scheduler drives
    # end_day/end_night), so it must not be filtered by Player's own read
    # policy (werewolf_ash-27w.2 rule 4) - the win check needs every living
    # player, not just ones some actor could see.
    authorize? false
  end

  step :count do
    description "Tally living wolves against everyone else."
    argument :players, result(:living_players)
    run fn %{players: players}, _context -> {:ok, count(players)} end
  end

  step :decide do
    argument :counts, result(:count)
    run fn %{counts: counts}, _context -> {:ok, decide(counts)} end
  end

  return :decide

  @doc "Counts living wolves and non-wolves among `players`."
  @spec count([Player.t()]) :: counts
  def count(players) do
    Enum.reduce(players, %{wolves: 0, non_wolves: 0}, fn
      %Player{role: :werewolf}, acc -> Map.update!(acc, :wolves, &(&1 + 1))
      %Player{}, acc -> Map.update!(acc, :non_wolves, &(&1 + 1))
    end)
  end

  @doc "Applies the win rules to `counts`; see the moduledoc for the order."
  @spec decide(counts) :: decision
  def decide(%{wolves: 0} = counts), do: {:village_wins, counts}

  def decide(%{wolves: wolves, non_wolves: non_wolves} = counts) when wolves >= non_wolves,
    do: {:wolves_wins, counts}

  def decide(counts), do: {:continue, counts}

  @doc """
  The `WerewolfAsh.Games.Game.Winner` value a decision corresponds to, or nil
  when the game continues.
  """
  @spec winner(decision) :: :village | :wolves | nil
  def winner({:village_wins, _counts}), do: :village
  def winner({:wolves_wins, _counts}), do: :wolves
  def winner({:continue, _counts}), do: nil
end
