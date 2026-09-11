defmodule WerewolfAshWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :werewolf_ash

  socket("/ws/gql", WerewolfAshWeb.GraphqlSocket,
    websocket: true,
    longpoll: true,
    auth_token: true
  )

  use Absinthe.Phoenix.Endpoint
  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(WerewolfAshWeb.Router)
end
