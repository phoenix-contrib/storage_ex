defmodule StorageEx.JobAdapters.AsyncTest do
  use ExUnit.Case
  use StorageEx.Support.DiskCleanup

  import ExUnit.CaptureLog

  alias StorageEx.JobAdapters.Async

  # Use the test service configured in config/test.exs
  @test_service :test_disk

  describe "enqueue_analyze/3" do
    test "returns immediately with a reference", %{namespace: ns} do
      # Upload a test file first
      key = "#{ns}/analyze_test.txt"
      StorageEx.upload(key, "test content", service_name: @test_service)

      # Enqueue analysis - should return immediately
      result = Async.enqueue_analyze(key, "text/plain", service_name: @test_service)

      assert {:ok, ref} = result
      assert is_reference(ref)

      # Give the task time to complete
      Process.sleep(100)
    end

    test "does not block the caller", %{namespace: ns} do
      key = "#{ns}/async_test.txt"
      StorageEx.upload(key, "content", service_name: @test_service)

      # Measure time - should be nearly instant
      {time_us, result} =
        :timer.tc(fn ->
          Async.enqueue_analyze(key, "text/plain", service_name: @test_service)
        end)

      assert {:ok, _ref} = result
      # Should complete in less than 100ms (actual work happens in background)
      assert time_us < 100_000

      Process.sleep(100)
    end
  end

  describe "enqueue_purge/3" do
    test "returns immediately and deletes file in background", %{namespace: ns} do
      # Upload a test file
      key = "#{ns}/purge_test.txt"
      StorageEx.upload(key, "delete me", service_name: @test_service)
      assert StorageEx.exists?(key, service_name: @test_service) == true

      # Enqueue purge - should return immediately
      result = Async.enqueue_purge(key, @test_service, [])

      assert {:ok, ref} = result
      assert is_reference(ref)

      # File might still exist immediately after enqueue
      # Wait for the task to complete
      Process.sleep(100)

      # Now the file should be deleted
      assert StorageEx.exists?(key, service_name: @test_service) == false
    end
  end

  describe "enqueue_preview/2" do
    test "returns immediately with a reference" do
      result = Async.enqueue_preview("video.mp4", content_type: "video/mp4")

      assert {:ok, ref} = result
      assert is_reference(ref)

      # Give the task time to run (it will fail but that's ok)
      Process.sleep(50)
    end
  end

  describe "enqueue_transform/3" do
    test "returns immediately with a reference" do
      # Capture log to suppress expected error from non-existent file
      capture_log(fn ->
        result =
          Async.enqueue_transform(
            "photo.jpg",
            [resize_to_limit: [100, 100]],
            service_name: @test_service
          )

        assert {:ok, ref} = result
        assert is_reference(ref)

        Process.sleep(50)
      end)
    end
  end

  describe "behaviour implementation" do
    test "implements all required callbacks" do
      behaviours = Async.module_info(:attributes)[:behaviour] || []
      assert StorageEx.JobAdapter in behaviours
    end
  end
end
