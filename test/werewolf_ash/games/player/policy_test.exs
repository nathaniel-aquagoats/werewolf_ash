defmodule WerewolfAsh.Games.Player.PolicyTest do
  @moduledoc """
  Rule 4 (werewolf_ash-27w.2): a `Player` row is readable only while the
  reading actor themselves holds a seat, any role, alive or dead, in that
  row's game. Rule 5's `:role` field policy is exercised separately below.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  describe "rule 4 - Player read policy" do
    test "a fellow game member reads a Player row, living or dead" do
      # game() already seats an owner, so this game has four players total.
      game = generate(game())
      reader = generate(player(game_id: game.id))
      alive_target = generate(player(game_id: game.id))
      dead_target = generate(player(game_id: game.id))
      Games.update_player!(dead_target, %{alive: false})

      actor = %{id: reader.user_id}

      assert Games.get_player!(alive_target.id, actor: actor).id == alive_target.id
      assert Games.get_player!(dead_target.id, actor: actor).id == dead_target.id

      assert Games.list_players!(query: [filter: [game_id: game.id]], actor: actor)
             |> length() == 4

      living_ids = Games.list_living_players!(game.id, actor: actor) |> Enum.map(& &1.id)
      assert reader.id in living_ids
      assert alive_target.id in living_ids
      refute dead_target.id in living_ids
    end

    test "a user with no seat in that game cannot read its Player rows" do
      game = generate(game())
      target = generate(player(game_id: game.id))
      outsider = generate(user())
      actor = %{id: outsider.id}

      assert {:error, %Ash.Error.Invalid{}} = Games.get_player(target.id, actor: actor)
      assert Games.list_players!(query: [filter: [game_id: game.id]], actor: actor) == []
      assert Games.list_living_players!(game.id, actor: actor) == []
    end
  end

  describe "rule 5 - Player.role field policy" do
    test "a player reads their own role" do
      game = generate(game())
      player = generate(player(game_id: game.id, role: :seer))

      reloaded = Ash.get!(Games.Player, player.id, actor: %{id: player.user_id})
      assert reloaded.role == :seer
    end

    test "a werewolf reads a fellow werewolf's role" do
      game = generate(game())
      wolf1 = generate(player(game_id: game.id, role: :werewolf))
      wolf2 = generate(player(game_id: game.id, role: :werewolf))

      reloaded = Ash.get!(Games.Player, wolf2.id, actor: %{id: wolf1.user_id})
      assert reloaded.role == :werewolf
    end

    test "a villager reading a wolf's, the seer's or another villager's role gets a forbidden field, not nil" do
      game = generate(game())
      villager = generate(player(game_id: game.id, role: :villager))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      seer = generate(player(game_id: game.id, role: :seer))
      other_villager = generate(player(game_id: game.id, role: :villager))

      actor = %{id: villager.user_id}

      for target <- [wolf, seer, other_villager] do
        reloaded = Ash.get!(Games.Player, target.id, actor: actor)
        assert %Ash.ForbiddenField{} = reloaded.role
      end
    end

    test "once the game is :finished, a villager reads a wolf's role; the same setup while the game is still running still hides it" do
      finished_game = generate(game())
      villager = generate(player(game_id: finished_game.id, role: :villager))
      wolf = generate(player(game_id: finished_game.id, role: :werewolf))
      finish_game(finished_game)

      finished_read = Ash.get!(Games.Player, wolf.id, actor: %{id: villager.user_id})
      assert finished_read.role == :werewolf

      running_game = generate(game())
      running_villager = generate(player(game_id: running_game.id, role: :villager))
      running_wolf = generate(player(game_id: running_game.id, role: :werewolf))

      running_read =
        Ash.get!(Games.Player, running_wolf.id, actor: %{id: running_villager.user_id})

      assert %Ash.ForbiddenField{} = running_read.role
    end

    test "a dead villager reads a living wolf's role; the same reader still alive still gets it hidden" do
      game = generate(game())
      dead_villager = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(dead_villager, %{alive: false})
      wolf = generate(player(game_id: game.id, role: :werewolf))

      dead_read = Ash.get!(Games.Player, wolf.id, actor: %{id: dead_villager.user_id})
      assert dead_read.role == :werewolf

      living_villager = generate(player(game_id: game.id, role: :villager))
      living_read = Ash.get!(Games.Player, wolf.id, actor: %{id: living_villager.user_id})
      assert %Ash.ForbiddenField{} = living_read.role
    end
  end

  defp finish_game(game) do
    game
    |> Changeset.for_update(:update, %{}, authorize?: false)
    |> Changeset.force_change_attribute(:state, :finished)
    |> Ash.update!()
  end
end
