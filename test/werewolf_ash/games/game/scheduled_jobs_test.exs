defmodule WerewolfAsh.Games.Game.ScheduledJobsTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game.ScheduledJobs
  alias WerewolfAsh.Games.Game.Workers.EndPhase
  alias WerewolfAsh.Games.Game.Workers.HunterDeadline

  @ends_at ~U[2026-06-15 20:00:00.000000Z]

  defp timed_game(attrs \\ []) do
    generate(game())
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:phase_ends_at, attrs[:phase_ends_at] || @ends_at)
    |> Changeset.force_change_attribute(:hunter_deadline_at, attrs[:hunter_deadline_at])
    |> Ash.update!()
  end

  defp jobs(worker), do: all_enqueued(worker: worker)

  describe "schedule_phase_end/1" do
    test "enqueues one :end_phase job on :game_clock at phase_ends_at with an ISO8601 `at`" do
      game = timed_game()

      assert {:ok, _job} = ScheduledJobs.schedule_phase_end(game)

      assert [job] = jobs(EndPhase)
      assert job.queue == "game_clock"
      assert DateTime.compare(job.scheduled_at, @ends_at) == :eq
      assert job.args["action_arguments"]["at"] == DateTime.to_iso8601(@ends_at)
    end

    test "the same boundary twice leaves one job; a different boundary gives a second" do
      game = timed_game()
      ScheduledJobs.schedule_phase_end(game)
      ScheduledJobs.schedule_phase_end(game)
      assert length(jobs(EndPhase)) == 1

      later = %{game | phase_ends_at: DateTime.add(@ends_at, 12, :hour)}
      ScheduledJobs.schedule_phase_end(later)
      assert length(jobs(EndPhase)) == 2
    end
  end

  describe "schedule_hunter_deadline/1" do
    test "enqueues one :hunter_deadline job at hunter_deadline_at" do
      deadline = ~U[2026-06-15 21:00:00.000000Z]
      game = timed_game(hunter_deadline_at: deadline)

      assert {:ok, _job} = ScheduledJobs.schedule_hunter_deadline(game)

      assert [job] = jobs(HunterDeadline)
      assert DateTime.compare(job.scheduled_at, deadline) == :eq
      assert jobs(EndPhase) == []
    end
  end

  describe "cancel_phase_jobs/1 and cancel_hunter_jobs/1" do
    test "cancel only that game's pending jobs of their kind" do
      game = timed_game(hunter_deadline_at: ~U[2026-06-15 21:00:00.000000Z])
      other = timed_game(hunter_deadline_at: ~U[2026-06-15 21:00:00.000000Z])

      for g <- [game, other] do
        ScheduledJobs.schedule_phase_end(g)
        ScheduledJobs.schedule_hunter_deadline(g)
      end

      assert :ok = ScheduledJobs.cancel_phase_jobs(game)
      assert [%{args: %{"primary_key" => %{"id" => id}}}] = jobs(EndPhase)
      assert id == other.id
      assert length(jobs(HunterDeadline)) == 2

      assert :ok = ScheduledJobs.cancel_hunter_jobs(game)
      assert [%{args: %{"primary_key" => %{"id" => ^id}}}] = jobs(HunterDeadline)
    end

    test "an executing job is not cancelled, and cancelling with none pending succeeds" do
      game = timed_game()
      {:ok, job} = ScheduledJobs.schedule_phase_end(game)
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "executing"])

      assert :ok = ScheduledJobs.cancel_phase_jobs(game)
      assert Repo.get!(Oban.Job, job.id).state == "executing"

      assert :ok = ScheduledJobs.cancel_hunter_jobs(game)
    end
  end

  describe "backoff/1 and the generated workers" do
    test "backoff is 30, 60, 300 then 600 forever" do
      assert Enum.map([1, 2, 3, 4, 5, 1_000_000], &ScheduledJobs.backoff(%{attempt: &1})) ==
               [30, 60, 300, 600, 600, 600]

      assert EndPhase.backoff(%{attempt: 2}) == 60
      assert HunterDeadline.backoff(%{attempt: 4}) == 600
    end

    test "both workers allow effectively unlimited attempts" do
      assert EndPhase.new(%{}).changes.max_attempts == 1_000_000
      assert HunterDeadline.new(%{}).changes.max_attempts == 1_000_000
    end
  end
end
