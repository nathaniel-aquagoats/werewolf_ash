defmodule WerewolfAsh.Games.Game.Changes.AnnounceDuskTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers

  alias WerewolfAsh.Games

  @now ~U[2026-06-15 20:00:00Z]

  defp vote!(ctx, voter, target) do
    Games.create_action!(ctx.phase.id, voter.id, target.id, :vote, authorize?: false)
  end

  test "lynched, with the role and cause lynched, at the action's now, and night is starting" do
    ctx = day_game()
    vote!(ctx, ctx.villager, ctx.victim)
    vote!(ctx, ctx.seer, ctx.victim)

    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert [dusk] = of_kind(ctx.game, :dusk)
    assert dusk.lynch_outcome == :lynched
    assert dusk.night_starting
    assert DateTime.compare(dusk.announced_at, @now) == :eq
    assert [%{player_id: id, role: :villager, cause: :lynched}] = dusk.deaths
    assert id == ctx.victim.id
    refute is_nil(Games.get_player!(ctx.victim.id, authorize?: false).death_announced_at)
  end

  test "a tie is no_lynch with no deaths, and the notice still says night is starting" do
    ctx = day_game()
    vote!(ctx, ctx.villager, ctx.victim)
    vote!(ctx, ctx.seer, ctx.villager)

    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert [%{lynch_outcome: :no_lynch, deaths: [], night_starting: true}] =
             of_kind(ctx.game, :dusk)
  end

  test "no votes is no_lynch" do
    ctx = day_game()

    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert [%{lynch_outcome: :no_lynch, deaths: []}] = of_kind(ctx.game, :dusk)
  end

  test "a lynch that finishes the game says night is not starting, and a game_over follows" do
    ctx = day_game()
    vote!(ctx, ctx.villager, ctx.wolf)
    vote!(ctx, ctx.seer, ctx.wolf)

    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert [%{lynch_outcome: :lynched, night_starting: false}] = of_kind(ctx.game, :dusk)
    assert [%{kind: :dusk}, %{kind: :game_over, winner: :village}] = announcements(ctx.game)
  end

  test "a player who died earlier is neither the lynched one nor listed" do
    ctx = day_game()
    kill_all!([ctx.victim])

    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert [%{lynch_outcome: :no_lynch, deaths: []}] = of_kind(ctx.game, :dusk)
    assert is_nil(Games.get_player!(ctx.victim.id, authorize?: false).death_announced_at)
  end
end
