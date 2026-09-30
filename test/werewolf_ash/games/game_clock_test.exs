defmodule WerewolfAsh.Games.GameClockTest do
  @moduledoc """
  werewolf_ash-qss.9 end to end: enqueue on transition, the generated workers,
  cancel on finish, and replay by drain. Times are injected; nothing sleeps.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.GameClockHelpers
  import WerewolfAsh.Generators

  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow
  alias WerewolfAsh.Games.Game.ScheduledJobs
  alias WerewolfAsh.Games.Game.Workers.EndPhase
  alias WerewolfAsh.Games.Game.Workers.HunterDeadline

  @day_end ~U[2026-06-15 20:00:00.000000Z]

  defp jobs(worker), do: all_enqueued(worker: worker)

  describe "enqueue on transition (AdvancePhase, HunterWindow)" do
    test "start, end_day and end_night each leave one job for the phase they open" do
      %{game: game} = running_game()
      assert [job] = jobs(EndPhase)
      assert DateTime.compare(job.scheduled_at, @day_end) == :eq

      night = Games.end_day!(game, %{now: @day_end})
      assert length(jobs(EndPhase)) == 2

      Games.end_night!(night, %{now: night.phase_ends_at})
      assert length(jobs(EndPhase)) == 3
    end

    test "a lobby game leaves no job" do
      game = generate(game())

      Games.update_game_settings!(game, %{min_players: 4},
        actor: Games.get_game!(game.id, load: :owner, authorize?: false).owner
      )

      assert jobs(EndPhase) == []
      assert jobs(HunterDeadline) == []
    end

    test "HunterWindow.open/4 enqueues the deadline job and clear/2 cancels it" do
      %{game: game} = running_game()
      [victim | _] = Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      now = ~U[2026-06-15 14:00:00Z]

      {:ok, opened} = HunterWindow.open(game, victim.id, now, authorize?: false)
      assert [job] = jobs(HunterDeadline)
      assert DateTime.compare(job.scheduled_at, opened.hunter_deadline_at) == :eq

      {:ok, _} = HunterWindow.clear(opened, authorize?: false)
      assert jobs(HunterDeadline) == []
      assert length(jobs(EndPhase)) == 1
    end
  end

  describe "finish" do
    test "cancels that game's pending jobs, not another game's" do
      %{game: game} = running_game()
      %{game: other} = running_game()
      open_window(game, ~U[2026-06-15 15:00:00.000000Z])
      ScheduledJobs.schedule_hunter_deadline(Games.get_game!(game.id, authorize?: false))

      Games.finish_game!(Games.get_game!(game.id, authorize?: false), :wolves)

      assert [%{args: %{"primary_key" => %{"id" => id}}}] = jobs(EndPhase)
      assert id == other.id
      assert jobs(HunterDeadline) == []
    end
  end

  describe "workers" do
    test "a job for a game the caller has no seat in advances it (AshObanInteraction bypass)" do
      %{game: game} = running_game()
      [job] = jobs(EndPhase)

      assert {:ok, _} = perform_job(EndPhase, job.args)

      assert Games.get_game!(game.id, authorize?: false).state == :night
    end

    test "a job for a finished game is cancelled as no longer applying" do
      %{game: game} = running_game()
      [job] = jobs(EndPhase)
      Games.finish_game!(game, :wolves)

      assert {:cancel, _} = perform_job(EndPhase, job.args)
    end

    test "a hunter job whose phase boundary is earlier snoozes 30s" do
      %{game: game} = running_game()
      game = open_window(game, game.phase_ends_at)
      {:ok, _} = ScheduledJobs.schedule_hunter_deadline(game)
      [job] = jobs(HunterDeadline)

      assert {:snooze, 30} = perform_job(HunterDeadline, job.args)
    end

    test "a phase job later than the hunter's deadline snoozes, then proceeds once the hunter job ran" do
      %{game: game} = running_game()
      game = open_window(game, ~U[2026-06-15 15:00:00.000000Z])
      {:ok, _} = ScheduledJobs.schedule_hunter_deadline(game)
      [phase_job] = jobs(EndPhase)
      [hunter_job] = jobs(HunterDeadline)

      assert {:snooze, 30} = perform_job(EndPhase, phase_job.args)

      assert {:ok, _} = perform_job(HunterDeadline, hunter_job.args)
      # the random fallback shot may itself end the game, so only the snooze is asserted
      result = perform_job(EndPhase, phase_job.args)
      assert match?({:ok, _}, result) or match?({:cancel, :trigger_no_longer_applies}, result)
    end
  end

  describe "hunter job and dusk win" do
    test "a hunter job for a game whose window was cleared is cancelled as no longer applying" do
      %{game: game} = running_game()
      game = open_window(game, ~U[2026-06-15 15:00:00.000000Z])
      {:ok, _} = ScheduledJobs.schedule_hunter_deadline(game)
      [job] = jobs(HunterDeadline)
      {:ok, _} = HunterWindow.clear(game, authorize?: false)

      assert {:cancel, :trigger_no_longer_applies} = perform_job(HunterDeadline, job.args)
    end

    test "a win at dusk leaves no pending job" do
      %{game: game} = running_game()

      game.id
      |> Games.list_living_players!(authorize?: false)
      |> Enum.filter(&(&1.role == :werewolf))
      |> Enum.each(&Games.update_player!(&1, %{alive: false}, authorize?: false))

      finished = Games.end_day!(game, %{now: @day_end})

      assert finished.state == :finished
      assert jobs(EndPhase) == []
      assert jobs(HunterDeadline) == []
    end
  end

  describe "replay by drain" do
    test "missed phases are replayed in order at their recorded boundaries; the next one stays scheduled" do
      %{game: game} = running_game()
      cutoff = ~U[2026-06-18 00:00:00Z]

      Oban.drain_queue(queue: :game_clock, with_scheduled: cutoff, with_recursion: true)

      phases = phases(game)
      assert Enum.map(phases, & &1.kind) == [:day, :night, :day, :night, :day, :night]
      assert Enum.map(phases, & &1.number) == [1, 2, 3, 4, 5, 6]

      boundaries = [
        ~U[2026-06-15 09:00:00Z],
        ~U[2026-06-15 20:00:00Z],
        ~U[2026-06-16 08:00:00Z],
        ~U[2026-06-16 20:00:00Z],
        ~U[2026-06-17 08:00:00Z],
        ~U[2026-06-17 20:00:00Z]
      ]

      for {phase, at} <- Enum.zip(phases, boundaries) do
        assert DateTime.compare(phase.started_at, at) == :eq
      end

      assert [pending] = jobs(EndPhase)
      assert DateTime.compare(pending.scheduled_at, ~U[2026-06-18 08:00:00Z]) == :eq
    end

    test "an unused hunter window is closed by the fallback shot when its job drains" do
      %{game: game} = running_game()
      game = open_window(game, ~U[2026-06-15 15:00:00.000000Z])
      {:ok, _} = ScheduledJobs.schedule_hunter_deadline(game)

      Oban.drain_queue(
        queue: :game_clock,
        with_scheduled: ~U[2026-06-15 21:00:00Z],
        with_recursion: true
      )

      after_drain = Games.get_game!(game.id, authorize?: false)
      assert is_nil(after_drain.pending_hunter_id)

      assert [%{result: %{"fallback" => true}}] =
               Games.list_actions!(query: [filter: [type: :shoot]], authorize?: false)
    end
  end
end
