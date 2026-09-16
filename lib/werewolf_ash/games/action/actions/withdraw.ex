defmodule WerewolfAsh.Games.Action.Actions.Withdraw do
  @moduledoc """
  The `:withdraw` action's own lookup-then-destroy-or-no-op logic (rules 6,
  9). Given the `phase_id`, `actor_id` and `type` arguments, deletes the
  actor's existing `:vote`/`:protect` row for that phase and type, if one
  exists. When none exists, changes nothing and raises no error (rule 9).

  By the time this runs, `:withdraw`'s own `ActorAlive` and
  `PhaseNotEnded` validations have already passed, so rule 12's ordering
  (those checks before the "nothing to withdraw" no-op) falls out of the
  generic action's own validate-then-run pipeline, not from anything here.

  Looks up and destroys unauthorized (`authorize?: false`), matching
  `ActorAlive`'s stated reasoning: this is a game rule, not an access
  check — who may call `:withdraw` at all for a given `actor_id` is
  already settled by the action's own policy (rule 11) before `run/3` ever
  executes.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias WerewolfAsh.Games

  @impl true
  def run(input, _opts, _context) do
    phase_id = ActionInput.get_argument(input, :phase_id)
    actor_id = ActionInput.get_argument(input, :actor_id)
    type = ActionInput.get_argument(input, :type)

    case Games.list_actions(
           query: [filter: [phase_id: phase_id, actor_id: actor_id, type: type]],
           authorize?: false
         ) do
      {:ok, [action]} -> Ash.destroy(action, authorize?: false)
      {:ok, []} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
