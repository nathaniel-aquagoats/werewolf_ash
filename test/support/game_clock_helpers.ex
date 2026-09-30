defmodule WerewolfAsh.GameClockHelpers do
  @moduledoc "Shared setup for the game clock (werewolf_ash-qss.9) tests."

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @doc "A started game (5 seats) whose first day runs 2026-06-15 08:00Z to 20:00Z."
  def running_game(opts \\ []) do
    owner = generate(user())
    game = generate(game(Keyword.put(opts, :owner_id, owner.id)))
    generate_many(player(game_id: game.id), 4)
    game = Games.start_game!(game, %{now: ~U[2026-06-15 09:00:00Z]}, actor: owner)
    %{game: game, owner: owner}
  end

  def run_end_phase(game, at), do: run(game, :end_phase_on_schedule, at)
  def run_hunter_deadline(game, at), do: run(game, :hunter_deadline_on_schedule, at)

  defp run(game, action, at) do
    game
    |> Changeset.for_update(action, %{at: at}, authorize?: false)
    |> Ash.update(authorize?: false)
  end

  @doc "Opens a hunter window on `game` for one of its players, deadline `deadline`."
  def open_window(game, deadline) do
    [victim | _] = Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)

    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, victim.id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, deadline)
    |> Ash.update!()
  end

  def phases(game) do
    Games.list_phases!(
      query: [filter: [game_id: game.id], sort: [number: :asc]],
      authorize?: false
    )
  end
end
