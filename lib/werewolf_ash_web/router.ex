defmodule WerewolfAshWeb.Router do
  use Phoenix.Router

  pipeline :graphql do
    plug(AshGraphql.Plug)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/gql" do
    pipe_through [:graphql]

    forward("/playground", Absinthe.Plug.GraphiQL,
      schema: Module.concat(["WerewolfAshWeb.GraphqlSchema"]),
      socket: Module.concat(["WerewolfAshWeb.GraphqlSocket"]),
      interface: :simple
    )

    forward("/", Absinthe.Plug, schema: Module.concat(["WerewolfAshWeb.GraphqlSchema"]))
  end

  scope "/", WerewolfAshWeb do
    pipe_through :api
  end
end
