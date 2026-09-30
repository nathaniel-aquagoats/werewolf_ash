defmodule WerewolfAsh.Games.EnqueueFailureTest do
  @moduledoc """
  werewolf_ash-qss.9 rules 5 and 6: a failed enqueue fails the transition.

  The constraint DDL takes a table lock until the sandbox rolls back, so this
  module runs alone (`async: false`).
  """

  use WerewolfAsh.DataCase, async: false

  import WerewolfAsh.Generators

  alias Ash.UUID
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.HunterWindow

  defp block_game_clock_jobs do
    Repo.query!(
      "ALTER TABLE oban_jobs ADD CONSTRAINT qss9_block CHECK (queue <> 'game_clock') NOT VALID"
    )
  end

  test "a phase job that cannot be enqueued fails start and leaves the game in the lobby" do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))
    generate_many(player(game_id: game.id), 4)
    block_game_clock_jobs()

    assert {:error, _} = Games.start_game(game, %{now: ~U[2026-06-15 09:00:00Z]}, actor: owner)

    assert Games.get_game!(game.id, authorize?: false).state == :lobby

    assert Games.list_phases!(query: [filter: [game_id: game.id]], authorize?: false) == []
  end

  test "HunterWindow.open/4 returns an error when the deadline job cannot be enqueued" do
    game = generate(game())
    block_game_clock_jobs()

    assert {:error, _} =
             HunterWindow.open(game, UUID.generate(), ~U[2026-06-15 14:00:00Z], authorize?: false)
  end
end
