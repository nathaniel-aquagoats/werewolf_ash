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

    case Games.get_game_by_join_code(join_code) do
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
