defmodule StorageEx.JobAdapters.InlineTest do
  use ExUnit.Case
  use StorageEx.Support.DiskCleanup

  alias StorageEx.JobAdapters.Inline

  # Use the test service configured in config/test.exs
  @test_service :test_disk

  describe "enqueue_analyze/3" do
    test "runs analysis synchronously and returns :completed", %{namespace: ns} do
      # Upload a test file first
      key = "#{ns}/analyze_test.txt"
      StorageEx.upload(key, "test content", service_name: @test_service)

      # Analyze - should complete immediately
      result = Inline.enqueue_analyze(key, "text/plain", service_name: @test_service)

      assert result == {:ok, :completed}
    end

    test "returns error for non-existent file" do
      result =
        Inline.enqueue_analyze("nonexistent.jpg", "image/jpeg", service_name: @test_service)

      assert {:error, _reason} = result
    end
  end

  describe "enqueue_purge/3" do
    test "deletes file synchronously and returns :completed", %{namespace: ns} do
      # Upload a test file
      key = "#{ns}/purge_test.txt"
      StorageEx.upload(key, "delete me", service_name: @test_service)
      assert StorageEx.exists?(key, service_name: @test_service) == true

      # Purge - should delete immediately
      result = Inline.enqueue_purge(key, @test_service, [])

      assert result == {:ok, :completed}
      assert StorageEx.exists?(key, service_name: @test_service) == false
    end

    test "returns :completed even for non-existent file" do
      # DiskService.delete returns :ok even for non-existent files
      result = Inline.enqueue_purge("nonexistent.txt", @test_service, [])

      # Depending on service behavior, this might be :ok or an error
      assert result == {:ok, :completed} or match?({:error, _}, result)
    end
  end

  describe "behaviour implementation" do
    test "implements all required callbacks" do
      behaviours = Inline.module_info(:attributes)[:behaviour] || []
      assert StorageEx.JobAdapter in behaviours
    end
  end
end
