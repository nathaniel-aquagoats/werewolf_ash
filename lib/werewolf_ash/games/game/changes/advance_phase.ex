defmodule WerewolfAsh.Games.Game.Changes.AdvancePhase do
  @moduledoc """
  Moves a game into its next phase.

  Transitions the state machine to `:day` or `:night` (with `to: :by_clock`,
  to whichever window the game's local time is in at `:now`), sets
  `phase_ends_at` to the next window boundary and, once the game row is
  written, closes the open `Phase` and opens the next one in the same
  transaction. Every instant derives from the action's `:now` argument.

  Resolution (votes, kills, win checks) is deliberately not here; later
  reactors run before this change hands the game to the next phase.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.Clock

  @targets [:day, :night, :by_clock]

  @impl true
  def init(opts) do
    if opts[:to] in @targets do
      {:ok, opts}
    else
      {:error, "`to` must be one of #{inspect(@targets)}, got: #{inspect(opts[:to])}"}
    end
  end

  @impl true
  def change(changeset, opts, context) do
    now = Changeset.get_argument(changeset, :now)
    game = changeset.data

    with {:ok, kind} <- target(opts[:to], game, now),
         {:ok, ends_at} <- Clock.next_boundary(game, kind, now) do
      changeset
      |> AshStateMachine.transition_state(kind)
      |> Changeset.force_change_attribute(:phase_ends_at, ends_at)
      |> Changeset.after_action(fn _changeset, game ->
        open_next_phase(game, kind, now, Context.to_opts(context))
      end)
    else
      {:error, reason} ->
        Changeset.add_error(changeset,
          field: :timezone,
          message: "cannot compute the next phase boundary: %{reason}",
          vars: [reason: inspect(reason)]
        )
    end
  end

  defp target(:by_clock, game, now), do: Clock.window_at(game, now)
  defp target(kind, _game, _now), do: {:ok, kind}

  defp open_next_phase(game, kind, now, opts) do
    %{current_phase: open_phase, last_phase_number: last_number} =
      Ash.load!(game, [:current_phase, :last_phase_number], opts)

    with :ok <- close_phase(open_phase, now, opts),
         {:ok, _phase} <-
           Games.create_phase(game.id, kind, (last_number || 0) + 1, %{started_at: now}, opts) do
      {:ok, game}
    end
  end

  defp close_phase(nil, _now, _opts), do: :ok

  defp close_phase(phase, now, opts) do
    with {:ok, _phase} <- Games.update_phase(phase, %{ended_at: now}, opts), do: :ok
  end
end
