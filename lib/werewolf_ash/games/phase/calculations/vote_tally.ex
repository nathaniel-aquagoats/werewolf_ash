defmodule WerewolfAsh.Games.Phase.Calculations.VoteTally do
  @moduledoc """
  Backs `WerewolfAsh.Games.Phase`'s `:vote_tally` calculation
  (werewolf_ash-qss.16 rule 1): the running tally of a day phase's `:vote`
  `WerewolfAsh.Games.Action` rows, one uniform shape for every reader — a map
  from target player id to a list of `%{voter_id:, counts:}` entries — which
  a given reader's own seat then narrows differently (rule 10).

  ## Settled decision: open ballot

  (Assumption 1, recorded here because a coder cannot write it to
  `CLAUDE.md` directly — `protect-pipeline.py` refuses that write, and the
  bead pipeline reserves `CLAUDE.md` edits for the main tree.)

  The day vote is an open ballot, watched live and updated instantly. A
  living game member sees only the votes that currently count — each living
  voter's current vote for a living target — plus their own vote even after
  it stops counting, marked as such, visible to no other living player. A
  dead game member sees every currently cast vote in the phase, including
  one from a since-dead voter or naming a since-dead target, each marked
  whether it currently counts — the dead see everything, as spectators in an
  afterlife. The wolves' night kill is never shown to living non-wolves, and
  never surfaces through the tally either way; only the day vote is open.

  ## Authorization (rule 1)

  This calculation performs its own, ordinary, top-level authorized read of
  `WerewolfAsh.Games.Action` inside `calculate/3` — never a `load/3`
  relationship dependency, which in this Ash version is always authorized
  with `authorize?: false` regardless of the caller's own actor/authorize?
  (see the bead's rule 1 for the full citation trail). Visibility of the
  underlying `:vote` rows is entirely inherited from `Action`'s own read
  policy (werewolf_ash-27w.2 rule 8); this module adds no authorization of
  its own. It does add two pieces of its own logic on top of that read,
  neither of which is authorization: (a) filtering the read rows to a living
  voter and a living target before handing them to
  `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` (qss.5, reused
  unmodified) to decide each entry's `counts` flag — mirroring, not reusing,
  the identical filter `ResolveLynch` applies for its own purpose; and (b)
  looking up the reading actor's own `Player.alive` seat in the phase's game
  to decide which subset of the uniform map they are shown.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  alias Ash.Context
  alias Ash.Query
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Reactors.ResolveLynch

  @impl true
  def calculate(phases, _opts, context) do
    phase_ids = Enum.map(phases, & &1.id)
    votes_by_phase = phase_ids |> read_votes(context) |> Enum.group_by(& &1.phase_id)

    Enum.map(phases, fn phase ->
      votes_by_phase
      |> Map.get(phase.id, [])
      |> build_entries()
      |> narrow(reader_view(context.actor, phase.game_id))
    end)
  end

  # Rule 1's own, ordinary, top-level authorized read of `Action` — passing
  # `Ash.Context.to_opts(context)` unchanged carries the calculation's actual
  # `actor`/`authorize?` through exactly as they would `Games.list_actions`.
  # No `load/3` relationship dependency is declared anywhere in this module
  # (the default no-op `use Ash.Resource.Calculation` already provides is
  # correct here); this is a query-level load on this explicit read instead,
  # which authorizes the normal way.
  defp read_votes([], _context), do: []

  defp read_votes(phase_ids, context) do
    query =
      Action
      |> Query.filter(phase_id in ^phase_ids and type == :vote)
      |> Query.load([:actor, :target])

    Games.list_actions!(Keyword.merge(Context.to_opts(context), query: query))
  end

  # Rules 1, 2, 4: build the one uniform map, %{target_id => [%{voter_id:,
  # counts:}]}, from every :vote row in the phase's group, by handing the
  # living-voter/living-target subset to `ResolveLynch.tally/1` (qss.5,
  # unmodified) and marking every row by whether it appears in that result.
  defp build_entries(votes) do
    counting_pairs =
      votes
      |> Enum.filter(&(&1.actor.alive and &1.target.alive))
      |> ResolveLynch.tally()
      |> Enum.flat_map(fn {target_id, voter_ids} -> Enum.map(voter_ids, &{target_id, &1}) end)
      |> MapSet.new()

    Enum.group_by(votes, & &1.target_id, fn vote ->
      %{
        voter_id: vote.actor_id,
        counts: MapSet.member?(counting_pairs, {vote.target_id, vote.actor_id})
      }
    end)
  end

  # Rule 10: which view a reader gets is decided once, by their own seat in
  # the phase's game — never by anything about the individual votes. No seat
  # at all, including no actor, yields `:none` (rule 5).
  defp reader_view(nil, _game_id), do: :none

  defp reader_view(actor, game_id) do
    case Games.list_players!(
           query: [filter: [game_id: game_id, user_id: actor.id]],
           authorize?: false
         ) do
      [%{alive: true, id: player_id}] -> {:living, player_id}
      [%{alive: false}] -> :dead
      [] -> :none
    end
  end

  # Rule 9: a dead reader's view is rule 1's map, entirely unfiltered.
  defp narrow(entries, :dead), do: entries

  # Rules 5, 10: no seat at all (including no actor) is always `%{}`, never a
  # fabricated view.
  defp narrow(_entries, :none), do: %{}

  # Rule 4: a living reader keeps only `counts: true` entries, plus their own
  # entry even when it is `counts: false` — dropping a target left with no
  # entries at all under that combined narrowing entirely, as a key.
  defp narrow(entries, {:living, player_id}) do
    entries
    |> Map.new(fn {target_id, details} ->
      {target_id, Enum.filter(details, &(&1.counts or &1.voter_id == player_id))}
    end)
    |> Enum.reject(fn {_target_id, details} -> details == [] end)
    |> Map.new()
  end
end
