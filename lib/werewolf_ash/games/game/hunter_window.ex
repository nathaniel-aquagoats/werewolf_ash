defmodule WerewolfAsh.Games.Game.HunterWindow do
  @moduledoc """
  Shared plumbing for opening and clearing the hunter's one-hour window
  (`Game.pending_hunter_id`, `Game.hunter_deadline_at`), reused by the
  lynch (rule 3) and dawn (rule 7) window-opening changes, and by the
  change that applies a landed shot (rule 14).

  Both fields are written only with `Ash.Changeset.force_change_attribute/3`
  (rule 1): the `Game` `:update` action's own `accept` list never includes
  them, so this is the one path by which they change.

  `open/4` also enqueues the window's one `:hunter_deadline` job and `clear/2`
  cancels it (werewolf_ash-qss.9).
  """

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game.ScheduledJobs

  @window_seconds 3600

  @doc "Opens the window: `hunter_id` becomes the pointer, the deadline is `now` plus one hour."
  def open(game, hunter_id, now, opts) do
    game
    |> Changeset.for_update(:update, %{}, opts)
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(
      :hunter_deadline_at,
      DateTime.add(now, @window_seconds, :second)
    )
    |> Ash.update(opts)
    |> schedule()
  end

  defp schedule({:ok, game}) do
    with {:ok, _job} <- ScheduledJobs.schedule_hunter_deadline(game), do: {:ok, game}
  end

  defp schedule(error), do: error

  @doc "Clears the window: both fields become nil."
  def clear(game, opts) do
    game
    |> Changeset.for_update(:update, %{}, opts)
    |> Changeset.force_change_attribute(:pending_hunter_id, nil)
    |> Changeset.force_change_attribute(:hunter_deadline_at, nil)
    |> Ash.update(opts)
    |> cancel()
  end

  # werewolf_ash-qss.9 rule 23 - a shot makes the pending deadline job stale.
  defp cancel({:ok, game}) do
    ScheduledJobs.cancel_hunter_jobs(game)
    {:ok, game}
  end

  defp cancel(error), do: error
end
