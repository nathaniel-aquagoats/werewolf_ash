defmodule WerewolfAsh.Generators do
  @moduledoc """
  `Ash.Generator` based fixtures for tests. Users are seeded straight into the
  data layer (no registration side effects); everything in the Games domain
  goes through its real actions.
  """

  use Ash.Generator

  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Player

  def user(opts \\ []) do
    seed_generator(
      %User{
        email: sequence(:user_email, &"user#{&1}@example.com")
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

  @doc """
  A seat in a game. Pass `game_id:` to seat several players in one game and
  `role:` to deal a role (a second `update_player` step run after the seat is
  created, since `Player`'s `:create` action no longer accepts `role`
  directly); `alive` can only be flipped through `update_player`.
  """
  def player(opts \\ []) do
    {role, opts} = Keyword.pop(opts, :role, nil)

    changeset_generator(
      Player,
      :create,
      defaults: [
        # Lazy, so an overridden game_id/user_id does not create a spare record.
        game_id: StreamData.repeatedly(fn -> generate(game()).id end),
        user_id: StreamData.repeatedly(fn -> generate(user()).id end)
      ],
      after_action: fn player -> Games.update_player!(player, %{role: role}) end,
      overrides: opts
    )
  end
end
