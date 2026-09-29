defmodule WerewolfAsh.Games.Game.Changes.HunterDeadlineOnSchedule do
  @moduledoc """
  The body of `:hunter_deadline_on_schedule` (werewolf_ash-qss.9 rules 11, 12).

  Re-reads the game with `FOR UPDATE` inside the action's own transaction and
  acts only on a running game with an open window whose deadline is exactly
  `at`; anything else is a silent no-op. A phase boundary that is at or before
  `at` and still unprocessed snoozes the job. Otherwise runs
  `resolve_hunter_deadline` with `now` = `at` (never `pick`).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshOban.Errors.SnoozeJob
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game

  @impl true
  def change(changeset, _opts, _context) do
    at = Changeset.get_argument(changeset, :at)

    Changeset.after_action(changeset, fn _changeset, game ->
      Game |> Ash.get!(game.id, authorize?: false, lock: :for_update) |> run(at)
    end)
  end

  defp run(%{state: state, pending_hunter_id: id, hunter_deadline_at: deadline} = game, at)
       when state in [:day, :night] and not is_nil(id) do
    cond do
      DateTime.compare(deadline, at) != :eq ->
        {:ok, game}

      DateTime.compare(game.phase_ends_at, at) != :gt ->
        {:error, SnoozeJob.exception(snooze_for: 30)}

      true ->
        Games.resolve_hunter_deadline(game, %{now: at}, authorize?: false)
    end
  end

  defp run(game, _at), do: {:ok, game}
end
