defmodule WerewolfAsh.Games.AnnouncedVisibilityTest do
  @moduledoc """
  werewolf_ash-qss.19 rules 18-22, 25-26: what announced and unannounced
  deaths change in `Player.role`, `visible_alive`, the vote views and the
  seer's reach.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers
  import WerewolfAsh.Generators

  alias Ash.ForbiddenField
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Player

  @now ~U[2026-06-16 08:00:00Z]

  defp role_seen(target, reader) do
    Ash.get!(Player, target.id, actor: actor_for(reader)).role
  end

  defp visible_alive(target, reader) do
    actor = reader && actor_for(reader)

    Player
    |> Ash.get!(target.id, load: :visible_alive, actor: actor, authorize?: false)
    |> Map.fetch!(:visible_alive)
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

  describe "Player.visible_alive (rule 19)" do
    setup do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)
      ctx
    end

    test "true for a living non-wolf reader on an unannounced night victim", ctx do
      assert visible_alive(ctx.victim, ctx.villager)
      assert visible_alive(ctx.victim, ctx.seer)
    end

    test "false for the victim's own seat, a wolf and a dead reader", ctx do
      refute visible_alive(ctx.victim, ctx.victim)
      refute visible_alive(ctx.victim, ctx.wolf)

      kill_all!([ctx.villager])
      refute visible_alive(ctx.victim, ctx.villager)
    end

    test "false once announced, in a finished game, and with no actor", ctx do
      refute visible_alive(ctx.victim, nil)

      Games.finish_game!(ctx.game, :wolves, authorize?: false)
      refute visible_alive(ctx.victim, ctx.villager)
    end

    test "false after the victim is announced", ctx do
      assert visible_alive(ctx.victim, ctx.villager)
      announce_death!(Games.get_player!(ctx.victim.id, authorize?: false))
      refute visible_alive(ctx.victim, ctx.villager)
    end

    test "true for a living player, whoever reads", ctx do
      assert visible_alive(ctx.villager, ctx.wolf)
      assert visible_alive(ctx.villager, ctx.victim)
      assert visible_alive(ctx.villager, nil)
    end
  end

  describe "vote views (rule 21)" do
    setup do
      ctx = day_game()
      # the victim voted for the villager, and the villager voted for the victim
      vote_for_victim =
        Games.create_action!(ctx.phase.id, ctx.villager.id, ctx.victim.id, :vote,
          authorize?: false
        )

      vote_by_victim =
        Games.create_action!(ctx.phase.id, ctx.victim.id, ctx.villager.id, :vote,
          authorize?: false
        )

      kill_all!([ctx.victim])
      Map.merge(ctx, %{vote_for_victim: vote_for_victim, vote_by_victim: vote_by_victim})
    end

    defp readable?(vote, reader) do
      match?({:ok, _}, Games.get_action(vote.id, actor: actor_for(reader)))
    end

    defp tally(ctx, reader) do
      Games.get_phase!(ctx.phase.id, load: :vote_tally, actor: actor_for(reader)).vote_tally
    end

    test "a living reader still reads votes from and for an unannounced dead player", ctx do
      assert readable?(ctx.vote_for_victim, ctx.seer)
      assert readable?(ctx.vote_by_victim, ctx.seer)

      assert tally(ctx, ctx.seer) == %{
               ctx.victim.id => [%{voter_id: ctx.villager.id, counts: true}],
               ctx.villager.id => [%{voter_id: ctx.victim.id, counts: true}]
             }
    end

    test "a living reader loses them once the death is announced", ctx do
      announce_death!(Games.get_player!(ctx.victim.id, authorize?: false))

      refute readable?(ctx.vote_for_victim, ctx.seer)
      refute readable?(ctx.vote_by_victim, ctx.seer)
      assert tally(ctx, ctx.seer) == %{}
      # the voter's own vote is still theirs, marked as not counting
      assert tally(ctx, ctx.villager) == %{
               ctx.victim.id => [%{voter_id: ctx.villager.id, counts: false}]
             }
    end

    test "a dead reader sees every vote with the real counts flag, announced or not", ctx do
      kill_all!([ctx.hunter])

      real = %{
        ctx.victim.id => [%{voter_id: ctx.villager.id, counts: false}],
        ctx.villager.id => [%{voter_id: ctx.victim.id, counts: false}]
      }

      assert tally(ctx, ctx.hunter) == real
      assert readable?(ctx.vote_for_victim, ctx.hunter)

      announce_death!(Games.get_player!(ctx.victim.id, authorize?: false))
      assert tally(ctx, ctx.hunter) == real
    end
  end

  describe "the seer and a night victim (rules 25-26)" do
    defp investigate(ctx, target) do
      Games.create_action(ctx.phase.id, ctx.seer.id, target.id, :investigate,
        actor: actor_for(ctx.seer)
      )
    end

    defp target_field_error?({:error, %{errors: errors}}) do
      Enum.any?(errors, &(Map.get(&1, :field) == :target_id))
    end

    test "the seer investigates a night victim before dawn, gets the real answer, once" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert {:ok, action} = investigate(ctx, ctx.victim)
      assert action.result == %{"is_werewolf" => false}

      assert {:error, _} = investigate(ctx, ctx.villager)
    end

    test "the answer is the victim's real werewolf yes/no" do
      ctx = night_game()

      other_wolf =
        generate(player(game_id: ctx.game.id, role: :werewolf))

      night_kill!(ctx.phase, ctx.wolf, other_wolf)

      assert {:ok, %{result: %{"is_werewolf" => true}}} = investigate(ctx, other_wolf)
    end

    test "after dawn the same call is refused on :target_id" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)
      Games.end_night!(ctx.game, %{now: @now}, authorize?: false)

      assert ctx |> investigate(ctx.victim) |> target_field_error?()
    end

    test "a player killed with update_player, a lynched or a shot player stay refused" do
      ctx = night_game()
      kill_all!([ctx.victim])
      assert ctx |> investigate(ctx.victim) |> target_field_error?()

      pending_hunter!(ctx.game, ctx.hunter)

      Games.create_action!(ctx.phase.id, ctx.hunter.id, ctx.villager.id, :shoot,
        authorize?: false
      )

      # shot players are announced, and have no kill row anyway
      assert ctx |> investigate(ctx.villager) |> target_field_error?()
    end

    test "a seer killed in the night cannot investigate" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)
      kill_all!([ctx.seer])

      assert {:error, %{errors: errors}} = investigate(ctx, ctx.victim)
      assert Enum.any?(errors, &(Map.get(&1, :field) == :actor_id))
    end

    test ":vote, :shoot and :kill refuse a night victim with no exception" do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      assert ctx.phase.id
             |> Games.create_action(ctx.villager.id, ctx.victim.id, :vote, authorize?: false)
             |> target_field_error?()

      pending_hunter!(ctx.game, ctx.hunter)

      assert ctx.phase.id
             |> Games.create_action(ctx.hunter.id, ctx.victim.id, :shoot, authorize?: false)
             |> target_field_error?()

      second_night =
        generate(phase(game_id: ctx.game.id, kind: :night, number: 2))

      assert second_night.id
             |> Games.create_kill_action(ctx.wolf.id, ctx.victim.id, authorize?: false)
             |> target_field_error?()
    end
  end
end
