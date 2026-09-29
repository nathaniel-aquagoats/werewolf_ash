defmodule WerewolfAsh.Games.Game.Calculations.MySeat do
  @moduledoc """
  Backs `Game`'s `:my_seat` calculation (`mySeat` in GraphQL, rule 9,
  werewolf_ash-27w.3): the caller's own `Player` row in the game, or `nil`
  for a caller with no seat (which cannot happen on a game the caller can
  read at all, but is the defined answer with no actor either).

  Like `Phase.Calculations.VoteTally`, this performs its own, ordinary,
  authorized read of `Games.list_players` inside `calculate/3`, passing the
  calculation's own actor/authorize? through unchanged
  (`Ash.Context.to_opts/1`) - never `authorize?: false`. Because the read is
  authorized as the caller, the returned seat's `role` follows the ordinary
  `Player` field policy the same way it would through any other read: the
  caller sees their own role.
  """

  use Ash.Resource.Calculation

  alias Ash.Context
  alias WerewolfAsh.Games

  @impl true
  def calculate(games, _opts, %{actor: nil}), do: Enum.map(games, fn _ -> nil end)

  def calculate(games, _opts, context) do
    Enum.map(games, &seat_in(&1, context))
  end

  defp seat_in(game, context) do
    opts =
      Keyword.merge(Context.to_opts(context),
        query: [filter: [game_id: game.id, user_id: context.actor.id]]
      )

    case Games.list_players(opts) do
      {:ok, [seat]} -> seat
      _ -> nil
    end
  end
end
