defmodule WerewolfAsh.Games.Player.Validations.GameNotFull do
  @moduledoc """
  Rejects seating a player once the game already has `max_players` players
  seated; never fires when the game's `max_players` is `nil`. Shared by
  `:join` (rule 11) and the primary `:create` action `add_player` uses (rule
  16); `field:` says which field the error is reported against, mirroring
  `GameInLobby`'s `field:` option.

  Declared with `before_action?: true` on both actions so this runs inside
  the action's own transaction, after a fresh
  `Games.get_game(game_id, authorize?: false, lock: :for_update)` has locked
  the `Game` row. Only once that lock is held does this read `max_players`
  off the locked row and, if it is set, count seated players — never the
  other way around. A concurrent `:join`/`:create` on the same game blocks on
  that same lock until this transaction commits or rolls back, so the two
  calls can never together seat more than `max_players` (see the spec for the
  full race argument; no sandboxed test can exercise it).

  A `game_id` naming no row (only reachable through `add_player`'s bare
  `game_id` argument, never through `:join`'s already-resolved `game_id`) is
  reported on the same `field:` with `message: "does not exist"`, instead of
  falling through to the database's own foreign-key error.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def init(opts) do
    if is_atom(opts[:field]) and not is_nil(opts[:field]) do
      {:ok, opts}
    else
      {:error, "`field` must be an atom, got: #{inspect(opts[:field])}"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    game_id = Changeset.get_attribute(changeset, :game_id)

    case Games.get_game(game_id, authorize?: false, lock: :for_update) do
      {:ok, %{max_players: nil}} ->
        :ok

      {:ok, %{id: game_id, max_players: max_players}} ->
        seated =
          Games.list_players!(query: [filter: [game_id: game_id]], authorize?: false)
          |> length()

        if seated < max_players do
          :ok
        else
          {:error, field: opts[:field], message: "the game is already full"}
        end

      _ ->
        {:error, field: opts[:field], message: "does not exist"}
    end
  end
end
