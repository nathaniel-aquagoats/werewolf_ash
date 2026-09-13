defmodule WerewolfAsh.Games.Player.Changes.ResolveGameByJoinCode do
  @moduledoc """
  Resolves the `:join_code` argument to the `Game` it names and stages
  `:game_id` to that game's id, looked up the same way
  `Games.get_game_by_join_code/1,2` already does (via `Game`'s
  `:unique_join_code` identity) — never a caller-supplied `game_id`. An
  unknown join code fails the changeset on `:join_code` instead, and leaves
  `:game_id` unset.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def change(changeset, _opts, _context) do
    join_code = Changeset.get_argument(changeset, :join_code)

    # Resolving a join code to the game it names is a game rule, not an
    # access check the joining actor needs to already pass: they aren't
    # seated yet, so Game's own read policy (werewolf_ash-27w.2 rule 1)
    # would otherwise never find it. Player's own :join policy (rule 6,
    # unchanged) is what actually decides whether the seat gets created.
    case Games.get_game_by_join_code(join_code, authorize?: false) do
      {:ok, game} ->
        Changeset.force_change_attribute(changeset, :game_id, game.id)

      {:error, _error} ->
        Changeset.add_error(changeset,
          field: :join_code,
          message: "does not match any game"
        )
    end
  end
end
