defmodule WerewolfAsh.Games.Action.Changes.ResolveKillWinTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Seed
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Changes.ResolveKillWin

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  # Games are built in :night, not the :lobby games apply_kill_test.exs uses:
  # from :lobby, `finish` isn't allowed, so a win check that wrongly ran on a
  # spent kill would still leave the game untouched and the test would pass
  # for the wrong reason.
  defp night_game, do: force_state(generate(game()), :night)

  defp seed_kill(phase, actor, target, killed?) do
    Seed.seed!(Action, %{
      phase_id: phase.id,
      actor_id: actor.id,
      target_id: target.id,
      type: :kill,
      result: %{"killed" => killed?}
    })
  end

  defp stage(action) do
    # `context: %{authorize?: false}`, not `%{}`: this helper invokes the
    # hook directly, never through the real :kill action, so there is no
    # real actor to forward for Game's own read policy (rule 1).
    changeset = ResolveKillWin.change(Changeset.new(%Action{}), [], %{authorize?: false})
    assert [hook] = changeset.after_action
    hook.(changeset, action)
  end

  describe "change/3" do
    test "a landed kill that decides :continue leaves the game's state and winner untouched" do
      game = night_game()
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :villager))
      target = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(target, %{alive: false})

      action = seed_kill(night, werewolf, target, true)

      assert {:ok, _action} = stage(action)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :night
      assert is_nil(reloaded.winner)
    end

    test "a landed kill that decides :village_wins finishes the game for the village" do
      game = night_game()
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      Games.update_player!(werewolf, %{alive: false})
      target = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(target, %{alive: false})

      action = seed_kill(night, werewolf, target, true)

      assert {:ok, _action} = stage(action)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :finished
      assert reloaded.winner == :village
    end

    test "a landed kill that decides :wolves_wins finishes the game for the wolves" do
      game = night_game()
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(target, %{alive: false})

      action = seed_kill(night, werewolf, target, true)

      assert {:ok, _action} = stage(action)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :finished
      assert reloaded.winner == :wolves
    end

    test "a spent kill runs no win check, regardless of the living counts, and returns {:ok, _}" do
      game = night_game()
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))

      # Kill the game's own auto-seated owner directly, so the living counts
      # going into this kill already sit at exact wolf parity (1 wolf vs 1
      # non-wolf, the target): a check-runs-regardless-of-spent
      # implementation would finish the game here; a correct one leaves it
      # alone, since the kill was spent.
      owner =
        Enum.find(
          Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false),
          &is_nil(&1.role)
        )

      Games.update_player!(owner, %{alive: false})

      action = seed_kill(night, werewolf, target, false)

      assert {:ok, _action} = stage(action)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :night
      assert is_nil(reloaded.winner)
      assert Games.get_player!(target.id, authorize?: false).alive == true
    end

    test "a decisive landed kill on a :lobby game makes ResolveWin fail, returning {:error, _}" do
      game = generate(game())
      night = generate(phase(game_id: game.id, kind: :night, number: 1))
      werewolf = generate(player(game_id: game.id, role: :werewolf))
      Games.update_player!(werewolf, %{alive: false})
      target = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(target, %{alive: false})

      action = seed_kill(night, werewolf, target, true)

      assert {:error, _reason} = stage(action)

      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.state == :lobby
    end
  end
end
