%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/"
        ]
      },
      extends: ["../../.credo.exs"]
    }
  ]
}