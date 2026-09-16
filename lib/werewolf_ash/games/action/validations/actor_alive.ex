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

  Also reused, unconditionally, on `:withdraw` (rule 7), where the subject
  is an `Ash.ActionInput` rather than a `Changeset`: the second
  `validate/3` clause below reads `:actor_id` off the input's argument
  instead of a changeset attribute, and `supports/1` is overridden so the
  generic action's own validation runner accepts an `Ash.ActionInput`
  subject at all.
  """

  use Ash.Resource.Validation

  alias Ash.ActionInput
  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput]

  @impl true
  def validate(%Changeset{} = changeset, _opts, _context) do
    check(Changeset.get_attribute(changeset, :actor_id))
  end

  def validate(%ActionInput{} = input, _opts, _context) do
    check(ActionInput.get_argument(input, :actor_id))
  end

  defp check(nil), do: :ok

  defp check(actor_id) do
    case Games.get_player(actor_id, authorize?: false) do
      {:ok, %{alive: true}} -> :ok
      _ -> {:error, field: :actor_id, message: "the actor is not alive"}
    end
  end
end
