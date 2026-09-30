defmodule WerewolfAsh.Games.Game.ScheduledJobs do
  @moduledoc """
  Enqueue and cancel helpers for the game clock (werewolf_ash-qss.9).

  A phase end and a hunter deadline are each one exact-time Oban job on
  `:game_clock`, made by `AshOban.run_trigger/3` inside the transaction that
  opens the phase or window, so it commits or rolls back with it. There is no
  cron and no sweeper. The `at` action argument is an ISO8601 string so that
  Oban's args uniqueness compares plain JSON values.
  """

  import Ecto.Query

  alias Oban.Worker
  alias WerewolfAsh.Games.Game.Workers.EndPhase
  alias WerewolfAsh.Games.Game.Workers.HunterDeadline

  @pending_states ["available", "scheduled", "retryable"]

  @doc "Enqueues the `:end_phase` job for `game.phase_ends_at` (nothing when it is unset)."
  def schedule_phase_end(%{phase_ends_at: nil}), do: {:ok, nil}
  def schedule_phase_end(game), do: schedule(game, :end_phase, game.phase_ends_at)

  @doc "Enqueues the `:hunter_deadline` job for `game.hunter_deadline_at`."
  def schedule_hunter_deadline(game),
    do: schedule(game, :hunter_deadline, game.hunter_deadline_at)

  @doc "Cancels the game's not-yet-started `:end_phase` jobs."
  def cancel_phase_jobs(game), do: cancel(game, EndPhase)

  @doc "Cancels the game's not-yet-started `:hunter_deadline` jobs."
  def cancel_hunter_jobs(game), do: cancel(game, HunterDeadline)

  @doc """
  Retry wait in seconds after failed attempt `job.attempt` (1 is the first
  failure): 30, 60, 300, then 600 for every later one.
  """
  def backoff(%{attempt: 1}), do: 30
  def backoff(%{attempt: 2}), do: 60
  def backoff(%{attempt: 3}), do: 300
  def backoff(_job), do: 600

  defp schedule(game, trigger, at) do
    {:ok,
     AshOban.run_trigger(game, trigger,
       scheduled_at: at,
       action_arguments: %{at: DateTime.to_iso8601(at)}
     )}
  rescue
    error -> {:error, error}
  end

  # Executing jobs are left alone: the running one completes normally.
  defp cancel(game, worker) do
    id = game.id
    name = Worker.to_string(worker)

    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where:
          j.worker == ^name and j.state in ^@pending_states and
            fragment("?->'primary_key'->>'id'", j.args) == ^id
      )
    )

    :ok
  end
end
