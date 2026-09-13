defmodule WerewolfAsh.Games.Action.Validations.ActorAndTargetInGame do
  @moduledoc """
  Rejects an action whose actor (`actor_id`) or target (`target_id`) is not
  a `Player` seated in the same game as the phase named by `phase_id`
  (rules 2 and 3). Reports on `:actor_id` when the actor is the mismatch,
  `:target_id` when the target is — including either id failing to resolve
  to any `Player` at all. Runs unconditionally on every `:create` type and
  on `:kill`.

  When `phase_id` does not resolve to a `Phase`, this validation has
  nothing to compare against and passes; some other validation (or the data
  layer's own foreign key) is responsible for a bad `phase_id`.

  Loads `Phase`/`Player` unauthorized (`authorize?: false`), matching
  `ActorAlive`'s own stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :phase_id) do
      nil ->
        :ok

      phase_id ->
        case Games.get_phase(phase_id, authorize?: false) do
          {:ok, phase} ->
            check_all(changeset, phase.game_id)

          _ ->
            :ok
        end
    end
  end

  defp check_all(changeset, game_id) do
    with :ok <- check_seated(changeset, :actor_id, game_id) do
      check_seated(changeset, :target_id, game_id)
    end
  end

  defp check_seated(changeset, field, game_id) do
    case Changeset.get_attribute(changeset, field) do
      nil ->
        :ok

      player_id ->
        case Games.get_player(player_id, authorize?: false) do
          {:ok, %{game_id: ^game_id}} ->
            :ok

          _ ->
            {:error, field: field, message: "must be seated in the phase's game"}
        end
    end
  end
end
