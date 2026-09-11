defmodule WerewolfAsh.Games do
  @moduledoc """
  The werewolf game domain: games, their players, the day/night phases and the
  actions players take within them. All game rules live behind this domain's
  code interface; interfaces (GraphQL, scheduler) only call it.
  """

  use Ash.Domain,
    otp_app: :werewolf_ash

  resources do
    resource WerewolfAsh.Games.Game do
      define :create_game, action: :create
      define :update_game, action: :update
      define :destroy_game, action: :destroy
      define :get_game, action: :read, get_by: [:id]
      define :get_game_by_join_code, action: :read, get_by: [:join_code]
      define :list_games, action: :read
    end

    resource WerewolfAsh.Games.Player do
      define :add_player, action: :create, args: [:game_id, :user_id]
      define :update_player, action: :update
      define :remove_player, action: :destroy
      define :get_player, action: :read, get_by: [:id]
      define :list_players, action: :read
    end

    resource WerewolfAsh.Games.Phase do
      define :create_phase, action: :create, args: [:game_id, :kind, :number]
      define :update_phase, action: :update
      define :get_phase, action: :read, get_by: [:id]
      define :list_phases, action: :read
    end

    resource WerewolfAsh.Games.Action do
      define :create_action, action: :create, args: [:phase_id, :actor_id, :target_id, :type]
      define :update_action, action: :update
      define :get_action, action: :read, get_by: [:id]
      define :list_actions, action: :read
    end
  end
end
