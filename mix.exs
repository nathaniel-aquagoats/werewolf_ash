defmodule WerewolfAsh.MixProject do
  use Mix.Project

  def project do
    [
      app: :werewolf_ash,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      usage_rules: usage_rules()
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [:usage_rules, :igniter],
      skills: [
        location: ".claude/skills",
        build: [
          "ash-framework": [
            description:
              "Use when working with Ash Framework or any ash_* extension: domains, resources, actions, policies, AshPostgres, AshOban, AshGraphql, AshAuthentication. Consult before any domain change.",
            usage_rules: [:ash, ~r/^ash_/]
          ],
          reactor: [
            description:
              "Use when writing or changing Reactor sagas/workflows (steps, inputs, compensation, map/switch/compose).",
            usage_rules: [:reactor]
          ],
          "phoenix-api": [
            description:
              "Use when working on the Phoenix API layer: endpoint, router, Absinthe/GraphQL plugs and sockets.",
            usage_rules: [:phoenix, ~r/^phoenix_/]
          ]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WerewolfAsh.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tz, "~> 0.28"},
      {:bcrypt_elixir, "~> 3.0"},
      {:picosat_elixir, "~> 0.2"},
      {:absinthe_phoenix, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_graphql, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:phoenix, "~> 1.8"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:reactor, "~> 1.0"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:oban, "~> 2.0"},
      {:ash_state_machine, "~> 0.2"},
      {:oban_web, "~> 2.0"},
      {:ash_oban, "~> 0.8"},
      {:ash_postgres, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases() do
    [test: ["ash.setup --quiet", "test"], setup: "ash.setup"]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
