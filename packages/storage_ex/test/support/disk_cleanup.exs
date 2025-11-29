defmodule StorageEx.Support.DiskCleanup do
  @moduledoc """
  Provides isolated test namespaces for disk storage tests.

  Each test gets a unique namespace (folder prefix), ensuring parallel tests
  don't interfere with each other. Only the test's namespace is cleaned up
  after the test, not the entire storage directory.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case, async: true
        use StorageEx.Support.DiskCleanup

        test "uploads file", %{namespace: ns} do
          key = "\#{ns}/my_file.txt"
          StorageEx.upload(key, "data")
          # ...
        end
      end

  The namespace is available in the test context as `%{namespace: ns}`.
  """

  @test_services [:test_disk, :alternative_disk, :streaming_test]

  defmacro __using__(_opts) do
    quote do
      alias StorageEx.Support.DiskCleanup

      setup context do
        # Generate unique namespace for this test
        test_id = System.unique_integer([:positive, :monotonic])
        namespace = "test_#{test_id}"

        # Ensure storage directories exist
        DiskCleanup.ensure_service_directories()

        ExUnit.Callbacks.on_exit(fn ->
          # Clean up only this test's namespace from all services
          DiskCleanup.cleanup_namespace(namespace)
        end)

        {:ok, namespace: namespace}
      end
    end
  end

  @doc false
  def ensure_service_directories do
    for service <- @test_services do
      case get_service_root(service) do
        nil -> :ok
        root -> File.mkdir_p!(root)
      end
    end
  end

  @doc false
  def cleanup_namespace(namespace) do
    for service <- @test_services do
      case get_service_root(service) do
        nil ->
          :ok

        root ->
          namespace_path = Path.join(root, namespace)
          File.rm_rf(namespace_path)
      end
    end
  end

  defp get_service_root(service) do
    case Application.get_env(:storage_ex, :services, %{})[service] do
      nil -> nil
      config -> config[:configuration][:root]
    end
  end
end
