defmodule WerewolfAsh.Games.Player.Validations.UserHasName do
  @moduledoc """
  Rejects seating a `User` with no display name yet, shared by `:create`
  (rule 5, direct or via `Game.Changes.SeatOwner`'s `manage_relationship`)
  and `:join`. Always reports the error on `:name`, regardless of which
  action ran it.

  A `Player` with no resolvable `:user_id` yet is left alone here; that is
  the action's own required-input check to report.

  The user is looked up without authorization: this is a game rule, not an
  access check, so it must not depend on what the actor may read — the same
  convention `Message.Validations.AuthorMayPost` uses to load its `Player`.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Accounts.User

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :user_id) do
      nil ->
        :ok

      user_id ->
        case Ash.get(User, user_id, authorize?: false) do
          {:ok, %{name: nil}} -> {:error, field: :name, message: "must be set before seating"}
          {:ok, _user} -> :ok
          {:error, _} -> :ok
        end
    end
  end
end
