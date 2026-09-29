defmodule WerewolfAsh.Games.Game.Changes.CancelScheduledJobs do
  @moduledoc """
  On `:finish`, cancels the game's pending phase and hunter jobs in the same
  transaction (werewolf_ash-qss.9 rule 22).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game.ScheduledJobs

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn _changeset, game ->
      ScheduledJobs.cancel_phase_jobs(game)
      ScheduledJobs.cancel_hunter_jobs(game)
      {:ok, game}
    end)
  end
end
