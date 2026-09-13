defmodule WerewolfAsh.Games.Action.Validations.NoConsecutiveProtect do
  @moduledoc """
  Rejects a `:protect` whose `target_id` matches the same actor's `:protect`
  target from the immediately preceding day phase of the same game (rule
  4) — "the immediately preceding day phase" being the day phase of that
  game with the largest `number` smaller than the current phase's `number`,
  not literally the phase numbered one less (a game can open at night, so
  its first day phase need not be `number: 1`).

  When no earlier day phase of the game exists, or the actor recorded no
  `:protect` action in it, there is nothing to compare against and the
  action is allowed regardless of target.

  Loads `Phase`/`Action` unauthorized (`authorize?: false`), matching
  `ActorAlive`'s own stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    actor_id = Changeset.get_attribute(changeset, :actor_id)
    target_id = Changeset.get_attribute(changeset, :target_id)
    phase_id = Changeset.get_attribute(changeset, :phase_id)

    if is_nil(actor_id) or is_nil(target_id) or is_nil(phase_id) do
      :ok
    else
      check(actor_id, target_id, phase_id)
    end
  end

  defp check(actor_id, target_id, phase_id) do
    with {:ok, phase} <- Games.get_phase(phase_id, authorize?: false),
         {:ok, day_phase} <- preceding_day_phase(phase),
         {:ok, previous_target_id} <- previous_protect_target(day_phase, actor_id),
         true <- previous_target_id == target_id do
      {:error, field: :target_id, message: "may not protect the same player two days in a row"}
    else
      _ -> :ok
    end
  end

  defp preceding_day_phase(phase) do
    case Games.list_phases!(
           query: [
             filter: [game_id: phase.game_id, kind: :day, number: [less_than: phase.number]],
             sort: [number: :desc],
             limit: 1
           ],
           authorize?: false
         ) do
      [day_phase] -> {:ok, day_phase}
      [] -> {:error, :no_preceding_day_phase}
    end
  end

  defp previous_protect_target(day_phase, actor_id) do
    case Games.list_actions!(
           query: [filter: [phase_id: day_phase.id, actor_id: actor_id, type: :protect]],
           authorize?: false
         ) do
      [%{target_id: target_id}] -> {:ok, target_id}
      [] -> {:error, :no_previous_protect}
    end
  end
end
