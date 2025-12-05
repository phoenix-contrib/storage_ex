defmodule StorageEx.JobLaterFunctionsTest do
  use ExUnit.Case
  use StorageEx.Support.DiskCleanup

  # Use the test service configured in config/test.exs
  @test_service :test_disk

  setup do
    # Store original job_adapter config
    original_adapter = Application.get_env(:storage_ex, :job_adapter)

    on_exit(fn ->
      # Restore original config
      if original_adapter do
        Application.put_env(:storage_ex, :job_adapter, original_adapter)
      else
        Application.delete_env(:storage_ex, :job_adapter)
      end
    end)

    {:ok, original_adapter: original_adapter}
  end

  describe "with Inline adapter" do
    setup do
      Application.put_env(:storage_ex, :job_adapter, StorageEx.JobAdapters.Inline)
      :ok
    end

    test "analyze_later runs synchronously", %{namespace: ns} do
      key = "#{ns}/inline_analyze.txt"
      StorageEx.upload(key, "test content", service_name: @test_service)

      result = StorageEx.analyze_later(key, "text/plain", service_name: @test_service)

      assert {:ok, :completed} = result
    end

    test "purge_later deletes file immediately", %{namespace: ns} do
      key = "#{ns}/inline_purge.txt"
      StorageEx.upload(key, "delete me", service_name: @test_service)
      assert StorageEx.exists?(key, service_name: @test_service) == true

      result = StorageEx.purge_later(key, service_name: @test_service)

      assert {:ok, :completed} = result
      assert StorageEx.exists?(key, service_name: @test_service) == false
    end
  end

  describe "with Async adapter" do
    setup do
      Application.put_env(:storage_ex, :job_adapter, StorageEx.JobAdapters.Async)
      :ok
    end

    test "analyze_later returns immediately with reference", %{namespace: ns} do
      key = "#{ns}/async_analyze.txt"
      StorageEx.upload(key, "test content", service_name: @test_service)

      result = StorageEx.analyze_later(key, "text/plain", service_name: @test_service)

      assert {:ok, ref} = result
      assert is_reference(ref)

      # Wait for async task
      Process.sleep(100)
    end

    test "purge_later returns immediately and deletes in background", %{namespace: ns} do
      key = "#{ns}/async_purge.txt"
      StorageEx.upload(key, "delete me", service_name: @test_service)
      assert StorageEx.exists?(key, service_name: @test_service) == true

      result = StorageEx.purge_later(key, service_name: @test_service)

      assert {:ok, ref} = result
      assert is_reference(ref)

      # Wait for async task to complete
      Process.sleep(100)
      assert StorageEx.exists?(key, service_name: @test_service) == false
    end
  end

  describe "Config.job_adapter/0" do
    test "defaults to Async adapter (like Rails)" do
      Application.delete_env(:storage_ex, :job_adapter)
      assert StorageEx.Config.job_adapter() == StorageEx.JobAdapters.Async
    end

    test "returns configured adapter module" do
      Application.put_env(:storage_ex, :job_adapter, StorageEx.JobAdapters.Inline)
      assert StorageEx.Config.job_adapter() == StorageEx.JobAdapters.Inline
    end
  end
end
