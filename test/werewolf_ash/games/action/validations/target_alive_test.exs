defmodule WerewolfAsh.Games.Action.Validations.TargetAliveTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers
  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.TargetAlive

  describe "validate/3" do
    test "passes for a living target" do
      game = generate(game())
      target = generate(player(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:target_id, target.id)

      assert TargetAlive.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :target_id, for a dead target" do
      game = generate(game())
      target = generate(player(game_id: game.id))
      Games.update_player!(target, %{alive: false})

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:target_id, target.id)

      assert {:error, error} = TargetAlive.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "passes when target_id is absent" do
      changeset = Changeset.new(%Action{})

      assert TargetAlive.validate(changeset, [], %{}) == :ok
    end
  end

  describe "validate/3 with night_victim?: true (qss.19 rules 25-26)" do
    defp changeset(target, phase) do
      %Action{}
      |> Changeset.new()
      |> Changeset.change_attribute(:target_id, target.id)
      |> Changeset.change_attribute(:phase_id, phase.id)
    end

    test "passes for an unannounced victim of a landed kill in the named phase" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert TargetAlive.validate(changeset(ctx.victim, ctx.phase), [night_victim?: true], %{}) ==
               :ok
    end

    test "without the option the same dead target still fails" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert {:error, error} = TargetAlive.validate(changeset(ctx.victim, ctx.phase), [], %{})
      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "fails on :target_id for a player killed with update_player, no kill row" do
      ctx = night_game()
      kill_all!([ctx.victim])

      assert {:error, error} =
               TargetAlive.validate(changeset(ctx.victim, ctx.phase), [night_victim?: true], %{})

      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "fails for a victim whose death is announced" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)
      announce_death!(Games.get_player!(ctx.victim.id, authorize?: false))

      assert {:error, _} =
               TargetAlive.validate(changeset(ctx.victim, ctx.phase), [night_victim?: true], %{})
    end

    test "fails when the landed kill is in another phase, or the kill was spent" do
      ctx = night_game()
      other = generate(phase(game_id: ctx.game.id, kind: :night, number: 3))
      night_kill!(other, ctx.wolf, ctx.victim)

      assert {:error, _} =
               TargetAlive.validate(changeset(ctx.victim, ctx.phase), [night_victim?: true], %{})

      # a spent kill (bodyguard) leaves a row with killed: false; the target
      # here is dead some other way, so the row does not qualify them.
      spent = generate(phase(game_id: ctx.game.id, kind: :night, number: 5))
      kill = night_kill!(spent, ctx.wolf, ctx.villager)
      Games.update_action!(kill, %{result: %{"killed" => false}}, authorize?: false)

      assert {:error, _} =
               TargetAlive.validate(changeset(ctx.villager, spent), [night_victim?: true], %{})
    end
  end
end
