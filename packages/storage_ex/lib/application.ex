defmodule StorageEx.Application do
  @moduledoc """
  StorageEx OTP Application.

  Starts the supervision tree for StorageEx services:

    * `StorageEx.TaskSupervisor` - Supervises async job tasks

  ## Usage

  StorageEx can be used as a library (no supervision tree) or as an
  application (with supervision tree).

  ### As an Application (Recommended for Async Jobs)

  Add to your `mix.exs`:

      def application do
        [
          mod: {StorageEx.Application, []},
          extra_applications: [:logger]
        ]
      end

  Or add StorageEx.Application to your supervision tree:

      children = [
        StorageEx.Application,
        # ... other children
      ]

  ### As a Library (No Async Jobs)

  If you don't use the `Async` job adapter, you can use StorageEx
  without starting its application:

      # No mod: required
      def application do
        [extra_applications: [:logger]]
      end

  ## Task Supervisor

  The `StorageEx.TaskSupervisor` is required for the `Async` job adapter.
  If you're using a different adapter (Inline, Oban, etc.), the supervisor
  isn't strictly necessary but is still started for consistency.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: StorageEx.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: StorageEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
