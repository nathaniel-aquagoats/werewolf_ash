defmodule WerewolfAsh.Games.Game.Changes.ResolveHunterDeadlineTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @deadline ~U[2026-06-15 21:00:00Z]

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  defp force_pending_hunter(game, hunter_id, deadline) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, deadline)
    |> Ash.update!()
  end

  # A day-phase game with an open window: the dealt hunter is dead and is
  # the game's own pointer, deadline `@deadline`.
  defp open_game do
    game = force_state(generate(game()), :day)
    day = generate(phase(game_id: game.id, kind: :day, number: 1))
    hunter = generate(player(game_id: game.id, role: :hunter))
    Games.update_player!(hunter, %{alive: false}, authorize?: false)
    game = force_pending_hunter(game, hunter.id, @deadline)
    %{game: game, day: day, hunter: hunter}
  end

  defp shoot_rows(game) do
    Games.list_actions!(
      query: [filter: [actor_id: game.pending_hunter_id]],
      authorize?: false
    )
  end

  describe "Games.resolve_hunter_deadline/2 (Game.Changes.ResolveHunterDeadline, rules 16-18)" do
    test "before the deadline, is a silent no-op" do
      %{game: game, hunter: hunter} = open_game()

      resolved =
        Games.resolve_hunter_deadline!(game, %{now: DateTime.add(@deadline, -1, :second)})

      assert resolved.pending_hunter_id == hunter.id
      assert DateTime.compare(resolved.hunter_deadline_at, @deadline) == :eq
      assert Games.list_actions!(query: [filter: [type: :shoot]], authorize?: false) == []
    end

    test "with no window open, is a silent no-op (rule 18)" do
      game = force_state(generate(game()), :day)

      resolved = Games.resolve_hunter_deadline!(game, %{now: DateTime.utc_now()})

      assert is_nil(resolved.pending_hunter_id)
      assert Games.list_actions!(query: [filter: [type: :shoot]], authorize?: false) == []
    end

    test "on a finished game, is a silent no-op" do
      game = force_state(generate(game()), :finished)

      resolved = Games.resolve_hunter_deadline!(game, %{now: DateTime.utc_now()})

      assert is_nil(resolved.pending_hunter_id)
      assert resolved.state == :finished
    end

    test "at or past the deadline, shoots the living player at `pick` modulo the living count, ordered by id (rule 16)" do
      %{game: game, day: day, hunter: hunter} = open_game()

      generate(player(game_id: game.id, role: :villager))

      [first | _] =
        Games.list_living_players!(game.id, query: [sort: [id: :asc]], authorize?: false)

      count =
        length(Games.list_living_players!(game.id, query: [sort: [id: :asc]], authorize?: false))

      # `pick: count` wraps modulo back to index 0, the same target `pick: 0`
      # would choose.
      resolved = Games.resolve_hunter_deadline!(game, %{now: @deadline, pick: count})

      assert Games.get_player!(first.id, authorize?: false).alive == false
      assert is_nil(resolved.pending_hunter_id)
      assert is_nil(resolved.hunter_deadline_at)

      assert [shot] = shoot_rows(game)
      assert shot.actor_id == hunter.id
      assert shot.target_id == first.id
      assert shot.phase_id == day.id
      assert shot.result == %{"killed" => true, "fallback" => true}
    end

    test "wolves are eligible for the fallback shot like anyone else" do
      %{game: game} = open_game()

      werewolf1 = generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :werewolf))
      generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :villager))

      living =
        Games.list_living_players!(game.id, query: [sort: [id: :asc]], authorize?: false)

      wolf_index = Enum.find_index(living, &(&1.id == werewolf1.id))

      resolved = Games.resolve_hunter_deadline!(game, %{now: @deadline, pick: wolf_index})

      assert Games.get_player!(werewolf1.id, authorize?: false).alive == false
      assert resolved.state == :day
    end

    test "the win check runs after the shot and can finish the game" do
      %{game: game} = open_game()

      generate(player(game_id: game.id, role: :werewolf))

      # Only the game() generator's own roleless owner and this one
      # werewolf are left living once the hunter is dead: whichever of the
      # two the fallback lands on, the shot decides the game one way or the
      # other.
      resolved = Games.resolve_hunter_deadline!(game, %{now: @deadline, pick: 0})

      assert resolved.state == :finished
      assert resolved.winner in [:village, :wolves]
      assert is_nil(resolved.pending_hunter_id)
    end

    test "a second run after the window is already spent changes nothing more" do
      %{game: game} = open_game()

      generate(player(game_id: game.id, role: :villager))
      generate(player(game_id: game.id, role: :villager))

      first_resolved = Games.resolve_hunter_deadline!(game, %{now: @deadline, pick: 0})
      assert [_one_shot] = shoot_rows(game)

      second_resolved = Games.resolve_hunter_deadline!(first_resolved, %{now: @deadline, pick: 0})

      assert is_nil(second_resolved.pending_hunter_id)
      assert [_still_one_shot] = shoot_rows(game)
    end
  end
end
