defmodule WerewolfAsh.Games.Game.Changes.EndPhaseOnSchedule do
  @moduledoc """
  The body of `:end_phase_on_schedule` (werewolf_ash-qss.9 rules 9, 10, 20).

  Re-reads the game with `FOR UPDATE` inside the action's own transaction,
  then acts only if it is a running day or night whose `phase_ends_at` is
  exactly `at`; anything else is a silent no-op. A hunter deadline that is
  strictly earlier and still open snoozes the job instead. Otherwise runs
  `end_day`/`end_night` with `now` = `at`, never the wall clock.
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

  defp run(%{state: state, phase_ends_at: ends_at} = game, at)
       when state in [:day, :night] and not is_nil(ends_at) do
    cond do
      DateTime.compare(ends_at, at) != :eq -> {:ok, game}
      hunter_first?(game, at) -> {:error, SnoozeJob.exception(snooze_for: 30)}
      state == :day -> Games.end_day(game, %{now: at}, authorize?: false)
      true -> Games.end_night(game, %{now: at}, authorize?: false)
    end
  end

  defp run(game, _at), do: {:ok, game}

  defp hunter_first?(%{pending_hunter_id: nil}, _at), do: false

  defp hunter_first?(%{hunter_deadline_at: deadline}, at),
    do: DateTime.compare(deadline, at) == :lt
end
