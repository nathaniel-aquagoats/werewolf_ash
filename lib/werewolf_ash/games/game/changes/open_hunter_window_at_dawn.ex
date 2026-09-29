defmodule WerewolfAsh.Games.Game.Changes.OpenHunterWindowAtDawn do
  @moduledoc """
  Opens the hunter's one-hour window at dawn (rules 7-9) when the wolves'
  kill, not a lynch, is what killed the game's dealt hunter: registered
  after `ResolveNightWin` in `:end_night`'s own change list, so its own
  `after_action` hook (hooks run in registration order) sees the dawn win
  check's own verdict.

  Opens the window, deadline `end_night`'s own `now` argument plus one hour,
  only when, once the dawn win check has run: the game is still `:day`; the
  game's dealt hunter is dead; that hunter holds no `:shoot` `Action` row at
  all, in any phase (a spent window, chosen or fallback, always leaves one -
  this is how the change tells "the hunter died and was already shot" apart
  from "the hunter died and never got a window"); and the game has no
  window open already (rule 9's pointer is non-nil exactly while one is, so
  a dusk window not yet spent is left alone rather than reopened). A game
  with no hunter dealt, or whose hunter is still alive, opens none either
  (rule 8).

  `:end_night` is called by the scheduler with no real actor, exactly like
  `ResolveNightWin`'s own composed reactors - every `Player`/`Action` touch
  here is `authorize?: false`, a game rule rather than a request made on any
  particular player's behalf.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow

  @impl true
  def change(changeset, _opts, _context) do
    now = Changeset.get_argument(changeset, :now)

    Changeset.after_action(changeset, fn _changeset, game ->
      maybe_open(game, now)
    end)
  end

  defp maybe_open(%{state: :day, pending_hunter_id: nil} = game, now) do
    with hunter when not is_nil(hunter) <- dealt_hunter(game.id),
         %{alive: false} <- hunter,
         [] <- shoot_rows(hunter.id) do
      HunterWindow.open(game, hunter.id, now, authorize?: false)
    else
      _ -> {:ok, game}
    end
  end

  # rule 8 - the dawn win check already finished the game, or a window is
  # already open (a dusk window not yet spent): no window opens here.
  defp maybe_open(game, _now), do: {:ok, game}

  defp dealt_hunter(game_id) do
    case Games.list_players(
           query: [filter: [game_id: game_id, role: :hunter]],
           authorize?: false
         ) do
      {:ok, [hunter]} -> hunter
      _ -> nil
    end
  end

  defp shoot_rows(hunter_id) do
    Games.list_actions!(query: [filter: [actor_id: hunter_id, type: :shoot]], authorize?: false)
  end
end
