defmodule WerewolfAsh.Games.Action.PolicyTest do
  @moduledoc """
  Rules 7-8 (werewolf_ash-27w.2): an `Action` row may only be created as the
  caller's own seat, and read narrowing by type (`:kill` to werewolves,
  `:investigate`/`:protect` to the seer/bodyguard who cast them), except
  once the reading actor's own seat has died, when every row is visible.

  qss.4's role/phase/aliveness validations are exercised elsewhere
  (`action_test.exs`); this file is only about *who* may create/read a row.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  defp actor_for(player), do: %{id: player.user_id}

  describe "rule 7 - Action create policy" do
    test "an actor_id naming the caller's own seat is authorized" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      voter = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      action =
        Games.create_action!(day.id, voter.id, target.id, :vote, actor: actor_for(voter))

      assert action.actor_id == voter.id
    end

    test "an actor_id naming another player's seat is forbidden" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      voter = generate(player(game_id: game.id))
      impersonator = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.create_action(day.id, voter.id, target.id, :vote,
                 actor: actor_for(impersonator)
               )
    end

    test "no actor at all is forbidden" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      voter = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.create_action(day.id, voter.id, target.id, :vote)
    end
  end

  describe "rule 7 - :kill create policy (create_kill_action)" do
    test "a werewolf submitting as their own seat is authorized" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id))
      # a bystander so the kill's own win check doesn't decide the game
      # (game() already auto-seats one non-wolf owner besides this one).
      generate(player(game_id: game.id))

      action =
        Games.create_kill_action!(night.id, wolf.id, target.id, actor: actor_for(wolf))

      assert action.type == :kill
    end

    test "a kill whose actor_id references another user's seat is forbidden" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      impersonator = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.create_kill_action(night.id, wolf.id, target.id,
                 actor: actor_for(impersonator)
               )
    end

    test "a kill submitted with no actor is forbidden" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.create_kill_action(night.id, wolf.id, target.id)
    end
  end

  describe "rule 8 - Action read policy, type narrowing" do
    setup do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      night = generate(phase(game_id: game.id, kind: :night, number: 2))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      seer = generate(player(game_id: game.id, role: :seer))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      villager = generate(player(game_id: game.id, role: :villager))
      target = generate(player(game_id: game.id, role: :villager))
      # a target of its own, so the kill's own effect (the target dies)
      # doesn't fail TargetAlive for the investigate/protect/vote rows below.
      kill_target = generate(player(game_id: game.id, role: :villager))

      investigate =
        Games.create_action!(night.id, seer.id, target.id, :investigate, authorize?: false)

      protect =
        Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)

      vote = Games.create_action!(day.id, villager.id, target.id, :vote, authorize?: false)

      kill = Games.create_kill_action!(night.id, wolf.id, kill_target.id, authorize?: false)

      %{
        game: game,
        wolf: wolf,
        seer: seer,
        bodyguard: bodyguard,
        villager: villager,
        target: target,
        kill: kill,
        investigate: investigate,
        protect: protect,
        vote: vote
      }
    end

    test "an outsider holding no seat in the game cannot read any row", ctx do
      outsider = generate(user())
      outsider_actor = %{id: outsider.id}

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.vote.id, actor: outsider_actor)

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.kill.id, actor: outsider_actor)

      assert Games.list_actions!(actor: outsider_actor) == []
    end

    test ":kill is readable by a werewolf seat-holder", ctx do
      assert Games.get_action!(ctx.kill.id, actor: actor_for(ctx.wolf)).id == ctx.kill.id
    end

    test ":kill is not readable by a non-wolf game member", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.kill.id, actor: actor_for(ctx.villager))
    end

    test ":investigate is readable by the seer who cast it", ctx do
      assert Games.get_action!(ctx.investigate.id, actor: actor_for(ctx.seer)).id ==
               ctx.investigate.id
    end

    test ":investigate is not readable by any other game member, wolf included", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.investigate.id, actor: actor_for(ctx.wolf))

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.investigate.id, actor: actor_for(ctx.villager))
    end

    test ":protect is readable by the bodyguard who cast it", ctx do
      assert Games.get_action!(ctx.protect.id, actor: actor_for(ctx.bodyguard)).id ==
               ctx.protect.id
    end

    test ":protect is not readable by any other game member, a werewolf included", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.protect.id, actor: actor_for(ctx.wolf))

      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.protect.id, actor: actor_for(ctx.villager))
    end

    test ":vote is readable by any game member", ctx do
      assert Games.get_action!(ctx.vote.id, actor: actor_for(ctx.villager)).id == ctx.vote.id
      assert Games.get_action!(ctx.vote.id, actor: actor_for(ctx.wolf)).id == ctx.vote.id
    end

    test "a dead non-wolf, non-seer, non-bodyguard game member reads a :kill row once dead, but not while alive",
         ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.kill.id, actor: actor_for(ctx.villager))

      Games.update_player!(ctx.villager, %{alive: false})

      assert Games.get_action!(ctx.kill.id, actor: actor_for(ctx.villager)).id == ctx.kill.id
    end

    test "a dead non-wolf, non-seer, non-bodyguard game member reads an :investigate row once dead, but not while alive",
         ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.investigate.id, actor: actor_for(ctx.villager))

      Games.update_player!(ctx.villager, %{alive: false})

      assert Games.get_action!(ctx.investigate.id, actor: actor_for(ctx.villager)).id ==
               ctx.investigate.id
    end

    test "a dead non-wolf, non-seer, non-bodyguard game member reads a :protect row once dead, but not while alive",
         ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.get_action(ctx.protect.id, actor: actor_for(ctx.villager))

      Games.update_player!(ctx.villager, %{alive: false})

      assert Games.get_action!(ctx.protect.id, actor: actor_for(ctx.villager)).id ==
               ctx.protect.id
    end
  end
end
