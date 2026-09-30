defmodule WerewolfAsh.Games.Game.Changes.AnnounceDusk do
  @moduledoc """
  On `:end_day`, always announces the dusk at the action's `now`. The lynched
  player is the one player alive before the action and dead after its vote
  resolution; none means `:no_lynch`. `night_starting` is true unless the
  lynch's win check finished the game. Registered last, so it sees the lynch,
  the win check and the hunter window.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Announcer

  @impl true
  def change(changeset, _opts, _context) do
    now = Changeset.get_argument(changeset, :now)

    changeset
    |> Changeset.before_action(fn changeset ->
      Changeset.set_context(changeset, %{alive_before: living_ids(changeset.data.id)})
    end)
    |> Changeset.after_action(fn changeset, game ->
      lynched = changeset.context.alive_before -- living_ids(game.id)
      {:ok, current} = Games.get_game(game.id, authorize?: false)

      with {:ok, _} <-
             Announcer.announce(game.id, :dusk, now, attrs(lynched, current.state != :finished)) do
        {:ok, game}
      end
    end)
  end

  defp attrs([id], night_starting) do
    {:ok, player} = Games.get_player(id, authorize?: false)

    %{
      lynch_outcome: :lynched,
      deaths: [%{player_id: id, role: player.role, cause: :lynched}],
      night_starting: night_starting
    }
  end

  defp attrs(_none, night_starting),
    do: %{lynch_outcome: :no_lynch, deaths: [], night_starting: night_starting}

  defp living_ids(game_id) do
    game_id |> Games.list_living_players!(authorize?: false) |> Enum.map(& &1.id)
  end
end
