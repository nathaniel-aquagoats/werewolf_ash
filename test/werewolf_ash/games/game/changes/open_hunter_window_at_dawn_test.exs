defmodule WerewolfAsh.Games.Game.Changes.OpenHunterWindowAtDawnTest do
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

  defp force_pending_hunter(game, hunter_id) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, DateTime.utc_now())
    |> Ash.update!()
  end

  defp night_game do
    game = force_state(generate(game()), :night)
    night = generate(phase(game_id: game.id, kind: :night, number: 1))
    %{game: game, night: night}
  end

  # Stages all three of `:end_night`'s changes at once, the same way
  # ResolveNightWinTest's own `stage_hooks/2` does, registering
  # `AdvancePhase`, `ResolveNightWin` and this module's own hook, in order.
  defp stage_hooks(game, now) do
    changeset = Changeset.for_update(game, :end_night, %{now: now}, authorize?: false)
    assert changeset.valid?
    assert [advance_hook, resolve_hook, window_hook | _] = changeset.after_action
    {changeset, advance_hook, resolve_hook, window_hook}
  end

  # Runs the dawn win check (the two hooks registered ahead of this module's
  # own), returning what this module's own hook then sees. `AdvancePhase`'s
  # real hook - unlike the stand-in `game` this test drives it with - runs
  # against a `game` the primary `:end_night` UPDATE has already
  # transitioned to `:day`; passing `%{game | state: :day}` as its own
  # second argument reproduces that for this module's own state check,
  # exactly as `ResolveNightWinTest`'s own `stage_hooks/2` reproduces it for
  # `ResolveNightWin`'s untouched-`:night`-from-state needs.
  defp run_up_to_window(game) do
    {changeset, advance_hook, resolve_hook, window_hook} = stage_hooks(game, @now)
    assert {:ok, after_advance} = advance_hook.(changeset, %{game | state: :day})
    assert {:ok, after_resolve} = resolve_hook.(changeset, after_advance)
    {changeset, after_resolve, window_hook}
  end

  describe "change/3 (staged like ResolveNightWinTest's own stage_hooks/2)" do
    test "opens the window at dawn for a hunter killed in the night, deadline now + 1h (rule 7)" do
      %{game: game} = night_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))
      Games.update_player!(hunter, %{alive: false}, authorize?: false)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.pending_hunter_id == hunter.id

      assert DateTime.compare(resolved.hunter_deadline_at, DateTime.add(@now, 3600, :second)) ==
               :eq
    end

    test "opens no window once the hunter already holds a :shoot row" do
      %{game: game, night: night} = night_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      villager1 = generate(player(game_id: game.id, role: :villager))
      _villager2 = generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :werewolf))

      # Simulates an earlier, already-spent window: the hunter shoots while
      # their own pointer is open, which also clears it (rule 14) - by the
      # time this same night's wolves kill them too, a `:shoot` row already
      # exists for them. villager2 keeps the dawn count away from parity, so
      # this test exercises the shoot-row exclusion specifically, not rule
      # 8's separate "the game finished" case.
      force_pending_hunter(game, hunter.id)
      Games.create_action!(night.id, hunter.id, villager1.id, :shoot, authorize?: false)
      Games.update_player!(hunter, %{alive: false}, authorize?: false)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.state == :day
      assert is_nil(resolved.pending_hunter_id)
    end

    test "opens no window when one is already open" do
      %{game: game} = night_game()

      hunter = generate(player(game_id: game.id, role: :hunter))
      generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))
      Games.update_player!(hunter, %{alive: false}, authorize?: false)
      game = force_pending_hunter(game, hunter.id)

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.pending_hunter_id == hunter.id
    end

    test "opens no window when the dawn win check finishes the game (rule 8)" do
      %{game: game} = night_game()

      generate(player(game_id: game.id, role: :werewolf))

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert resolved.state == :finished
      assert is_nil(resolved.pending_hunter_id)
    end

    test "opens no window while the dealt hunter is still alive (rule 8)" do
      %{game: game} = night_game()

      generate(player(game_id: game.id, role: :hunter))
      generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))

      {changeset, after_resolve, window_hook} = run_up_to_window(game)

      assert {:ok, resolved} = window_hook.(changeset, after_resolve)

      assert is_nil(resolved.pending_hunter_id)
    end
  end
end
