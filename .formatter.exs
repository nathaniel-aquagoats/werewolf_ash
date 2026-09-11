# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Absinthe.Formatter, Spark.Formatter],
  import_deps: [
    :ash_authentication,
    :ash_graphql,
    :absinthe,
    :ash_state_machine,
    :ash_oban,
    :oban,
    :ash_postgres,
    :ash,
    :reactor
  ]
]
