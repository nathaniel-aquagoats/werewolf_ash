defmodule WerewolfAsh.Games.Player.Validations.GameInLobby do
  @moduledoc """
  Rejects an action on a `Player` whose `Game` has already left the
  `:lobby` state. Shared by `:join` (rule 5) and the destroy action behind
  "leave" (rule 7); `field:` says which field the error is reported
  against, mirroring `KnownTimezone`'s `attribute:` option.

  A `Player` with no resolvable `:game_id` yet (an unknown `:join_code`
  already failed elsewhere) is left alone here rather than piling on a
  second error.
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
    case Changeset.get_attribute(changeset, :game_id) do
      nil ->
        :ok

      game_id ->
        case Games.get_game(game_id, authorize?: false) do
          {:ok, %{state: :lobby}} -> :ok
          _ -> {:error, field: opts[:field], message: "the game has already left its lobby"}
        end
    end
  end
end
