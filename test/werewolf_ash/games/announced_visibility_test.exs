defmodule WerewolfAsh.Games.AnnouncedVisibilityTest do
  @moduledoc """
  werewolf_ash-qss.19 rules 18-19: what announced and unannounced deaths change in
  `Player.role`.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers

  alias Ash.ForbiddenField
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Player

  @now ~U[2026-06-16 08:00:00Z]

  defp role_seen(target, reader) do
    Ash.get!(Player, target.id, actor: actor_for(reader)).role
  end

  describe "Player.role announced grant (rule 18)" do
    test "a night victim's role is hidden from a living villager until announced" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert %ForbiddenField{} = role_seen(ctx.victim, ctx.villager)

      Games.end_night!(ctx.game, %{now: @now}, authorize?: false)

      assert role_seen(ctx.victim, ctx.villager) == :villager
    end

    test "a lynched player's role is readable right after end_day" do
      ctx = day_game()

      for voter <- [ctx.villager, ctx.seer] do
        Games.create_action!(ctx.phase.id, voter.id, ctx.victim.id, :vote, authorize?: false)
      end

      Games.end_day!(ctx.game, %{now: @now}, authorize?: false)

      assert role_seen(ctx.victim, ctx.villager) == :villager
    end

    test "a shot player's role is readable right after the shot" do
      ctx = night_game()
      pending_hunter!(ctx.game, ctx.hunter)
      assert %ForbiddenField{} = role_seen(ctx.villager, ctx.seer)

      Games.create_action!(ctx.phase.id, ctx.hunter.id, ctx.villager.id, :shoot,
        authorize?: false
      )

      assert role_seen(ctx.villager, ctx.seer) == :villager
    end

    test "a dead player who was never announced stays hidden" do
      ctx = night_game()
      kill_all!([ctx.victim])

      assert %ForbiddenField{} = role_seen(ctx.victim, ctx.villager)
    end
  end

  describe "a wolf kill announces nothing (rule 19)" do
    test "before end_night there is no announcement, alive reads false, the role stays forbidden" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert announcements(ctx.game) == []

      assert Games.list_announcements!(ctx.game.id, actor: actor_for(ctx.villager)) == []

      seen = Ash.get!(Player, ctx.victim.id, actor: actor_for(ctx.villager))
      refute seen.alive
      assert %ForbiddenField{} = seen.role
    end
  end
end
