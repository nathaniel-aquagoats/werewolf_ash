defmodule WerewolfAsh.Games.Game.Changes.ResolveNightWinTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @now ~U[2026-06-16 08:00:00Z]

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  defp night_game do
    game = force_state(generate(game()), :night)
    night = generate(phase(game_id: game.id, kind: :night, number: 1))
    %{game: game, night: night}
  end

  # Stages both of `:end_night`'s changes at once, the same way
  # ResolveDayVoteTest's `stage_hooks/2` does for the symmetric `:end_day`
  # case: `Ash.Changeset.for_update` runs every declared `change`'s own
  # `change/3` immediately, so both `AdvancePhase` and `ResolveNightWin`
  # register their `after_action` hooks on this one changeset, in that order.
  defp stage_hooks(game, now) do
    changeset = Changeset.for_update(game, :end_night, %{now: now}, authorize?: false)
    assert changeset.valid?
    assert [advance_hook, resolve_hook | _] = changeset.after_action
    {changeset, advance_hook, resolve_hook}
  end

  describe "change/3 (staged like ResolveDayVoteTest's stage_hooks/2 helper)" do
    test "when the check decides a winner, destroys the day phase AdvancePhase just opened (rules 9, 10)" do
      %{game: game, night: night} = night_game()

      generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))
      Games.update_player!(target, %{alive: false})

      owner =
        Enum.find(Games.list_players!(query: [filter: [game_id: game.id]]), &is_nil(&1.role))

      Games.update_player!(owner, %{alive: false})

      {changeset, advance_hook, resolve_hook} = stage_hooks(game, @now)

      assert {:ok, after_advance} = advance_hook.(changeset, game)

      assert [day] = Games.list_phases!(query: [filter: [game_id: game.id, kind: :day]])

      assert {:ok, resolved} = resolve_hook.(changeset, after_advance)

      assert resolved.state == :finished
      assert resolved.winner == :wolves

      assert Games.list_phases!(query: [filter: [id: day.id]]) == []
      refute is_nil(Games.get_phase!(night.id).ended_at)
    end

    test "when the check decides :continue, leaves AdvancePhase's day phase exactly as it was created (rule 11)" do
      %{game: game} = night_game()

      generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :villager))

      {changeset, advance_hook, resolve_hook} = stage_hooks(game, @now)

      assert {:ok, after_advance} = advance_hook.(changeset, game)

      assert [day_before] = Games.list_phases!(query: [filter: [game_id: game.id, kind: :day]])

      assert {:ok, _resolved} = resolve_hook.(changeset, after_advance)

      day_after = Games.get_phase!(day_before.id)
      assert day_after.ended_at == nil
      assert day_after.number == day_before.number
    end
  end
end
