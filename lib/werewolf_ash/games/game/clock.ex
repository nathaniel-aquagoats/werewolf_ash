defmodule WerewolfAsh.Games.Game.Clock do
  @moduledoc """
  Pure wall-clock arithmetic for a game's day/night windows.

  A game's `day_start` and `day_end` are local times of day in its `timezone`.
  Day is the half-open window `[day_start, day_end)`; everything else is night.
  A window may wrap midnight (`day_start` after `day_end`).

  Nothing here reads the system clock: every function takes the instant to
  reason from, so transitions stay testable without a clock.
  """

  @type window :: :day | :night

  @doc """
  Which window the game's local clock is in at `now` (a UTC `DateTime`).
  """
  @spec window_at(map(), DateTime.t()) :: {:ok, window()} | {:error, term()}
  def window_at(%{timezone: timezone, day_start: day_start, day_end: day_end}, %DateTime{} = now) do
    with {:ok, local} <- DateTime.shift_zone(now, timezone) do
      if in_window?(DateTime.to_time(local), day_start, day_end) do
        {:ok, :day}
      else
        {:ok, :night}
      end
    end
  end

  @doc """
  The UTC instant at which a phase of `kind` that is running at `now` ends:
  the next `day_end` for a day, the next `day_start` for a night, in the
  game's timezone. "Next" is strictly after `now`, so a transition made
  exactly on a boundary schedules the following one.

  DST is handled per the IANA rules of the zone. When the boundary's local
  time does not exist that day (spring forward), the phase ends at the first
  instant after the gap; when it happens twice (fall back), the earlier one
  wins.
  """
  @spec next_boundary(map(), window(), DateTime.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def next_boundary(%{timezone: timezone} = game, kind, %DateTime{} = now) do
    boundary =
      case kind do
        :day -> game.day_end
        :night -> game.day_start
      end

    with {:ok, local} <- DateTime.shift_zone(now, timezone) do
      today = DateTime.to_date(local)
      candidate = at(today, boundary, timezone)

      candidate =
        if DateTime.compare(candidate, now) == :gt,
          do: candidate,
          else: at(Date.add(today, 1), boundary, timezone)

      {:ok, DateTime.shift_zone!(candidate, "Etc/UTC")}
    end
  end

  defp at(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
      {:gap, _just_before, just_after} -> just_after
    end
  end

  defp in_window?(time, day_start, day_end) do
    started? = Time.compare(time, day_start) != :lt
    not_over? = Time.compare(time, day_end) == :lt

    case Time.compare(day_start, day_end) do
      :lt -> started? and not_over?
      _ -> started? or not_over?
    end
  end
end
