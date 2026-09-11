# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash_state_machine, :ash_oban, :oban, :ash_postgres, :ash, :reactor]
]
