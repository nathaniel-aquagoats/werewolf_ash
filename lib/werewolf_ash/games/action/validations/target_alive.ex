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

  With `night_victim?: true` (only the `:investigate` clause passes it, qss.19
  rules 25-26) a dead target also passes when its death is not yet announced
  and the phase the action names holds a `:kill` on it that landed
  (`result["killed"] == true`). That `:kill` lookup is `authorize?: false`: the
  seer cannot read `:kill` rows.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, opts, _context) do
    night_victim? = Keyword.get(opts, :night_victim?, false)

    case Changeset.get_attribute(changeset, :target_id) do
      nil ->
        :ok

      target_id ->
        case Games.get_player(target_id, authorize?: false) do
          {:ok, %{alive: true}} ->
            :ok

          {:ok, %{death_announced_at: nil}} when night_victim? ->
            landed_kill(Changeset.get_attribute(changeset, :phase_id), target_id)

          _ ->
            not_alive()
        end
    end
  end

  defp landed_kill(phase_id, target_id) do
    landed? =
      [phase_id: phase_id, type: :kill, target_id: target_id]
      |> then(&Games.list_actions!(query: [filter: &1], authorize?: false))
      |> Enum.any?(&(&1.result["killed"] == true))

    if landed?, do: :ok, else: not_alive()
  end

  defp not_alive, do: {:error, field: :target_id, message: "the target is not alive"}
end
