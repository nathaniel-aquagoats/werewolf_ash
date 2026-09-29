defmodule WerewolfAsh.Games.Game.MineTest do
  @moduledoc """
  `Games.my_games/1` (rule 7, werewolf_ash-27w.3): every game the caller
  holds a seat in, in any state, newest `inserted_at` first, with no filter
  of its own - the existing `action_type(:read)` policy is what narrows the
  result.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  describe "my_games/1" do
    test "lists only the caller's own games, in any state, newest inserted_at first" do
      caller = generate(user())

      # game() already seats the owner (SeatOwner); joining an existing
      # game seats a second, non-owner caller instead, so both memberships
      # are covered.
      older_as_owner = generate(game(owner_id: caller.id))

      newer_as_member = generate(game())
      generate(player(game_id: newer_as_member.id, user_id: caller.id))

      other_game = generate(game())

      assert Games.my_games!(actor: caller) |> Enum.map(& &1.id) ==
               [newer_as_member.id, older_as_owner.id]

      refute other_game.id in Enum.map(Games.my_games!(actor: caller), & &1.id)
    end

    test "returns [] for a user with no games, and for no actor at all" do
      lonely = generate(user())
      generate(game())

      assert Games.my_games!(actor: lonely) == []
      assert Games.my_games!() == []
    end
  end
end
