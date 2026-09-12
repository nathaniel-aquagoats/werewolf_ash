defmodule WerewolfAsh.Games.Action.Changes.ApplyKill do
  @moduledoc """
  The immediate effect of a landed `:kill` (rule 13), once rules 1, 3 and
  11's checks have already passed.

  Looks up the immediately preceding day phase of the same game (the
  `Phase` with the same `game_id`, `kind: :day`, and `number` exactly one
  less than the kill's own phase). If that phase holds a `:protect` action
  naming the same target, the kill is spent: the action row still records
  `result: %{"killed" => false}` and the target's `alive` is left alone.
  Otherwise the target's `alive` is set to `false` and `result` is
  `%{"killed" => true}`. A kill on a game's very first phase (`number: 1`)
  has no preceding day phase to check, so it is never protected.

  Runs as an `after_action` hook, alongside `DealRoles`'s own hook that
  reads and writes a different resource than the one being created.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn _changeset, action ->
      apply_kill(action, Context.to_opts(context))
    end)
  end

  defp apply_kill(action, opts) do
    if protected?(action, opts) do
      Games.update_action(action, %{result: %{"killed" => false}}, opts)
    else
      with {:ok, target} <- Games.get_player(action.target_id, opts),
           {:ok, _target} <- Games.update_player(target, %{alive: false}, opts) do
        Games.update_action(action, %{result: %{"killed" => true}}, opts)
      end
    end
  end

  defp protected?(action, opts) do
    with {:ok, phase} <- Games.get_phase(action.phase_id, opts),
         {:ok, day_phase} <- preceding_day_phase(phase, opts) do
      protects =
        Games.list_actions!(
          Keyword.merge(opts,
            query: [
              filter: [phase_id: day_phase.id, type: :protect, target_id: action.target_id]
            ]
          )
        )

      protects != []
    else
      _ -> false
    end
  end

  defp preceding_day_phase(%{number: 1}, _opts), do: {:error, :no_preceding_phase}

  defp preceding_day_phase(phase, opts) do
    case Games.list_phases!(
           Keyword.merge(opts,
             query: [filter: [game_id: phase.game_id, kind: :day, number: phase.number - 1]]
           )
         ) do
      [day_phase] -> {:ok, day_phase}
      [] -> {:error, :no_preceding_phase}
    end
  end
end
