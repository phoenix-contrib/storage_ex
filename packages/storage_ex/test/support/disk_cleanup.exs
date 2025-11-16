defmodule StorageEx.Support.DiskCleanup do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      setup :disk_cleanup

      def disk_cleanup(_) do
        test_dir = Path.join(System.tmp_dir!(), "storage_ex_test")

        # Use non-bang version to avoid errors if directory doesn't exist or is already being deleted
        case File.rm_rf(test_dir) do
          {:ok, _} -> :ok
          {:error, _, _} -> :ok
        end

        File.mkdir_p!(test_dir)

        ExUnit.Callbacks.on_exit(fn ->
          case File.rm_rf(test_dir) do
            {:ok, _} -> :ok
            {:error, _, _} -> :ok
          end
        end)

        :ok
      end
    end
  end
end
