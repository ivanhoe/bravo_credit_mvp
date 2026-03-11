%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["config/", "lib/", "test/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      requires: [],
      plugins: [],
      checks: [
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 100}
      ]
    }
  ]
}
