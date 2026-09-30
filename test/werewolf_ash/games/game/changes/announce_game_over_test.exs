defmodule WerewolfAsh.Games.Game.Changes.AnnounceGameOverTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers

  alias WerewolfAsh.Games

  @now ~U[2026-06-16 08:00:00Z]

  defp assert_one_game_over(game, winner) do
    assert [over] = of_kind(game, :game_over)
    assert over.winner == winner
    assert over.deaths == []
    refute over.night_starting
  end

  defp others(ctx), do: [ctx.seer, ctx.villager, ctx.victim, ctx.hunter]

  test "a direct finish_game announces the winner" do
    %{game: game} = day_game()

    Games.finish_game!(game, :wolves, authorize?: false)

    assert_one_game_over(game, :wolves)
  end

  test "the dusk lynch route" do
    ctx = day_game()
    Games.create_action!(ctx.phase.id, ctx.villager.id, ctx.wolf.id, :vote, authorize?: false)
    Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

    assert_one_game_over(ctx.game, :village)
  end

  test "the dawn win check route" do
    ctx = night_game()
    kill_all!(others(ctx))
    kill_all!(Games.list_players!(query: [filter: [role: nil]], authorize?: false))
    Games.end_night!(ctx.game, %{now: @now}, authorize?: false)

    assert_one_game_over(ctx.game, :wolves)
  end

  test "the wolf kill route" do
    ctx = night_game()
    kill_all!(Games.list_players!(query: [filter: [role: nil]], authorize?: false))
    kill_all!([ctx.seer, ctx.villager, ctx.hunter])
    night_kill!(ctx.phase, ctx.wolf, ctx.victim)

    assert Games.get_game!(ctx.game.id, authorize?: false).state == :finished
    assert_one_game_over(ctx.game, :wolves)
  end

  test "the hunter's shot route" do
    ctx = night_game()
    pending_hunter!(ctx.game, ctx.hunter)
    Games.create_action!(ctx.phase.id, ctx.hunter.id, ctx.wolf.id, :shoot, authorize?: false)

    assert_one_game_over(ctx.game, :village)
  end

  test "the hunter deadline fallback route" do
    ctx = night_game()
    kill_all!(others(ctx))
    kill_all!(Games.list_players!(query: [filter: [role: nil]], authorize?: false))
    pending_hunter!(ctx.game, ctx.hunter, @now)

    Games.resolve_hunter_deadline!(ctx.game, %{now: @now, pick: 0}, authorize?: false)

    assert_one_game_over(ctx.game, :village)
  end
end
