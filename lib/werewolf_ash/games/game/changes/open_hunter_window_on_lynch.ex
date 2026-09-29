defmodule WerewolfAsh.Games.Game.Changes.OpenHunterWindowOnLynch do
  @moduledoc """
  Opens the hunter's one-hour window the moment a lynch itself kills the
  game's dealt hunter (rules 3-5), registered after `ResolveDayVote` in
  `:end_day`'s own change list. Ash runs a changeset's `after_action` hooks
  in the order they were registered, so this one's own hook necessarily runs
  once `ResolveDayVote`'s has already resolved the lynch and the dusk win
  check.

  `change/3` captures the game's dealt hunter (if any) and their pre-lynch
  `alive` before `ResolveDayVote`'s own hook runs the lynch. The window then
  opens, deadline `end_day`'s own `now` argument plus one hour, only when:
  a hunter was dealt; they were alive before this `end_day` and are dead
  once it has run (so this lynch, not some earlier event, is what killed
  them - a hunter already dead going in is left alone, rule 5's "no window"
  case for a lynch that never touched the hunter at all); and the game is
  still `:day`/`:night` after the win check (rule 9) - a lynch that finishes
  the game (rule 4) opens none.

  `:end_day` is called by the scheduler with no real actor, exactly like
  `ResolveLynch`'s own internal reads and writes - every `Player`/`Game`
  touch here is `authorize?: false`, a game rule rather than a request made
  on any particular player's behalf.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow

  @impl true
  def change(changeset, _opts, _context) do
    now = Changeset.get_argument(changeset, :now)
    hunter = dealt_hunter(changeset.data.id)

    Changeset.after_action(changeset, fn _changeset, game ->
      maybe_open(hunter, now, game)
    end)
  end

  defp dealt_hunter(game_id) do
    case Games.list_players(
           query: [filter: [game_id: game_id, role: :hunter]],
           authorize?: false
         ) do
      {:ok, [hunter]} -> hunter
      _ -> nil
    end
  end

  # rule 5 - no hunter dealt at all: nothing to open a window for.
  defp maybe_open(nil, _now, game), do: {:ok, game}

  # rule 5 - the hunter was already dead before this end_day; this lynch
  # cannot be what killed them (a dead player cannot be lynched), so any
  # window their earlier death may have opened is left exactly as it is.
  defp maybe_open(%{alive: false}, _now, game), do: {:ok, game}

  # rule 4, 9 - the win check already finished the game: no window opens.
  defp maybe_open(_hunter, _now, %{state: state} = game)
       when state not in [:day, :night],
       do: {:ok, game}

  defp maybe_open(hunter, now, game) do
    case Games.get_player(hunter.id, authorize?: false) do
      # rule 3 - this lynch is what killed the hunter: open the window.
      {:ok, %{alive: false}} -> HunterWindow.open(game, hunter.id, now, authorize?: false)
      # rule 5 - the lynch, if any, landed on someone else: no window.
      _ -> {:ok, game}
    end
  end
end
