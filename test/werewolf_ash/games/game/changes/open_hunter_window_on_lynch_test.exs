defmodule WerewolfAsh.Games.Game.Changes.OpenHunterWindowOnLynchTest do
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

  # Stages all three of `:end_day`'s changes at once, the same way
  # ResolveDayVoteTest's own `stage_hooks/2` does: `Ash.Changeset.for_update`
  # runs every declared `change`'s own `change/3` immediately, registering
  # `AdvancePhase`, `ResolveDayVote` and this module's own hook on the one
  # changeset, in that order.
  defp stage_hooks(game, now) do
    changeset = Changeset.for_update(game, :end_day, %{now: now}, authorize?: false)
    assert changeset.valid?
    assert [advance_hook, resolve_hook, window_hook | _] = changeset.after_action
    {changeset, advance_hook, resolve_hook, window_hook}
  end

  # Runs the vote resolution and dusk win check (the two hooks registered
  # ahead of this module's own), returning what this module's own hook then
  # sees.
  defp run_up_to_window(game) do
    {changeset, advance_hook, resolve_hook, window_hook} = stage_hooks(game, @now)
    assert {:ok, after_advance} = advance_hook.(changeset, game)
    assert {:ok, after_resolve} = resolve_hook.(changeset, after_advance)
    {changeset, after_resolve, window_hook}
  end

  describe "change/3 (staged like ResolveDayVoteTest's own stage_hooks/2)" do
    test "opens the window when this lynch killed the dealt hunter, deadline now + 1h (rule 3)" do
      %{game: game, day: day} = day_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      villager1 = generate(player(game_id: game.id, role: :villager))
      villager2 = generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :werewolf))

      Games.create_action!(day.id, villager1.id, hunter.id, :vote, authorize?: false)
      Games.create_action!(day.id, villager2.id, hunter.id, :vote, authorize?: false)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.pending_hunter_id == hunter.id

      assert DateTime.compare(resolved.hunter_deadline_at, DateTime.add(@now, 3600, :second)) ==
               :eq
    end

    test "opens no window when the lynch lands on someone other than the hunter (rule 5)" do
      %{game: game, day: day} = day_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      target = generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :werewolf))

      Games.create_action!(day.id, hunter.id, target.id, :vote, authorize?: false)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert is_nil(resolved.pending_hunter_id)
      assert is_nil(resolved.hunter_deadline_at)
      assert Games.get_player!(hunter.id, authorize?: false).alive == true
    end

    test "opens no window when the hunter's own lynch finishes the game (rule 4)" do
      %{game: game, day: day} = day_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      werewolf = generate(player(game_id: game.id, role: :werewolf))

      Games.create_action!(day.id, werewolf.id, hunter.id, :vote, authorize?: false)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.state == :finished
      assert is_nil(resolved.pending_hunter_id)
      assert is_nil(resolved.hunter_deadline_at)
    end
  end
end
