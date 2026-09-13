defmodule WerewolfAsh.Games.Game.Changes.ResolveDayVote do
  @moduledoc """
  Resolves the day just closed by `:end_day`, once `AdvancePhase`'s own hook
  has already transitioned the game to `:night` and opened the night phase.

  Runs `WerewolfAsh.Games.Reactors.ResolveLynch` synchronously
  (`async?: false`) against the day phase that was open on the game at the
  moment `end_day` was called — captured here, in `change/3`'s own body,
  before `AdvancePhase`'s change runs and closes it. If the reactor's win
  check decides the game is over, this hook destroys the night `Phase` row
  `AdvancePhase` just opened, so no night phase is left in the game's
  history for a game that ended at dusk; otherwise the game is left exactly
  as `AdvancePhase` set it up.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.ResolveLynch

  @impl true
  def change(changeset, _opts, context) do
    phase_id = current_day_phase_id(changeset.data, context)
    game_id = changeset.data.id

    Changeset.after_action(changeset, fn _changeset, _game ->
      resolve(phase_id, game_id, Context.to_opts(context))
    end)
  end

  defp current_day_phase_id(game, context) do
    case Ash.load!(game, :current_phase, Context.to_opts(context)) do
      %{current_phase: nil} -> nil
      %{current_phase: phase} -> phase.id
    end
  end

  defp resolve(phase_id, game_id, opts) do
    with {:ok, %{outcome: outcome, game: resolved_game}} <-
           Reactor.run(ResolveLynch, %{phase_id: phase_id, game_id: game_id}, %{}, async?: false),
         :ok <- maybe_destroy_night_phase(outcome, resolved_game, opts) do
      {:ok, resolved_game}
    end
  end

  defp maybe_destroy_night_phase(outcome, game, opts)
       when outcome in [:village_wins, :wolves_wins] do
    with {:ok, %{current_phase: phase}} <- Ash.load(game, [:current_phase], opts) do
      destroy_phase(phase, opts)
    end
  end

  defp maybe_destroy_night_phase(_outcome, _game, _opts), do: :ok

  defp destroy_phase(nil, _opts), do: :ok
  defp destroy_phase(phase, opts), do: Games.destroy_phase(phase, opts)
end
