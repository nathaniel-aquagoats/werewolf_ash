defmodule WerewolfAsh.Games.Action.Changes.ApplyKillTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Seed
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Changes.ApplyKill

  defp stage(target, actor, phase) do
    action =
      Seed.seed!(Action, %{
        phase_id: phase.id,
        actor_id: actor.id,
        target_id: target.id,
        type: :kill
      })

    # `context: %{authorize?: false}`, not `%{}`: this helper invokes the
    # hook directly, never through the real :kill action, so there is no
    # real actor to forward. In production `opts` carries the werewolf who
    # submitted the kill, who already satisfies Player's own read policy
    # (rule 4) for a fellow game member; bypassing here pins the same
    # "game rule, not an access check" behavior without needing one.
    changeset = ApplyKill.change(Changeset.new(%Action{}), [], %{authorize?: false})
    assert [hook] = changeset.after_action

    hook.(changeset, action)
  end

  describe "change/3" do
    test "an unprotected target dies and the row records it" do
      game = generate(game())
      generate(phase(game_id: game.id, kind: :day, number: 1))
      night = generate(phase(game_id: game.id, kind: :night, number: 2))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))

      assert {:ok, updated} = stage(target, werewolf, night)

      assert updated.result == %{"killed" => true}
      assert Games.get_player!(target.id, authorize?: false).alive == false
    end

    test "a target protected that day survives and the kill is spent" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      night = generate(phase(game_id: game.id, kind: :night, number: 2))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)

      assert {:ok, updated} = stage(target, werewolf, night)

      assert updated.result == %{"killed" => false}
      assert Games.get_player!(target.id, authorize?: false).alive == true
    end

    test "a kill on a game's first-ever phase behaves like the unprotected case" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))

      assert {:ok, updated} = stage(target, werewolf, night)

      assert updated.result == %{"killed" => true}
      assert Games.get_player!(target.id, authorize?: false).alive == false
    end

    test "a target protected by a bodyguard who is dead by kill resolution dies unprotected (rule 10)" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      night = generate(phase(game_id: game.id, kind: :night, number: 2))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)
      Games.update_player!(bodyguard, %{alive: false}, authorize?: false)

      assert {:ok, updated} = stage(target, werewolf, night)

      assert updated.result == %{"killed" => true}
      assert Games.get_player!(target.id, authorize?: false).alive == false
    end
  end
end
