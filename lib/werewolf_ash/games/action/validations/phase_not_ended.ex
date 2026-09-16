defmodule WerewolfAsh.Games.Action.Validations.PhaseNotEnded do
  @moduledoc """
  Rejects an action whose `phase_id` names a phase that has already ended
  (`ended_at` is not `nil`) — rule 4. Backs the "voting has closed" check
  for a `:vote` and the "night has started" check for a `:protect`, on both
  a first `:create` and a recast (Assumption 2): there is no reliable way,
  before the database is touched, to tell a first attempt from a recast, so
  the same check applies to both.

  Runs on `Ash.Changeset` (guarded by `where:` for `:vote`/`:protect` on
  `:create`) and, unconditionally, on `Ash.ActionInput` (`:withdraw`, rule
  8) — the same dual-subject handling `ActorAlive` needs, for the same
  reason, including the `supports/1` override below.

  Loads the `Phase` unauthorized (`authorize?: false`), matching
  `ActorAlive`'s own stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.ActionInput
  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput]

  @impl true
  def validate(%Changeset{} = changeset, _opts, _context) do
    check(Changeset.get_attribute(changeset, :phase_id))
  end

  def validate(%ActionInput{} = input, _opts, _context) do
    check(ActionInput.get_argument(input, :phase_id))
  end

  defp check(nil), do: :ok

  defp check(phase_id) do
    case Games.get_phase(phase_id, authorize?: false) do
      {:ok, %{ended_at: nil}} -> :ok
      {:ok, _ended} -> {:error, field: :phase_id, message: "the phase has already ended"}
      _ -> :ok
    end
  end
end
