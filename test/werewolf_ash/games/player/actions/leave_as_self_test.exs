defmodule WerewolfAsh.Games.Player.Actions.LeaveAsSelfTest do
  @moduledoc """
  `Games.leave_as_self/2` (rules 25-26, werewolf_ash-27w.3): removes the
  caller's own seat in a lobby, refused for the owner, once started, or for
  an unseated caller.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  describe "leave_as_self/2" do
    test "removes the caller's own seat in a lobby" do
      game = generate(game())
      leaver = generate(user())
      generate(player(game_id: game.id, user_id: leaver.id))

      assert Games.leave_as_self!(game.id, actor: leaver) == :ok

      assert Games.list_players!(
               query: [filter: [game_id: game.id, user_id: leaver.id]],
               authorize?: false
             ) == []
    end

    test "refused for the owner, whose seat remains" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.leave_as_self(game.id, actor: owner)

      assert [_seat] =
               Games.list_players!(
                 query: [filter: [game_id: game.id, user_id: owner.id]],
                 authorize?: false
               )
    end

    test "refused once the game has started" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      leaver = generate(user())
      generate(player(game_id: game.id, user_id: leaver.id))
      generate_many(player(game_id: game.id), 3)
      Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]}, actor: owner)

      assert {:error, %Ash.Error.Invalid{}} = Games.leave_as_self(game.id, actor: leaver)
    end

    test "refused for an unseated caller" do
      game = generate(game())
      outsider = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.leave_as_self(game.id, actor: outsider)
    end
  end
end
