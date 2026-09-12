defmodule WerewolfAsh.Games.Game.ClockTest do
  use ExUnit.Case, async: true

  alias WerewolfAsh.Games.Game.Clock

  # Clock only pattern-matches on `timezone`, `day_start` and `day_end`, so a
  # bare map stands in for a `Game` here — no Ash, no database.
  defp game(attrs) do
    Map.merge(%{timezone: "Etc/UTC", day_start: ~T[08:00:00], day_end: ~T[20:00:00]}, attrs)
  end

  describe "window_at/2" do
    test "reports day inside the window and night outside it" do
      game = game(%{})

      assert Clock.window_at(game, ~U[2026-01-01 10:00:00Z]) == {:ok, :day}
      assert Clock.window_at(game, ~U[2026-01-01 22:00:00Z]) == {:ok, :night}
    end

    test "day_start is inclusive, day_end is exclusive" do
      game = game(%{})

      assert Clock.window_at(game, ~U[2026-01-01 08:00:00Z]) == {:ok, :day}
      assert Clock.window_at(game, ~U[2026-01-01 20:00:00Z]) == {:ok, :night}
    end

    test "a midnight-wrapping window treats the small hours as day" do
      game = game(%{day_start: ~T[22:00:00], day_end: ~T[06:00:00]})

      assert Clock.window_at(game, ~U[2026-01-01 23:00:00Z]) == {:ok, :day}
      assert Clock.window_at(game, ~U[2026-01-01 03:00:00Z]) == {:ok, :day}
      assert Clock.window_at(game, ~U[2026-01-01 12:00:00Z]) == {:ok, :night}
    end

    test "an unknown time zone is an error" do
      game = game(%{timezone: "Not/AZone"})

      assert {:error, _reason} = Clock.window_at(game, ~U[2026-01-01 12:00:00Z])
    end
  end

  describe "next_boundary/3" do
    test "the next day_end for a day already in progress" do
      game = game(%{})

      assert Clock.next_boundary(game, :day, ~U[2026-01-01 10:00:00Z]) ==
               {:ok, ~U[2026-01-01 20:00:00Z]}
    end

    test "a midnight-wrapping window rolls the boundary onto the next date" do
      game = game(%{day_start: ~T[22:00:00], day_end: ~T[06:00:00]})

      # 23:30 is inside the (wrapping) day window; day_end (06:00) already
      # passed earlier that calendar date, so the next one is tomorrow's.
      assert Clock.next_boundary(game, :day, ~U[2026-01-01 23:30:00Z]) ==
               {:ok, ~U[2026-01-02 06:00:00Z]}

      # 12:00 is inside the night window; day_start (22:00) has not happened
      # yet today, so it stays on the same date.
      assert Clock.next_boundary(game, :night, ~U[2026-01-01 12:00:00Z]) ==
               {:ok, ~U[2026-01-01 22:00:00Z]}
    end

    test "a boundary exactly at now rolls to the following day" do
      game = game(%{})

      assert Clock.next_boundary(game, :day, ~U[2026-01-01 20:00:00Z]) ==
               {:ok, ~U[2026-01-02 20:00:00Z]}
    end

    test "a DST gap resolves to the first instant after it" do
      # New York springs forward at 02:00 EST -> 03:00 EDT on 2026-03-08, so
      # 02:30 does not exist that day.
      game = game(%{timezone: "America/New_York", day_start: ~T[02:30:00], day_end: ~T[14:00:00]})

      assert Clock.next_boundary(game, :night, ~U[2026-03-08 00:00:00Z]) ==
               {:ok, ~U[2026-03-08 07:00:00Z]}
    end

    test "a DST fold resolves to the earlier occurrence" do
      # New York falls back at 02:00 EDT on 2026-11-01, so 01:30 happens twice.
      game = game(%{timezone: "America/New_York", day_start: ~T[01:30:00], day_end: ~T[14:00:00]})

      assert Clock.next_boundary(game, :night, ~U[2026-11-01 00:00:00Z]) ==
               {:ok, ~U[2026-11-01 05:30:00Z]}
    end

    test "an unknown time zone is an error" do
      game = game(%{timezone: "Not/AZone"})

      assert {:error, _reason} = Clock.next_boundary(game, :day, ~U[2026-01-01 12:00:00Z])
    end
  end
end
