defmodule WerewolfAsh.Games.Action.Validations.TypeRequiresPhaseAndRole do
  @moduledoc """
  Rejects an action whose referenced `Phase` is not of `phase_kind:`, or
  (when `role:` is also given) whose actor does not hold `role:`. Reports on
  `:type`: the actor picked the wrong kind of move for the phase or role
  they are in, not that a reference is bad. `role:` is optional — omitting
  it means no role restriction, per `:vote`'s rule 2.

  Backs rules 2, 4 and 5 on `:create` (each guarded by its own `where:`) and
  rule 3's unconditional use on `:kill`. Says nothing about `:type` itself:
  callers wire it in per action.

  Loads `Phase`/`Player` unauthorized (`authorize?: false`), matching
  `AuthorMayPost`'s stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def init(opts) do
    phase_kind = opts[:phase_kind]
    role = opts[:role]

    if is_atom(phase_kind) and not is_nil(phase_kind) and (is_nil(role) or is_atom(role)) do
      {:ok, opts}
    else
      {:error,
       "`phase_kind` must be an atom and `role`, if given, must be an atom, got: #{inspect(opts)}"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    with :ok <- check_phase(changeset, opts[:phase_kind]) do
      check_role(changeset, opts[:role])
    end
  end

  defp check_phase(changeset, phase_kind) do
    case Changeset.get_attribute(changeset, :phase_id) do
      nil ->
        :ok

      phase_id ->
        case Games.get_phase(phase_id, authorize?: false) do
          {:ok, %{kind: ^phase_kind}} ->
            :ok

          _ ->
            {:error, field: :type, message: "requires a %{kind} phase", vars: [kind: phase_kind]}
        end
    end
  end

  defp check_role(_changeset, nil), do: :ok

  defp check_role(changeset, role) do
    case Changeset.get_attribute(changeset, :actor_id) do
      nil ->
        :ok

      actor_id ->
        case Games.get_player(actor_id, authorize?: false) do
          {:ok, %{role: ^role}} ->
            :ok

          _ ->
            {:error,
             field: :type, message: "requires the actor to be a %{role}", vars: [role: role]}
        end
    end
  end
end
