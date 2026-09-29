defmodule WerewolfAsh.Games.Action.Actions.WithdrawOwn do
  @moduledoc """
  Implements `Action`'s `:withdraw_own_vote` and `:withdraw_own_protection`
  generic actions (rules 17, 17a, werewolf_ash-27w.3): resolves the
  caller's own seat and the game's open phase (`CallerResolution`, rules
  11-13), refuses on `:game_id` unless that open phase is a `:day` (rule
  17a - a call at night, including the night that opens at dusk, is
  refused rather than the silent no-op `Games.withdraw_action/4` would
  otherwise give), then calls `Games.withdraw_action/4` as the caller with
  the `type` this instance is configured for (`:vote` or `:protect`).
  `:withdraw`'s own rules (rules 6-9) are unchanged and still decide
  everything else.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias Ash.Error.Changes.InvalidArgument
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.CallerResolution

  @impl true
  def run(input, opts, context) do
    type = Keyword.fetch!(opts, :type)
    game_id = ActionInput.get_argument(input, :game_id)
    actor = context.actor

    with {:ok, seat, phase} <- CallerResolution.resolve_seat_and_phase(game_id, actor),
         :ok <- require_day(phase) do
      Games.withdraw_action(phase.id, seat.id, type, actor: actor)
    end
  end

  defp require_day(%{kind: :day}), do: :ok

  defp require_day(_phase) do
    {:error,
     InvalidArgument.exception(
       field: :game_id,
       message: "a vote or protection can only be withdrawn while the day is open"
     )}
  end
end
