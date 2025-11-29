Code.eval_file("../../helpers/mix_helpers.ex")

defmodule PhoenixContribStorageEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/phoenix-contrib/storage_ex"

  def project do
    [
      app: :phoenix_contrib_storage_ex,
      name: "StorageEx",
      version: @version,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      aliases: MixHelpers.common_aliases()
    ] ++
      MixHelpers.shared_paths() ++
      MixHelpers.common_project_config()
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "ActiveStorage-like file storage for Phoenix. Core package with Local service and facade pattern."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["andresgutgon"],
      files: ~w(lib priv mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "StorageEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:mime, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:igniter, "~> 0.6", optional: true},
      # Optional image processing (for variants/transformations)
      {:image, "~> 0.54", optional: true}
    ] ++ MixHelpers.deps()
  end
end
