defmodule WerewolfAsh.Games.Game.OpenTest do
  @moduledoc """
  `Games.open_game/2` (rules 20-23, werewolf_ash-27w.3): seats the caller as
  owner, generates the join code and accepts no client `ownerId`/`joinCode`.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  describe "open_game/2" do
    test "seats the caller as owner and sets owner_id to them" do
      owner = generate(user())

      game = Games.open_game!(%{name: "Owner's Game"}, actor: owner)

      assert game.owner_id == owner.id

      assert [%{user_id: owner_id}] =
               Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)

      assert owner_id == owner.id
    end

    test "no actor is refused" do
      assert {:error, %Ash.Error.Forbidden{}} = Games.open_game(%{name: "No One's Game"})
    end

    test "the join code is 6 characters, all in the alphabet" do
      owner = generate(user())
      game = Games.open_game!(%{name: "Coded Game"}, actor: owner)

      assert String.length(game.join_code) == 6
      assert game.join_code =~ ~r/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]+$/
    end

    test "with join_code_candidates in context, takes the first free candidate" do
      owner = generate(user())
      generate(game(join_code: "TAKEN1"))

      game =
        Games.open_game!(%{name: "Contextual Game"},
          actor: owner,
          context: %{join_code_candidates: ["TAKEN1", "FREE01"]}
        )

      assert game.join_code == "FREE01"
    end

    test "with 10 candidates all taken, fails on :join_code" do
      owner = generate(user())
      taken = for n <- 1..10, do: "TAKEN#{n}"
      Enum.each(taken, &generate(game(join_code: &1)))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Games.open_game(%{name: "Doomed Game"},
                 actor: owner,
                 context: %{join_code_candidates: taken}
               )

      assert Enum.any?(errors, &(&1.field == :join_code))
    end

    test "a supplied owner_id or join_code in params is not accepted" do
      owner = generate(user())
      impersonated = generate(user())

      assert_raise Ash.Error.Invalid, ~r/join_code/, fn ->
        Games.open_game!(%{name: "Guarded Game", owner_id: owner.id, join_code: "HACKED"},
          actor: owner
        )
      end

      assert_raise Ash.Error.Invalid, ~r/owner_id/, fn ->
        Games.open_game!(%{name: "Guarded Game", owner_id: impersonated.id}, actor: owner)
      end
    end
  end
end
