defmodule WerewolfAsh.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WerewolfAsh.Repo,
      {Phoenix.PubSub, name: WerewolfAsh.PubSub},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:werewolf_ash, :ash_domains),
         Application.fetch_env!(:werewolf_ash, Oban)
       )},
      WerewolfAshWeb.Endpoint,
      {Absinthe.Subscription, WerewolfAshWeb.Endpoint},
      AshGraphql.Subscription.Batcher,
      {AshAuthentication.Supervisor, [otp_app: :werewolf_ash]}
    ]

    opts = [strategy: :one_for_one, name: WerewolfAsh.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
