defmodule WerewolfAsh.Games.Game.Changes.HunterDeadlineOnScheduleTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.GameClockHelpers
  import WerewolfAsh.Generators

  alias Ash.Error
  alias AshOban.Errors.SnoozeJob
  alias WerewolfAsh.Games

  @deadline ~U[2026-06-15 15:00:00.000000Z]

  defp living(game),
    do: Games.list_living_players!(game.id, authorize?: false) |> length()

  defp shots, do: Games.list_actions!(query: [filter: [type: :shoot]], authorize?: false)

  test "at the deadline, shoots one living player as a fallback and clears the window" do
    %{game: game} = running_game()
    game = open_window(game, @deadline)
    before = living(game)

    assert {:ok, resolved} = run_hunter_deadline(game, @deadline)

    assert is_nil(resolved.pending_hunter_id)
    assert living(game) == before - 1
    assert [%{result: %{"fallback" => true}}] = shots()
  end

  test "a stale boundary, no open window, a lobby game and a finished game change nothing" do
    %{game: game} = running_game()
    open = open_window(game, @deadline)
    assert {:ok, _} = run_hunter_deadline(open, DateTime.add(@deadline, 1, :second))
    assert shots() == []

    %{game: none} = running_game()
    assert {:ok, _} = run_hunter_deadline(none, @deadline)

    %{game: over} = running_game()
    over = open_window(over, @deadline)
    Games.finish_game!(over, :wolves)
    assert {:ok, %{state: :finished}} = run_hunter_deadline(over, @deadline)

    lobby = generate(game())
    assert {:ok, %{state: :lobby}} = run_hunter_deadline(lobby, @deadline)
    assert shots() == []
  end

  test "snoozes while a phase boundary at or before the deadline is unprocessed" do
    %{game: game} = running_game()
    ends_at = game.phase_ends_at

    # window deadline equal to the phase boundary: the tie goes to the phase job
    game = open_window(game, ends_at)

    assert {:error, error} = run_hunter_deadline(game, ends_at)
    assert Enum.any?(Error.to_error_class(error).errors, &match?(%SnoozeJob{}, &1))
    assert shots() == []
  end
end
