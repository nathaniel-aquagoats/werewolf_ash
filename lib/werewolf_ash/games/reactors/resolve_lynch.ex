defmodule WerewolfAsh.Games.Reactors.ResolveLynch do
  @moduledoc """
  Resolves one day's vote.

  Loads the still-valid `:vote` `WerewolfAsh.Games.Action` rows cast in one
  phase — a vote from a voter who is no longer alive, or naming a target who
  is no longer alive, is dropped first — tallies them, and lynches whoever
  holds a strict plurality (a tie, or no votes at all, lynches nobody).
  Afterwards, win or lose, it checks whether either side has won by
  composing `WerewolfAsh.Games.Reactors.ResolveWin`, which finishes the game
  when someone has.

  ## Input

    * `phase_id` — the day phase whose `:vote` actions to count. Never
      derived from the game's own state or from which phases happen to be
      open or closed: the caller already knows which phase it means to
      resolve.
    * `game_id` — the game to check the win condition for, once the lynch
      has been applied (or not).

  ## Result

  Whatever `WerewolfAsh.Games.Reactors.ResolveWin` returns: a map with
  `outcome`, `counts` and `game` (see its own moduledoc).

  ## Running it

      Reactor.run(
        WerewolfAsh.Games.Reactors.ResolveLynch,
        %{phase_id: phase.id, game_id: game.id},
        %{},
        async?: false
      )

  `tally/1` and `decide/1` are the pure halves and can be unit tested without
  a database.
  """

  use Ash.Reactor

  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Reactors.ResolveWin

  @type tally :: %{optional(term) => [term]}
  @type decision :: {:lynch, term} | :no_lynch

  input :phase_id
  input :game_id

  step :load_votes do
    argument :phase_id, input(:phase_id)

    run fn %{phase_id: phase_id}, _context ->
      votes =
        Games.list_actions!(
          load: [:actor, :target],
          query: [filter: [phase_id: phase_id, type: :vote]],
          authorize?: false
        )

      {:ok, Enum.filter(votes, &(&1.actor.alive and &1.target.alive))}
    end
  end

  step :tally do
    argument :votes, result(:load_votes)
    run fn %{votes: votes}, _context -> {:ok, tally(votes)} end
  end

  step :decide do
    argument :tally, result(:tally)
    run fn %{tally: tally}, _context -> {:ok, decide(tally)} end
  end

  step :apply_lynch do
    argument :decision, result(:decide)
    run fn %{decision: decision}, _context -> apply_lynch(decision) end
  end

  step :reload_game do
    argument :game_id, input(:game_id)
    wait_for :apply_lynch
    run fn %{game_id: game_id}, _context -> Games.get_game(game_id, authorize?: false) end
  end

  compose :resolution, ResolveWin do
    argument :game, result(:reload_game)
  end

  return :resolution

  @doc """
  Groups `:vote` actions by target id into the list of actor ids who voted
  for it. A target nobody voted for is absent, not present with an empty
  list. Any action whose `type` is not `:vote` is ignored.
  """
  @spec tally([Action.t()]) :: tally
  def tally(actions) do
    actions
    |> Enum.filter(&(&1.type == :vote))
    |> Enum.reduce(%{}, fn action, acc ->
      Map.update(acc, action.target_id, [action.actor_id], &[action.actor_id | &1])
    end)
  end

  @doc """
  Decides a lynch from a tally: the sole target holding the strict maximum
  vote count is lynched; a tie for the maximum, or an empty tally, lynches
  nobody.
  """
  @spec decide(tally) :: decision
  def decide(tally) when map_size(tally) == 0, do: :no_lynch

  def decide(tally) do
    {leaders, _max} =
      Enum.reduce(tally, {[], -1}, fn {target_id, voters}, {leaders, max} = acc ->
        count = length(voters)

        cond do
          count > max -> {[target_id], count}
          count == max -> {[target_id | leaders], max}
          true -> acc
        end
      end)

    case leaders do
      [target_id] -> {:lynch, target_id}
      _ -> :no_lynch
    end
  end

  defp apply_lynch({:lynch, target_id}) do
    with {:ok, target} <- Games.get_player(target_id, authorize?: false) do
      Games.update_player(target, %{alive: false}, authorize?: false)
    end
  end

  defp apply_lynch(:no_lynch), do: {:ok, nil}
end
