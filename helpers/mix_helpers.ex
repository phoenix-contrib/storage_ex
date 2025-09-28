unless Code.ensure_loaded?(MixHelpers) do
  defmodule MixHelpers do
    @moduledoc """
    Centralized helpers for Mix projects in this repo.
    """

    @default_deps [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.17", only: :test},
      {:mix_test_watch, "~> 1.3.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
    ]

    @doc """
    Returns common dev/test dependencies.

    Accepts overrides as a keyword list. Each override can be:

      * a new version string (e.g., `credo: "~> 1.8"`)
      * or a full tuple (e.g., `credo: {:credo, "~> 1.8", only: [:dev], runtime: false}`)

    Example:

        MixHelpers.deps(
          credo: "~> 1.8",
          ex_doc: {:ex_doc, "~> 0.35", only: [:dev, :test], runtime: false}
        )
    """
    def deps(overrides \\ []) do
      Enum.map(@default_deps, fn
        {name, _version, opts} = dep ->
          case Keyword.fetch(overrides, name) do
            {:ok, new} -> normalize_override(name, new, opts)
            :error -> dep
          end
      end)
    end

    @doc "Common project config keys (dialyzer, coverage)."
    def common_project_config do
      [
        elixir: "~> 1.14",
        test_coverage: [tool: ExCoveralls],
        dialyzer: [
          plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
          plt_add_apps: [:mix, :ex_unit],
          plt_core_path: "../../priv/plts/core",
          plt_local_path: "priv/plts",
          no_umbrella: true
        ],
        preferred_cli_env: [
          "test.watch": :test
        ]
      ]
    end

    @doc "Shared build/deps/lock paths for all packages in the monorepo"
    def shared_paths do
      [
        build_path: "../../_build",
        deps_path: "../../deps",
        lockfile: "../../mix.lock"
      ]
    end

    @doc "Common mix aliases to enforce consistency across packages."
    def common_aliases do
      [
        # individual shortcuts
        # non-strict
        lint: ["credo"],
        # strict
        lint_strict: ["credo --strict"],
        # dialyzer only
        analyze: ["dialyzer"],
        fmt_check: ["format --check-formatted"],

        # coverage
        coverage: ["coveralls"],
        coverage_html: ["coveralls.html"],

        # composed all-in-one check (good for CI)
        check: [
          "fmt_check",
          "lint_strict",
          "analyze",
          "test",
          "coverage"
        ]
      ]
    end

    defp normalize_override(name, version, opts) when is_binary(version),
      do: {name, version, opts}

    defp normalize_override(_name, tuple, _opts) when is_tuple(tuple),
      do: tuple
  end
end
