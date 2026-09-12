defmodule WerewolfAsh.Games.Game.Validations.MinimumPlayers do
  @moduledoc """
  Rejects `start` until at least 5 `Player` rows are already seated in the
  game.
  """

  use Ash.Resource.Validation

  alias WerewolfAsh.Games

  @minimum 5

  @impl true
  def validate(changeset, _opts, _context) do
    seated =
      Games.list_players!(query: [filter: [game_id: changeset.data.id]], authorize?: false)
      |> length()

    if seated >= @minimum do
      :ok
    else
      {:error,
       field: :players,
       message: "needs at least %{minimum} seated players to start, has %{seated}",
       vars: [minimum: @minimum, seated: seated]}
    end
  end
end
