defmodule StorageEx.Support.DiskCleanup do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      setup :disk_cleanup

      def disk_cleanup(_) do
        test_dir = Path.join(System.tmp_dir!(), "storage_ex_test")
        File.rm_rf!(test_dir)
        File.mkdir_p!(test_dir)

        ExUnit.Callbacks.on_exit(fn ->
          File.rm_rf!(test_dir)
        end)

        :ok
      end
    end
  end
end
