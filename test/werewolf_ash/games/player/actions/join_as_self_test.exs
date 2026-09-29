defmodule WerewolfAsh.Games.Player.Actions.JoinAsSelfTest do
  @moduledoc """
  `Games.join_as_self/2` (rule 24, werewolf_ash-27w.3): seats the caller by
  their game's join code, upcasing it, never a client `user_id`.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  describe "join_as_self/2" do
    test "seats the caller by code (also lower-cased)" do
      game = generate(game(join_code: "ABCDEF"))
      joiner = generate(user())

      player = Games.join_as_self!("abcdef", actor: joiner)

      assert player.user_id == joiner.id
      assert player.game_id == game.id
    end

    test "an unknown code fails on :join_code" do
      joiner = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :join_code}]}} =
               Games.join_as_self("NOPE00", actor: joiner)
    end

    test "a started game fails on the existing field" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id, join_code: "STARTD"))
      generate_many(player(game_id: game.id), 4)
      Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]}, actor: owner)

      joiner = generate(user())

      assert {:error, %Ash.Error.Invalid{}} = Games.join_as_self("STARTD", actor: joiner)
    end

    test "a nameless caller fails on the existing field" do
      generate(game(join_code: "NONAME"))
      joiner = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{}} = Games.join_as_self("NONAME", actor: joiner)
    end

    test "a full game fails on the existing field" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id, join_code: "FULL01"))

      Games.update_game_settings!(
        game,
        %{
          min_players: 1,
          max_players: 1,
          seer_enabled: false,
          bodyguard_enabled: false,
          hunter_enabled: false
        },
        actor: owner
      )

      joiner = generate(user())

      assert {:error, %Ash.Error.Invalid{}} = Games.join_as_self("FULL01", actor: joiner)
    end

    test "no actor is refused" do
      generate(game(join_code: "NOAUTH"))
      assert {:error, %Ash.Error.Forbidden{}} = Games.join_as_self("NOAUTH")
    end
  end
end
