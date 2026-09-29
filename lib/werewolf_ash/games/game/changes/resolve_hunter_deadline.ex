defmodule WerewolfAsh.Games.Game.Changes.ResolveHunterDeadline do
  @moduledoc """
  `resolve_hunter_deadline`'s own change (rules 16-18).

  Once a window is open and `now` is at or past `hunter_deadline_at`, shoots
  one living player of the game - drawn from `Games.list_living_players/1`
  (`Player :living_in_game`), ordered by id; with the `pick` argument given,
  the target is that list at index `pick` modulo its length, otherwise the
  index is drawn uniformly at random. The shot is created through the same
  `:create` path a chosen `:shoot` uses, so
  `WerewolfAsh.Games.Action.Changes.ApplyShot`'s own rules 12-14 apply
  unchanged (the kill, the win check, the cleared window); this change adds
  only the `"fallback" => true` flag (rule 17) a chosen shot's result never
  carries.

  A no-op, changing nothing, when no window is open (including on a
  finished game, whose `finish` action already cleared it - rule 19) or
  `now` has not yet reached the deadline (rule 18); running it twice with
  the same arguments therefore shoots at most one player.

  `resolve_hunter_deadline` is meant to be called by the scheduler
  (werewolf_ash-qss.9), with no real actor behind the fallback shot it may
  create - like `end_day`/`end_night`'s own composed reactors, every
  `Player`/`Game`/`Action` touch here is `authorize?: false`, a game rule
  rather than a request made on the hunter's own behalf.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def change(changeset, _opts, _context) do
    now = Changeset.get_argument(changeset, :now)
    pick = Changeset.get_argument(changeset, :pick)

    Changeset.after_action(changeset, fn _changeset, game ->
      resolve(game, now, pick)
    end)
  end

  # rule 18 - no window open (nil pointer covers a finished game too, since
  # `finish` already cleared it).
  defp resolve(%{pending_hunter_id: nil} = game, _now, _pick), do: {:ok, game}

  defp resolve(%{hunter_deadline_at: deadline} = game, now, pick) do
    if DateTime.compare(now, deadline) == :lt do
      # rule 18 - too early: change nothing.
      {:ok, game}
    else
      shoot(game, pick)
    end
  end

  defp shoot(game, pick) do
    opts = [authorize?: false]

    with {:ok, %{current_phase: phase}} <- Ash.load(game, :current_phase, opts),
         {:ok, target} <- pick_target(game.id, pick),
         {:ok, action} <-
           Games.create_action(phase.id, game.pending_hunter_id, target.id, :shoot, opts),
         {:ok, _flagged} <- flag_fallback(action, opts) do
      Games.get_game(game.id, opts)
    end
  end

  # rule 17 - the same landed shot as a chosen one, just additionally
  # flagged; the base `%{"killed" => true}` was already stamped by
  # `ApplyShot`'s own `after_action` hook by the time `Games.create_action`
  # above returned.
  defp flag_fallback(action, opts) do
    Games.update_action(action, %{result: Map.put(action.result || %{}, "fallback", true)}, opts)
  end

  defp pick_target(game_id, pick) do
    case Games.list_living_players!(game_id, query: [sort: [id: :asc]], authorize?: false) do
      [] -> {:error, :no_living_players}
      players -> {:ok, Enum.at(players, index(pick, length(players)))}
    end
  end

  defp index(nil, count), do: :rand.uniform(count) - 1
  defp index(pick, count), do: Integer.mod(pick, count)
end
