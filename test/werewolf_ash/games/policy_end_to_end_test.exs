defmodule WerewolfAsh.Games.PolicyEndToEndTest do
  @moduledoc """
  End-to-end acceptance test for werewolf_ash-27w.2: a full game seating a
  villager, a werewolf and a dead villager, read and acted on through the
  domain code interface exactly as each seat's actor would.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  defp actor_for(player), do: %{id: player.user_id}

  test "a villager, a werewolf and a dead villager each see only what their own seat allows" do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))

    villager = generate(player(game_id: game.id))
    werewolf = generate(player(game_id: game.id))
    dead_villager = generate(player(game_id: game.id))
    # a five-plus-player game (rules 8-9 of qss.3's own :start); also the
    # kill's own target below, so the villager stays alive throughout.
    bystander = generate(player(game_id: game.id))

    outsider = generate(user())
    outsider_actor = %{id: outsider.id}

    # rule 3a - an outsider (indeed, anyone but the owner) may not start the
    # game; checked before the owner's own start below actually leaves the
    # lobby, since a later state prevents re-entering :start at all.
    assert {:error, %Ash.Error.Forbidden{}} = Games.start_game(game, actor: outsider_actor)

    # Etc/UTC, default 08:00/20:00 windows: 09:30 lands in day.
    game = Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]}, actor: owner)

    players_by_id =
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> Map.new(&{&1.id, &1})

    # start_game deals roles at random across all five seated players, so
    # every seat gets pinned to :villager except the one meant to be the
    # werewolf - leaving the owner's or bystander's dealt role to chance
    # could otherwise land a second werewolf on one of them, changing the
    # living wolves/non-wolves count enough to decide the game at dusk
    # (rule 8's own end-of-day win check) before the kill below ever runs.
    villager = Games.update_player!(players_by_id[villager.id], %{role: :villager})
    werewolf = Games.update_player!(players_by_id[werewolf.id], %{role: :werewolf})
    bystander = Games.update_player!(players_by_id[bystander.id], %{role: :villager})

    owner_player = Enum.find(Map.values(players_by_id), &(&1.user_id == owner.id))
    Games.update_player!(owner_player, %{role: :villager})

    dead_villager =
      players_by_id[dead_villager.id]
      |> Games.update_player!(%{role: :villager})
      |> Games.update_player!(%{alive: false})

    refute dead_villager.alive

    game = Games.end_day!(game, %{now: ~U[2026-06-15 20:00:00Z]})
    night = Games.get_game!(game.id, load: :current_phase, authorize?: false).current_phase

    kill =
      Games.create_kill_action!(night.id, werewolf.id, bystander.id, authorize?: false)

    village_by_wolf =
      Games.send_message!(game.id, werewolf.id, :village, "hi village",
        actor: actor_for(werewolf)
      )

    wolves_by_wolf =
      Games.send_message!(game.id, werewolf.id, :wolves, "hi wolves", actor: actor_for(werewolf))

    # As the villager: reads the game and roster, own role visible, others
    # hidden; fails to read :kill actions; fails to post in :wolves.
    villager_actor = actor_for(villager)
    assert Games.get_game!(game.id, actor: villager_actor).id == game.id

    roster = Games.list_players!(query: [filter: [game_id: game.id]], actor: villager_actor)
    assert length(roster) == 5

    own_row = Ash.get!(Games.Player, villager.id, actor: villager_actor)
    assert own_row.role == :villager

    wolf_row = Ash.get!(Games.Player, werewolf.id, actor: villager_actor)
    assert %Ash.ForbiddenField{} = wolf_row.role

    assert {:error, %Ash.Error.Invalid{}} = Games.get_action(kill.id, actor: villager_actor)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Games.send_message(game.id, villager.id, :wolves, "sneak", actor: villager_actor)

    assert Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{field: :channel}, &1))

    # As the werewolf: reads fellow wolves' roles and :kill actions, posts
    # in both channels (already done above).
    wolf_actor = actor_for(werewolf)
    assert Games.get_action!(kill.id, actor: wolf_actor).id == kill.id
    assert village_by_wolf.channel == :village
    assert wolves_by_wolf.channel == :wolves

    # An outsider holding no seat: every read comes back empty, and
    # send_message is forbidden (start_game was already checked above).
    assert {:error, %Ash.Error.Invalid{}} = Games.get_game(game.id, actor: outsider_actor)

    assert Games.list_players!(query: [filter: [game_id: game.id]], actor: outsider_actor) ==
             []

    assert Ash.read!(Games.Message, actor: outsider_actor) == []

    assert {:error, %Ash.Error.Forbidden{}} =
             Games.send_message(game.id, villager.id, :village, "hi", actor: outsider_actor)
  end
end
