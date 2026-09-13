defmodule WerewolfAsh.Games.Game.Changes.ResolveNightWin do
  @moduledoc """
  Dawn's own win check (werewolf_ash-qss.6 rules 9-11), appended after
  `{AdvancePhase, to: :day}` in `:end_night`'s own `change` list — the same
  chaining precedent `:start` already uses for `DealRoles` then
  `AdvancePhase`, each registering its own `after_action` hook.

  This is not resolving any kill: `end_night` re-resolves nothing about the
  night that just closed (`ApplyKill`/`ResolveKillWin` already settled that,
  if a kill landed at all). It exists for a case those cannot reach: a game
  can arrive at a night already at wolf parity without any kill ever having
  run — `start` deals roles and opens the first phase but composes no win
  check of its own.

  Runs `WerewolfAsh.Games.Reactors.ResolveWin` synchronously (`async?: false`)
  against the day-transitioned game `AdvancePhase`'s own hook already
  produced. When it decides a winner, the day `Phase` `AdvancePhase` just
  opened is destroyed — not merely closed, since no day is left for a game
  finished at dawn — mirroring `WerewolfAsh.Games.Game.Changes.ResolveDayVote`'s
  own handling of the symmetric dusk case. Otherwise the game and its phases
  are left exactly as `AdvancePhase` set them up.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.ResolveWin

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn _changeset, game ->
      resolve(game, Context.to_opts(context))
    end)
  end

  defp resolve(game, opts) do
    with {:ok, %{outcome: outcome, game: resolved_game}} <-
           Reactor.run(ResolveWin, %{game: game}, %{}, async?: false),
         :ok <- maybe_destroy_day_phase(outcome, resolved_game, opts) do
      {:ok, resolved_game}
    end
  end

  defp maybe_destroy_day_phase(outcome, game, opts)
       when outcome in [:village_wins, :wolves_wins] do
    with {:ok, %{current_phase: phase}} <- Ash.load(game, [:current_phase], opts) do
      destroy_phase(phase, opts)
    end
  end

  defp maybe_destroy_day_phase(_outcome, _game, _opts), do: :ok

  defp destroy_phase(nil, _opts), do: :ok
  defp destroy_phase(phase, opts), do: Games.destroy_phase(phase, opts)
end
