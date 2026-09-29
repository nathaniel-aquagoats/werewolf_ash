defmodule WerewolfAsh.Games.Phase.Calculations.VoteTallyTest do
  @moduledoc """
  Direct unit tests on `VoteTally.calculate/3` (werewolf_ash-qss.16 rule 1),
  using real, persisted `Phase`/`Action`/`Player` rows and a real actor
  context, never a preloaded in-memory struct: the whole point of rule 1's
  design is that the calculation performs its own authorized read, so a test
  handing `calculate/3` an already-populated struct would never exercise
  that read at all.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Resource.Calculation.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Phase
  alias WerewolfAsh.Games.Phase.Calculations.VoteTally
  alias WerewolfAsh.Games.Reactors.ResolveLynch

  defp actor_for(player), do: %{id: player.user_id}

  defp context(actor, authorize? \\ true) do
    %Context{
      actor: actor,
      authorize?: authorize?,
      resource: Phase,
      domain: Games,
      type: :map,
      constraints: [],
      arguments: %{},
      source_context: %{}
    }
  end

  defp vote!(phase, actor, target),
    do: Games.create_action!(phase.id, actor.id, target.id, :vote, authorize?: false)

  defp normalize(tally) do
    Map.new(tally, fn {target_id, entries} ->
      {target_id, MapSet.new(entries, &{&1.voter_id, &1.counts})}
    end)
  end

  describe "calculate/3" do
    test "a living game member sees only currently-counting entries, matching ResolveLynch.tally/1; a non-member gets %{} (rules 1, 2, 4, 5)" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      villager = generate(player(game_id: game.id, role: :villager))
      target1 = generate(player(game_id: game.id, role: :villager))
      target2 = generate(player(game_id: game.id, role: :villager))
      reader = generate(player(game_id: game.id, role: :villager))

      # a :protect row alongside the :vote rows must never reach the tally.
      Games.create_action!(day.id, bodyguard.id, target1.id, :protect, authorize?: false)
      vote!(day, villager, target1)
      vote!(day, reader, target2)

      [result] = VoteTally.calculate([day], [], context(actor_for(reader)))

      alive_votes =
        Games.list_actions!(
          load: [:actor, :target],
          query: [filter: [phase_id: day.id, type: :vote]],
          authorize?: false
        )

      expected =
        alive_votes
        |> ResolveLynch.tally()
        |> Map.new(fn {target_id, voter_ids} ->
          {target_id, MapSet.new(voter_ids, &{&1, true})}
        end)

      assert normalize(result) == expected

      # this is the specific case a load/3 relationship dependency (always
      # authorize?: false) would have gotten wrong: a genuine non-member.
      outsider = generate(user())
      assert [%{}] = VoteTally.calculate([day], [], context(%{id: outsider.id}))
    end

    test "no seat at all, including no actor, returns %{} regardless of which view would otherwise apply (rule 5, 10)" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      villager = generate(player(game_id: game.id, role: :villager))
      target = generate(player(game_id: game.id, role: :villager))

      vote!(day, villager, target)

      assert [%{}] = VoteTally.calculate([day], [], context(nil))
    end

    test "a phase with no :vote rows returns %{} for a member, whether a night's :kill row or a day before any vote (rules 2, 3)" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      night = generate(phase(game_id: game.id, kind: :night, number: 2))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      victim = generate(player(game_id: game.id, role: :villager))
      reader = generate(player(game_id: game.id, role: :villager))

      Games.create_kill_action!(night.id, wolf.id, victim.id, authorize?: false)

      assert [%{}] = VoteTally.calculate([day], [], context(actor_for(reader)))
      assert [%{}] = VoteTally.calculate([night], [], context(actor_for(reader)))
    end

    test "the same seeded votes narrow differently for a living non-voter, a dead reader, and the living reader who cast a now-non-counting vote (rules 4, 6, 9, 10)" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      target_a = generate(player(game_id: game.id, role: :villager))
      target_b = generate(player(game_id: game.id, role: :villager))
      voter_dead = generate(player(game_id: game.id, role: :villager))
      voter_ok = generate(player(game_id: game.id, role: :villager))
      voter_b = generate(player(game_id: game.id, role: :villager))
      reader_living = generate(player(game_id: game.id, role: :villager))
      reader_dead = generate(player(game_id: game.id, role: :villager))

      # target_a gets one vote that will stop counting (its voter dies) and
      # one that keeps counting; target_b gets one vote naming a target who
      # dies (so it stops counting from the voter's side instead).
      vote!(day, voter_dead, target_a)
      vote!(day, voter_ok, target_a)
      vote!(day, voter_b, target_b)

      Games.update_player!(voter_dead, %{alive: false})
      Games.update_player!(target_b, %{alive: false})
      Games.update_player!(reader_dead, %{alive: false})

      [living_view] = VoteTally.calculate([day], [], context(actor_for(reader_living)))
      [dead_view] = VoteTally.calculate([day], [], context(actor_for(reader_dead)))
      [own_vote_view] = VoteTally.calculate([day], [], context(actor_for(voter_b)))

      # a living non-voter sees only the entries that currently count, and a
      # target named only by a non-counting vote is absent as a key entirely.
      assert normalize(living_view) == %{target_a.id => MapSet.new([{voter_ok.id, true}])}
      refute Map.has_key?(living_view, target_b.id)

      # a dead reader sees every row currently on the books, correctly marked.
      assert normalize(dead_view) == %{
               target_a.id => MapSet.new([{voter_dead.id, false}, {voter_ok.id, true}]),
               target_b.id => MapSet.new([{voter_b.id, false}])
             }

      # the living voter whose own vote stopped counting still sees it,
      # alongside every other counting entry, unlike any other living reader.
      assert normalize(own_vote_view) == %{
               target_a.id => MapSet.new([{voter_ok.id, true}]),
               target_b.id => MapSet.new([{voter_b.id, false}])
             }
    end
  end
end
