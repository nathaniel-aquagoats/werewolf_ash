defmodule WerewolfAsh.Games.Action.Changes.AnnounceShotTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers

  alias WerewolfAsh.Games

  @now ~U[2026-06-16 08:00:00Z]

  defp shoot(ctx, target),
    do: Games.create_action(ctx.phase.id, ctx.hunter.id, target.id, :shoot, authorize?: false)

  test "a chosen shot is announced at once: only the victim, with role and cause shot, at the wall clock" do
    ctx = night_game()
    night_kill!(ctx.phase, ctx.wolf, ctx.victim)
    pending_hunter!(ctx.game, ctx.hunter)
    before = DateTime.utc_now()

    assert {:ok, _} = shoot(ctx, ctx.villager)

    assert [shot] = of_kind(ctx.game, :shot)
    assert [%{player_id: id, role: :villager, cause: :shot}] = shot.deaths
    assert id == ctx.villager.id
    assert DateTime.compare(shot.announced_at, before) in [:gt, :eq]
    refute is_nil(Games.get_player!(ctx.villager.id, authorize?: false).death_announced_at)
    # the unannounced night victim waits for dawn
    assert is_nil(Games.get_player!(ctx.victim.id, authorize?: false).death_announced_at)
  end

  test "the deadline fallback announces its shot too" do
    ctx = night_game()
    pending_hunter!(ctx.game, ctx.hunter, @now)

    Games.resolve_hunter_deadline!(ctx.game, %{now: @now, pick: 0}, authorize?: false)

    assert [%{deaths: [%{cause: :shot}]}] = of_kind(ctx.game, :shot)
  end

  test "a shot that finishes the game is still announced" do
    ctx = night_game()
    pending_hunter!(ctx.game, ctx.hunter)

    assert {:ok, _} = shoot(ctx, ctx.wolf)

    assert [%{deaths: [%{role: :werewolf}]}] = of_kind(ctx.game, :shot)
    assert [_] = of_kind(ctx.game, :game_over)
  end

  test "a refused shot announces nothing" do
    ctx = night_game()
    # no window open for this hunter
    assert {:error, _} = shoot(ctx, ctx.villager)

    pending_hunter!(ctx.game, ctx.hunter)
    kill_all!([ctx.villager])
    assert {:error, _} = shoot(ctx, ctx.villager)

    assert of_kind(ctx.game, :shot) == []
  end
end
