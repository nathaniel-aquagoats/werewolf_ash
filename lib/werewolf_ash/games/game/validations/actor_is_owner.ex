defmodule WerewolfAsh.Games.Game.Validations.ActorIsOwner do
  @moduledoc """
  Rejects an action whose actor is not the game's own owner.

  Reads the action's ordinary `actor` — the mechanism already wired end to
  end via `WerewolfAshWeb.Plugs.BearerActor` and
  `WerewolfAshWeb.GraphqlSocket` — rather than a caller-supplied argument.
  This is a plain validation, not an `Ash.Policy.Authorizer` policy; see
  werewolf_ash-27w.2 for the real authorization layer this stands in for
  until then.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, context) do
    owner_id = Changeset.get_attribute(changeset, :owner_id)

    case Map.get(context, :actor) do
      %{id: ^owner_id} -> :ok
      _ -> {:error, field: :owner_id, message: "only the game's owner may do this"}
    end
  end
end
