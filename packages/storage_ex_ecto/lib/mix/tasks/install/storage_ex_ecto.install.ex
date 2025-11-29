if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.StorageExEcto.Install do
    @shortdoc "Installs StorageEx into a project.
    Should be called with `mix igniter.install phoenix_contrib_storage_ex`"

    @moduledoc """
    #{@shortdoc}

    """

    use Igniter.Mix.Task

    alias Mix.Tasks.Install.Migrations

    @manual_lead_in """
    This guide will walk you through the process of manually installing StorageEx into your project.
    If you are starting from scratch, you can use `mix new` or `mix igniter.new` and follow these instructions.
    These installation instructions apply both to new projects and existing ones.
    """

    @repo_config """
    Add the following to your `config/config.exs`:

        config :phoenix_contrib_storage_ex,
          repo: MyApp.Repo
    """

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: [],
        schema: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Migrations.add_storage_migration()
      |> Igniter.Scribe.start_document(
        "Manual Installation",
        @manual_lead_in,
        app_name: :my_app
      )
      |> Igniter.Scribe.section("Configure the Repo", @repo_config, fn igniter ->
        igniter
      end)
    end
  end
else
  defmodule Mix.Tasks.PhoenixContribStorageEx.Install do
    @moduledoc "Installs StorageEx into a project. Should be called with `mix igniter.install phoenix_contrib_storage_ex`"

    @shortdoc @moduledoc

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'phoenix_contrib_storage_ex.install' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
