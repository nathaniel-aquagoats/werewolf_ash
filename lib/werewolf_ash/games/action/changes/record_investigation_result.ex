defmodule WerewolfAsh.Games.Action.Changes.RecordInvestigationResult do
  @moduledoc """
  Computes a seer's immediate yes/no answer (rule 8): creating an
  `:investigate` action stages `result: %{"is_werewolf" => boolean}`, `true`
  exactly when the target's `role` is `:werewolf` at the moment of creation
  (dead or alive — this checks the role, not survival). Every other type
  leaves `result` untouched.

  Loads the target `Player` unauthorized (`authorize?: false`), matching
  `AuthorMayPost`'s stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def change(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :type) do
      :investigate ->
        target_id = Changeset.get_attribute(changeset, :target_id)

        Changeset.force_change_attribute(changeset, :result, %{
          "is_werewolf" => werewolf?(target_id)
        })

      _ ->
        changeset
    end
  end

  defp werewolf?(nil), do: false

  defp werewolf?(target_id) do
    case Games.get_player(target_id, authorize?: false) do
      {:ok, %{role: :werewolf}} -> true
      _ -> false
    end
  end
end
