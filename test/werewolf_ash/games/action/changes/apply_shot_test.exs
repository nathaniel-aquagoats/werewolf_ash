defmodule WerewolfAsh.Games.Action.Changes.ApplyShotTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Seed
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Changes.ApplyShot

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  defp force_pending_hunter(game, hunter_id) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, DateTime.utc_now())
    |> Ash.update!()
  end

  # Same shape as ApplyKillTest's own `stage/3`: seeds a bare `:shoot` row,
  # runs `ApplyShot.change/3` against a fresh changeset, and invokes the
  # single `after_action` hook it registers directly, bypassing the real
  # `:create` action (and so its own validations) entirely.
  defp stage(target, actor, phase) do
    action =
      Seed.seed!(Action, %{
        phase_id: phase.id,
        actor_id: actor.id,
        target_id: target.id,
        type: :shoot
      })

    changeset = ApplyShot.change(Changeset.new(%Action{}), [], %{authorize?: false})
    assert [hook] = changeset.after_action

    hook.(changeset, action)
  end

  describe "change/3" do
    test "the target dies at once and the row records the kill, bodyguard protection notwithstanding" do
      game = force_state(generate(game()), :day)
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      hunter = generate(player(game_id: game.id, role: :hunter))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      target = generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)
      force_pending_hunter(game, hunter.id)

      assert {:ok, updated} = stage(target, hunter, day)

      assert updated.result == %{"killed" => true}
      assert Games.get_player!(target.id, authorize?: false).alive == false
    end

    test "clears the game's hunter window after a landed shot" do
      game = force_state(generate(game()), :day)
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      hunter = generate(player(game_id: game.id, role: :hunter))
      generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))
      force_pending_hunter(game, hunter.id)

      assert {:ok, _updated} = stage(target, hunter, day)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert is_nil(reloaded.pending_hunter_id)
      assert is_nil(reloaded.hunter_deadline_at)
    end

    test "the win check runs after the kill and can finish the game, window still cleared" do
      game = force_state(generate(game()), :day)
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      hunter = generate(player(game_id: game.id, role: :hunter))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      force_pending_hunter(game, hunter.id)

      assert {:ok, _updated} = stage(werewolf, hunter, day)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :finished
      assert reloaded.winner == :village
      assert is_nil(reloaded.pending_hunter_id)
    end
  end
end
