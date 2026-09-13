defmodule WerewolfAsh.Games.Game.Changes.ResolveDayVoteTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @now ~U[2026-06-15 20:00:00Z]

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  defp day_game do
    game = force_state(generate(game()), :day)
    day = generate(phase(game_id: game.id, kind: :day, number: 1))
    %{game: game, day: day}
  end

  # Stages both of `:end_day`'s changes at once, the same way building the
  # changeset for that action does in production: `Ash.Changeset.for_update`
  # runs every declared `change`'s own `change/3` immediately, so both
  # `AdvancePhase` and `ResolveDayVote` register their `after_action` hooks
  # on this one changeset, in that order.
  defp stage_hooks(game, now) do
    changeset = Changeset.for_update(game, :end_day, %{now: now}, authorize?: false)
    assert changeset.valid?
    assert [advance_hook, resolve_hook | _] = changeset.after_action
    {changeset, advance_hook, resolve_hook}
  end

  describe "change/3 (staged like ApplyKillTest's stage/3 helper)" do
    test "when the vote decides a winner, destroys the night phase AdvancePhase just opened (rules 13, 14)" do
      %{game: game, day: day} = day_game()

      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager1 = generate(player(game_id: game.id, role: :villager))
      villager2 = generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, villager1.id, wolf.id, :vote)
      Games.create_action!(day.id, villager2.id, wolf.id, :vote)

      {changeset, advance_hook, resolve_hook} = stage_hooks(game, @now)

      assert {:ok, after_advance} = advance_hook.(changeset, game)

      assert [night] = Games.list_phases!(query: [filter: [game_id: game.id, kind: :night]])

      assert {:ok, resolved} = resolve_hook.(changeset, after_advance)

      assert resolved.state == :finished
      assert resolved.winner == :village
      assert Games.get_player!(wolf.id).alive == false

      assert Games.list_phases!(query: [filter: [id: night.id]]) == []
      refute is_nil(Games.get_phase!(day.id).ended_at)
    end

    test "when nobody has won yet, leaves AdvancePhase's night phase exactly as it was created (rule 15)" do
      %{game: game, day: day} = day_game()

      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager1 = generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, villager1.id, wolf.id, :vote)
      Games.create_action!(day.id, wolf.id, villager1.id, :vote)

      {changeset, advance_hook, resolve_hook} = stage_hooks(game, @now)

      assert {:ok, after_advance} = advance_hook.(changeset, game)

      assert [night_before] =
               Games.list_phases!(query: [filter: [game_id: game.id, kind: :night]])

      assert {:ok, _resolved} = resolve_hook.(changeset, after_advance)

      night_after = Games.get_phase!(night_before.id)
      assert night_after.ended_at == nil
      assert night_after.number == night_before.number
      assert Games.get_player!(wolf.id).alive == true
      assert Games.get_player!(villager1.id).alive == true
    end
  end
end
