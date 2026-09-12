defmodule WerewolfAsh.Games.Action.Validations.ActorAlive do
  @moduledoc """
  Rejects an action whose actor (`actor_id`) is not currently alive
  (rule 1). Says nothing about `:type`: it runs wherever it is wired in —
  guarded by `where:` for `:vote`/`:investigate`/`:protect` on `:create`,
  unconditionally on `:kill` — never for `:shoot`, whose own check is
  `ShootRequiresPendingHunter`.

  Loads the `Player` unauthorized (`authorize?: false`), matching
  `AuthorMayPost`'s stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :actor_id) do
      nil ->
        :ok

      actor_id ->
        case Games.get_player(actor_id, authorize?: false) do
          {:ok, %{alive: true}} -> :ok
          _ -> {:error, field: :actor_id, message: "the actor is not alive"}
        end
    end
  end
end
