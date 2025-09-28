defmodule StorageEx.NotificationsTest do
  use ExUnit.Case, async: true

  alias StorageEx.Notifications

  # Test handler to avoid telemetry warnings about anonymous functions
  defmodule TestHandler do
    def handle_event(event, measurements, metadata, config) do
      send(config.test_pid, {config.ref, event, measurements, metadata})
    end
  end

  describe "prefix/0" do
    test "returns the telemetry prefix" do
      assert Notifications.prefix() == [:storage_ex]
    end
  end

  describe "span/3" do
    test "emits telemetry events with timing" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach_many(
        "test-handler-#{inspect(ref)}",
        [
          [:storage_ex, :test_operation, :start],
          [:storage_ex, :test_operation, :stop]
        ],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, ref: ref}
      )

      metadata = %{service: StorageEx.Services.Disk, args: ["test.txt"]}

      result =
        Notifications.span(:test_operation, metadata, fn ->
          {:ok, "success"}
        end)

      assert {:ok, "success"} == result

      # Should receive start event
      assert_receive {^ref, [:storage_ex, :test_operation, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.service == StorageEx.Services.Disk
      assert start_metadata.args == ["test.txt"]
      assert start_metadata.operation == :test_operation

      # Should receive stop event
      assert_receive {^ref, [:storage_ex, :test_operation, :stop], stop_measurements,
                      stop_metadata}

      assert is_integer(stop_measurements.duration)
      assert stop_metadata.service == StorageEx.Services.Disk
      assert start_metadata.args == ["test.txt"]

      :telemetry.detach("test-handler-#{inspect(ref)}")
    end

    test "emits exception event on failure" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-exception-handler-#{inspect(ref)}",
        [:storage_ex, :failing_operation, :exception],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, ref: ref}
      )

      metadata = %{service: StorageEx.Services.Disk, args: ["test.txt"]}

      assert_raise RuntimeError, "test error", fn ->
        Notifications.span(:failing_operation, metadata, fn ->
          raise "test error"
        end)
      end

      # Should receive exception event
      assert_receive {^ref, [:storage_ex, :failing_operation, :exception], measurements,
                      exception_metadata}

      assert is_integer(measurements.duration)
      assert exception_metadata.service == StorageEx.Services.Disk
      assert exception_metadata.args == ["test.txt"]
      assert exception_metadata.kind == :error
      assert %RuntimeError{} = exception_metadata.reason

      :telemetry.detach("test-exception-handler-#{inspect(ref)}")
    end
  end

  describe "execute/3" do
    test "executes telemetry event with atom operation" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-execute-handler-#{inspect(ref)}",
        [:storage_ex, :custom_event],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, ref: ref}
      )

      Notifications.execute(:custom_event, %{count: 5}, %{key: "test.txt"})

      assert_receive {^ref, [:storage_ex, :custom_event], measurements, metadata}
      assert measurements.count == 5
      assert metadata.key == "test.txt"

      :telemetry.detach("test-execute-handler-#{inspect(ref)}")
    end

    test "executes telemetry event with list operation" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-execute-list-handler-#{inspect(ref)}",
        [:storage_ex, :nested, :event],
        &TestHandler.handle_event/4,
        %{test_pid: test_pid, ref: ref}
      )

      Notifications.execute([:nested, :event], %{value: 10}, %{info: "test"})

      assert_receive {^ref, [:storage_ex, :nested, :event], measurements, metadata}
      assert measurements.value == 10
      assert metadata.info == "test"

      :telemetry.detach("test-execute-list-handler-#{inspect(ref)}")
    end
  end
end
