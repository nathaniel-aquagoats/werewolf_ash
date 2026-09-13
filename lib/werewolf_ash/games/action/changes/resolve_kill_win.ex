defmodule WerewolfAsh.Games.Action.Changes.ResolveKillWin do
  @moduledoc """
  The immediate win check that follows a landed `:kill` (werewolf_ash-qss.6
  rules 1, 3, 4), once `ApplyKill`'s own `after_action` hook has already run.

  A landed kill (`result: %{"killed" => true}`) is followed at once by
  `WerewolfAsh.Games.Reactors.ResolveWin`, composed synchronously
  (`async?: false`, so it can see this transaction's own uncommitted writes)
  against a freshly loaded `WerewolfAsh.Games.Game` for the kill's own game —
  never the possibly-stale struct any earlier hook already held. If that
  check decides a winner, the game finishes mid-night, right there. A spent
  (protected) kill (`result: %{"killed" => false}`) runs no win check at all:
  the game is left exactly as it was.

  This is deliberately a separate `change` from `ApplyKill`, registering its
  own `after_action` hook rather than folding into `ApplyKill.change/3` — see
  werewolf_ash-qss.6's spec for why that boundary matters.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Reactors.ResolveWin

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn _changeset, action ->
      resolve(action, Context.to_opts(context))
    end)
  end

  defp resolve(%{result: %{"killed" => true}} = action, opts) do
    with {:ok, phase} <- Games.get_phase(action.phase_id, opts),
         {:ok, game} <- Games.get_game(phase.game_id, opts),
         {:ok, _result} <- Reactor.run(ResolveWin, %{game: game}, %{}, async?: false) do
      {:ok, action}
    end
  end

  defp resolve(action, _opts), do: {:ok, action}
end
