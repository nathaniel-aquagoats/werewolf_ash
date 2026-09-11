defmodule WerewolfAsh.Generators do
  @moduledoc """
  `Ash.Generator` based fixtures for tests. Users are seeded straight into the
  data layer (no registration side effects); everything in the Games domain
  goes through its real actions.
  """

  use Ash.Generator

  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Games.Game

  def user(opts \\ []) do
    seed_generator(
      %User{
        email: sequence(:user_email, &"user#{&1}@example.com"),
        hashed_password: "not-a-real-hash"
      },
      overrides: opts
    )
  end

  def game(opts \\ []) do
    changeset_generator(
      Game,
      :create,
      uses: [owner: user()],
      defaults: fn %{owner: owner} ->
        owner = generate(owner)

        # action_input generates random values for any accepted attribute we
        # leave out, so pin the ones with meaningful defaults.
        [
          name: sequence(:game_name, &"Game #{&1}"),
          join_code: sequence(:join_code, &"CODE#{&1}"),
          timezone: "Etc/UTC",
          day_start: ~T[08:00:00],
          day_end: ~T[20:00:00],
          owner_id: owner.id
        ]
      end,
      overrides: opts
    )
  end
end
