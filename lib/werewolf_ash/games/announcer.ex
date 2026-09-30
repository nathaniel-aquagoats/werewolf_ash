defmodule WerewolfAsh.Games.Announcer do
  @moduledoc """
  The game rules' one way to make an announcement: `announce/4` creates the
  row and marks every player it lists as announced, in one call. Always
  `authorize?: false` (a game rule, not a request), so call it inside the
  transition's own transaction.
  """

  alias WerewolfAsh.Games

  @doc """
  The game's players who are dead and not yet announced, as death entries
  with cause `:killed`.
  """
  def unannounced_deaths(game_id) do
    [game_id: game_id, alive: false]
    |> then(&Games.list_players!(query: [filter: &1], authorize?: false))
    |> Enum.filter(&is_nil(&1.death_announced_at))
    |> Enum.map(&%{player_id: &1.id, role: &1.role, cause: :killed})
  end

  @doc """
  Creates an announcement of `kind` and marks each player in `attrs[:deaths]`
  announced at `announced_at`.
  """
  def announce(game_id, kind, announced_at, attrs \\ %{}) do
    params = Map.merge(attrs, %{game_id: game_id, kind: kind, announced_at: announced_at})

    with {:ok, announcement} <- Games.create_announcement(params, authorize?: false),
         :ok <- mark_announced(attrs[:deaths] || [], announced_at) do
      {:ok, announcement}
    end
  end

  defp mark_announced(deaths, announced_at) do
    Enum.reduce_while(deaths, :ok, fn %{player_id: player_id}, :ok ->
      with {:ok, player} <- Games.get_player(player_id, authorize?: false),
           {:ok, _} <- Games.mark_death_announced(player, %{at: announced_at}, authorize?: false) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end
end
