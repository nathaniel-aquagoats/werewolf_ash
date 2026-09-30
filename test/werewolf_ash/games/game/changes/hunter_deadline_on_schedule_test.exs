defmodule WerewolfAsh.Games.Game.Changes.HunterDeadlineOnScheduleTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.GameClockHelpers
  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Error
  alias Ash.UUID
  alias AshOban.Errors.SnoozeJob
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow

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

  test "snoozes when the phase boundary is strictly earlier than the deadline" do
    %{game: game} = running_game()
    deadline = DateTime.add(game.phase_ends_at, 3600, :second)
    game = open_window(game, deadline)

    assert {:error, error} = run_hunter_deadline(game, deadline)
    assert Enum.any?(Error.to_error_class(error).errors, &match?(%SnoozeJob{}, &1))
    assert shots() == []
  end

  test "uses the recorded deadline as now, not the wall clock (a future deadline still shoots)" do
    %{game: game} = running_game()
    deadline = ~U[2099-01-01 00:00:00.000000Z]

    game =
      game
      |> Changeset.for_update(:update, %{})
      |> Changeset.force_change_attribute(:phase_ends_at, ~U[2100-01-01 00:00:00.000000Z])
      |> Ash.update!()
      |> open_window(deadline)

    assert {:ok, resolved} = run_hunter_deadline(game, deadline)

    assert is_nil(resolved.pending_hunter_id)
    assert [%{result: %{"fallback" => true}}] = shots()
  end

  test "a lobby game with an open window is a no-op (the state guard, rule 12)" do
    lobby = generate(game())
    {:ok, opened} = HunterWindow.open(lobby, UUID.generate(), @deadline, authorize?: false)

    assert {:ok, %{state: :lobby}} = run_hunter_deadline(opened, opened.hunter_deadline_at)
    assert shots() == []
  end

  test "a failing shot rolls back and errors, leaving the window open (rule 13)" do
    %{game: game} = running_game()
    game = open_window(game, @deadline)

    Repo.update_all(from(p in "players", where: p.game_id == type(^game.id, :binary_id)),
      set: [alive: false]
    )

    assert {:error, _} = run_hunter_deadline(game, @deadline)
    assert %{pending_hunter_id: id} = Games.get_game!(game.id, authorize?: false)
    assert id == game.pending_hunter_id
  end
end
