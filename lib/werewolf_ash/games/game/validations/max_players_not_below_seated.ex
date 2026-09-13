defmodule WerewolfAsh.Games.Game.Validations.MaxPlayersNotBelowSeated do
  @moduledoc """
  Rejects `:update_settings` when the resulting `max_players` would be set
  below the game's current seated-player count (rule 17); a `nil` resulting
  `max_players` never fires this, and setting it exactly equal to the seated
  count is allowed.

  Declared with `before_action?: true` so this runs inside `:update_settings`'s
  own transaction. The resulting `max_players` itself is read straight off the
  changeset before any lock — this transaction's own pending write is not a
  fact any concurrent transaction can change out from under it. But the
  seated count it is compared against can change concurrently, so once a
  non-nil `max_players` is found, this reloads the game with a row lock —
  `Games.get_game(game_id, authorize?: false, lock: :for_update)`, the same
  call `GameNotFull` uses — before counting seated players, not after. A
  concurrent `:join`/`add_player` racing this call blocks on that same lock
  until whichever transaction got there first commits or rolls back (see the
  spec for the full race argument; no sandboxed test can exercise it).
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :max_players) do
      nil ->
        :ok

      max_players ->
        check(changeset.data.id, max_players)
    end
  end

  defp check(game_id, max_players) do
    case Games.get_game(game_id, authorize?: false, lock: :for_update) do
      {:ok, game} ->
        seated =
          Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
          |> length()

        if max_players >= seated do
          :ok
        else
          {:error,
           field: :max_players,
           message: "cannot be set below the %{seated} players already seated",
           vars: [seated: seated]}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
