defmodule WerewolfAsh.Games.Action.Validations.TargetAlive do
  @moduledoc """
  Rejects an action whose target (`target_id`) is not currently alive
  (rule 1). Says nothing about `:type`: it runs wherever it is wired in —
  guarded by `where:` for `:vote`/`:investigate`/`:protect`/`:shoot` on
  `:create` (werewolf_ash-qss.7 rule 11 adds `:shoot` to that guard),
  unconditionally on `:kill`.

  Loads the `Player` unauthorized (`authorize?: false`), matching
  `ActorAlive`'s own stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :target_id) do
      nil ->
        :ok

      target_id ->
        case Games.get_player(target_id, authorize?: false) do
          {:ok, %{alive: true}} -> :ok
          _ -> {:error, field: :target_id, message: "the target is not alive"}
        end
    end
  end
end
