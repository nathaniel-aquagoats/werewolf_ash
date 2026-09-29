defmodule WerewolfAsh.Games.Action.Changes.ApplyShot do
  @moduledoc """
  The immediate effect of a landed `:shoot` (rules 12-14), once
  `ShootRequiresPendingHunter` and `TargetAlive` have already passed.

  Unlike `ApplyKill`, this never consults bodyguard protection at all: the
  target's `alive` is set `false` unconditionally and the action row is
  stamped `result: %{"killed" => true}`. `WerewolfAsh.Games.Reactors.ResolveWin`
  then runs synchronously (`async?: false`, so it sees this transaction's own
  uncommitted writes) against a freshly loaded `WerewolfAsh.Games.Game`; if a
  side has won, the game finishes right there. Whether or not it does, the
  game's hunter window (`pending_hunter_id`, `hunter_deadline_at`) is cleared
  afterwards, via `WerewolfAsh.Games.Game.HunterWindow.clear/2`, so a second
  `:shoot` is refused by `ShootRequiresPendingHunter` (rule 15) - clearing
  unconditionally is simplest and correct either way: `Game.finish` already
  clears the same two fields on the route that finishes the game (rule 19),
  so clearing them again here is a no-op in that case.

  Registered on `:create`, guarded to `:shoot` only.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow
  alias WerewolfAsh.Games.Reactors.ResolveWin

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn _changeset, action ->
      apply_shot(action, Context.to_opts(context))
    end)
  end

  defp apply_shot(action, opts) do
    with {:ok, target} <- Games.get_player(action.target_id, opts),
         {:ok, _target} <- Games.update_player(target, %{alive: false}, opts),
         {:ok, updated_action} <-
           Games.update_action(action, %{result: %{"killed" => true}}, opts),
         {:ok, phase} <- Games.get_phase(action.phase_id, opts),
         :ok <- run_win_check(phase.game_id, opts),
         :ok <- clear_window(phase.game_id, opts) do
      {:ok, updated_action}
    end
  end

  defp run_win_check(game_id, opts) do
    with {:ok, game} <- Games.get_game(game_id, opts),
         {:ok, _result} <- Reactor.run(ResolveWin, %{game: game}, %{}, async?: false) do
      :ok
    end
  end

  defp clear_window(game_id, opts) do
    with {:ok, game} <- Games.get_game(game_id, opts),
         {:ok, _game} <- HunterWindow.clear(game, opts) do
      :ok
    end
  end
end
