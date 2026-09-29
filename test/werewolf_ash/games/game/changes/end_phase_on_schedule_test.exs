defmodule WerewolfAsh.Games.Game.Changes.EndPhaseOnScheduleTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.GameClockHelpers
  import WerewolfAsh.Generators

  alias Ash.Error
  alias AshOban.Errors.SnoozeJob
  alias WerewolfAsh.Games

  @day_end ~U[2026-06-15 20:00:00.000000Z]
  @night_end ~U[2026-06-16 08:00:00.000000Z]

  test "at the recorded boundary, advances once, stamping phases with the boundary not the clock" do
    %{game: game} = running_game()

    assert {:ok, night} = run_end_phase(game, @day_end)

    assert night.state == :night
    assert DateTime.compare(night.phase_ends_at, @night_end) == :eq
    assert [%{ended_at: ended}, %{kind: :night, started_at: started}] = phases(game)
    assert DateTime.compare(ended, @day_end) == :eq
    assert DateTime.compare(started, @day_end) == :eq
  end

  test "a second run with the same boundary, and a job left from an earlier phase, are no-ops" do
    %{game: game} = running_game()
    {:ok, _night} = run_end_phase(game, @day_end)

    assert {:ok, _} = run_end_phase(game, @day_end)
    assert length(phases(game)) == 2

    {:ok, day2} = run_end_phase(game, @night_end)
    assert day2.state == :day
    assert length(phases(game)) == 3

    # the first day's job must not end the second day early
    assert {:ok, still_day} = run_end_phase(game, @day_end)
    assert still_day.state == :day
    assert length(phases(game)) == 3
  end

  test "a mismatched boundary, a lobby game and a finished game change nothing" do
    %{game: game} = running_game()
    assert {:ok, _} = run_end_phase(game, DateTime.add(@day_end, 1, :second))
    assert length(phases(game)) == 1

    %{game: finished} = running_game()
    Games.finish_game!(finished, :wolves)
    assert {:ok, %{state: :finished}} = run_end_phase(finished, @day_end)
    assert length(phases(finished)) == 1

    lobby = generate(game())
    assert {:ok, %{state: :lobby}} = run_end_phase(lobby, @day_end)
    assert phases(lobby) == []
  end

  test "snoozes while the hunter's deadline is strictly earlier and unprocessed" do
    %{game: game} = running_game()
    game = open_window(game, DateTime.add(@day_end, -1, :second))

    assert {:error, error} = run_end_phase(game, @day_end)
    assert Enum.any?(Error.to_error_class(error).errors, &match?(%SnoozeJob{}, &1))
    assert length(phases(game)) == 1
  end

  test "a deadline equal to the boundary does not snooze the phase job (tie goes to it)" do
    %{game: game} = running_game()
    game = open_window(game, @day_end)

    assert {:ok, %{state: :night}} = run_end_phase(game, @day_end)
  end

  test "a failing transition rolls back and errors" do
    %{game: game} = running_game()

    Repo.update_all(from(g in "games", where: g.id == type(^game.id, :binary_id)),
      set: [timezone: "Nowhere/Land"]
    )

    assert {:error, _} = run_end_phase(game, @day_end)

    assert [%{ended_at: nil}] = phases(game)
    assert Games.get_game!(game.id, authorize?: false).state == :day
  end
end
