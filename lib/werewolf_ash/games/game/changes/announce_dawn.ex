defmodule WerewolfAsh.Games.Game.Changes.AnnounceDawn do
  @moduledoc """
  On `:end_night`, always announces the dawn: every unannounced death, with
  role and cause `:killed` (empty when nobody died), at the action's `now`.
  Registered after the dawn win check and hunter window, inside the same
  transaction.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games.Announcer

  @impl true
  def change(changeset, _opts, _context) do
    now = Changeset.get_argument(changeset, :now)

    Changeset.after_action(changeset, fn _changeset, game ->
      deaths = Announcer.unannounced_deaths(game.id)

      with {:ok, _} <- Announcer.announce(game.id, :dawn, now, %{deaths: deaths}) do
        {:ok, game}
      end
    end)
  end
end
