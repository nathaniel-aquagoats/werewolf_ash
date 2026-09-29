defmodule WerewolfAsh.Games.Action.Actions.CastActionTest do
  @moduledoc """
  `Games.cast_vote/3`, `cast_kill/3`, `cast_investigation/3`,
  `cast_protection/3` and `cast_shot/3` (rules 14-16, 18,
  werewolf_ash-27w.3): each resolves the caller's own seat and the game's
  open phase, then lands the matching `Action`, surfacing the inner call's
  own errors unchanged.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]

  defp started_game do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))
    generate_many(player(game_id: game.id), 4)
    game = Games.start_game!(game, %{now: @start}, actor: owner)

    players =
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> Map.new(&{&1.role, &1})

    %{game: game, players: players}
  end

  defp actor_for(player), do: %{id: player.user_id}

  defp force_pending_hunter(game, hunter_id) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(
      :hunter_deadline_at,
      DateTime.add(DateTime.utc_now(), 3600, :second)
    )
    |> Ash.update!()
  end

  describe "cast_vote/3" do
    setup do
      started_game()
    end

    test "lands the vote for the caller's own seat in the open day", %{game: game, players: p} do
      action = Games.cast_vote!(game.id, p.villager.id, actor: actor_for(p.villager))

      assert action.type == :vote
      assert action.actor_id == p.villager.id
      assert action.target_id == p.villager.id
    end

    test "casting again recasts the same row with the new target (qss.21)", %{
      game: game,
      players: p
    } do
      first = Games.cast_vote!(game.id, p.villager.id, actor: actor_for(p.villager))
      second = Games.cast_vote!(game.id, p.hunter.id, actor: actor_for(p.villager))

      assert second.id == first.id
      assert second.target_id == p.hunter.id
    end

    test "a dead voter gets the existing not-alive error on actor_id", %{game: game, players: p} do
      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.cast_vote(game.id, p.hunter.id, actor: actor_for(p.villager))
    end

    test "a target seated in another game gets ActorAndTargetInGame on target_id", %{
      game: game,
      players: p
    } do
      outsider = generate(player(game_id: generate(game()).id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.cast_vote(game.id, outsider.id, actor: actor_for(p.villager))
    end

    test "no actor is refused" do
      %{game: game, players: p} = started_game()
      assert {:error, %Ash.Error.Forbidden{}} = Games.cast_vote(game.id, p.villager.id)
    end
  end

  describe "cast_kill/3" do
    setup do
      started_game()
    end

    test "the pack's kill lands for the caller's own seat at night", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})

      action = Games.cast_kill!(night.id, p.villager.id, actor: actor_for(p.werewolf))

      assert action.type == :kill
      assert action.actor_id == p.werewolf.id
    end

    test "a villager caller gets the existing role error", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{}} =
               Games.cast_kill(night.id, p.werewolf.id, actor: actor_for(p.villager))
    end

    test "a second kill the same night is refused (one-kill identity)", %{
      game: game,
      players: p
    } do
      night = Games.end_day!(game, %{now: @dusk})

      Games.cast_kill!(night.id, p.villager.id, actor: actor_for(p.werewolf))

      assert {:error, %Ash.Error.Invalid{}} =
               Games.cast_kill(night.id, p.hunter.id, actor: actor_for(p.werewolf))
    end

    test "no actor is refused", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})
      assert {:error, %Ash.Error.Forbidden{}} = Games.cast_kill(night.id, p.villager.id)
    end
  end

  describe "cast_investigation/3" do
    setup do
      started_game()
    end

    test "the seer's investigation lands with a computed result", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})

      action = Games.cast_investigation!(night.id, p.werewolf.id, actor: actor_for(p.seer))

      assert action.result == %{"is_werewolf" => true}
    end

    test "a non-seer caller gets the existing role error", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{}} =
               Games.cast_investigation(night.id, p.werewolf.id, actor: actor_for(p.villager))
    end

    test "no actor is refused", %{game: game, players: p} do
      night = Games.end_day!(game, %{now: @dusk})
      assert {:error, %Ash.Error.Forbidden{}} = Games.cast_investigation(night.id, p.werewolf.id)
    end
  end

  describe "cast_protection/3" do
    setup do
      started_game()
    end

    test "the bodyguard's protection lands for the caller's own seat", %{game: game, players: p} do
      action = Games.cast_protection!(game.id, p.villager.id, actor: actor_for(p.bodyguard))

      assert action.type == :protect
      assert action.target_id == p.villager.id
    end

    test "a non-bodyguard caller gets the existing role error", %{game: game, players: p} do
      assert {:error, %Ash.Error.Invalid{}} =
               Games.cast_protection(game.id, p.villager.id, actor: actor_for(p.villager))
    end

    test "no actor is refused", %{game: game, players: p} do
      assert {:error, %Ash.Error.Forbidden{}} = Games.cast_protection(game.id, p.villager.id)
    end
  end

  describe "cast_shot/3" do
    setup do
      started_game()
    end

    test "works for the pending hunter", %{game: game, players: p} do
      Games.update_player!(p.hunter, %{alive: false})
      game = force_pending_hunter(game, p.hunter.id)

      action = Games.cast_shot!(game.id, p.villager.id, actor: actor_for(p.hunter))

      assert action.type == :shoot
      assert action.actor_id == p.hunter.id
    end

    test "is refused for anyone else, on actor_id", %{game: game, players: p} do
      Games.update_player!(p.hunter, %{alive: false})
      game = force_pending_hunter(game, p.hunter.id)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.cast_shot(game.id, p.villager.id, actor: actor_for(p.villager))
    end

    test "no actor is refused", %{game: game, players: p} do
      Games.update_player!(p.hunter, %{alive: false})
      game = force_pending_hunter(game, p.hunter.id)

      assert {:error, %Ash.Error.Forbidden{}} = Games.cast_shot(game.id, p.villager.id)
    end
  end

  describe "rule 13 - no open phase" do
    test "a lobby game refuses on :game_id and writes no row" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      seat = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :game_id}]}} =
               Games.cast_vote(game.id, seat.id, actor: actor_for(seat))

      assert Games.list_actions!(authorize?: false) == []
    end
  end
end
