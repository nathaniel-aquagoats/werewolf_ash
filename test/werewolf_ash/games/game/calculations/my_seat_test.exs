defmodule WerewolfAsh.Games.Game.Calculations.MySeatTest do
  @moduledoc """
  `Games.get_game/2` with `load: [:my_seat]` (rule 9, werewolf_ash-27w.3):
  the caller's own seat, with their own role visible, read as themselves.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  defp actor_for(player), do: %{id: player.user_id}

  test "returns the caller's own seat, with their role visible" do
    game = generate(game())
    seat = generate(player(game_id: game.id, role: :seer))

    loaded = Games.get_game!(game.id, load: [:my_seat], actor: actor_for(seat))

    assert loaded.my_seat.id == seat.id
    assert loaded.my_seat.role == :seer
  end

  test "another reader gets their own seat, not the first player's" do
    game = generate(game())
    first = generate(player(game_id: game.id))
    second = generate(player(game_id: game.id))

    loaded = Games.get_game!(game.id, load: [:my_seat], actor: actor_for(second))

    assert loaded.my_seat.id == second.id
    refute loaded.my_seat.id == first.id
  end

  test "is nil for a caller with no seat" do
    game = generate(game())
    outsider = generate(user())

    assert Games.get_game!(game.id,
             load: [:my_seat],
             authorize?: false,
             actor: %{id: outsider.id}
           ).my_seat ==
             nil
  end
end
