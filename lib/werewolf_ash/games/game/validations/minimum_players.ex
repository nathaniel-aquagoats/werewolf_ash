defmodule WerewolfAsh.Games.Game.Validations.MinimumPlayers do
  @moduledoc """
  Rejects `start` until the game's own configured `min_players` are already
  seated (default 5, qss.3's original fixed minimum).
  """

  use Ash.Resource.Validation

  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    minimum = changeset.data.min_players

    seated =
      Games.list_players!(query: [filter: [game_id: changeset.data.id]], authorize?: false)
      |> length()

    if seated >= minimum do
      :ok
    else
      {:error,
       field: :players,
       message: "needs at least %{minimum} seated players to start, has %{seated}",
       vars: [minimum: minimum, seated: seated]}
    end
  end
end
