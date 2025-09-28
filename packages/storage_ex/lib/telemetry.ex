defmodule StorageEx.Telemetry do
  @moduledoc """
  Telemetry integration guide for StorageEx.

  StorageEx automatically emits telemetry events for all storage operations,
  similar to Rails' ActiveSupport::Notifications.

  ## Quick Start

  Add telemetry handlers in your application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          # Attach telemetry handlers
          :ok = StorageEx.Telemetry.attach_default_handler()

          children = [
            # ... your other children
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ## Available Events

  All events are prefixed with `[:storage_ex]` and follow the pattern:
  `[:storage_ex, operation, event_type]`

  ### Operations

    * `:upload` - File upload operations
    * `:download` - Full file download operations
    * `:download_chunk` - Partial download operations
    * `:download_stream` - Stream download operations
    * `:delete` - File deletion operations
    * `:delete_prefixed` - Prefix-based deletion operations
    * `:exists?` - File existence check operations
    * `:compose` - File composition operations
    * `:update_metadata` - Metadata update operations
    * `:url` - URL generation operations
    * `:url_for_direct_upload` - Direct upload URL generation
    * `:headers_for_direct_upload` - Direct upload headers generation

  ### Event Types

    * `:start` - Emitted when operation begins
    * `:stop` - Emitted when operation completes successfully
    * `:exception` - Emitted when operation fails

  ## Measurements

  ### Start Events

    * `system_time` - System time when event was emitted (native units)

  ### Stop Events

    * `duration` - Time in native units the operation took

  ### Exception Events

    * `duration` - Time in native units before the exception occurred

  ## Metadata

  All events include:

    * `service` - The service module (e.g., `StorageEx.Services.Disk`)
    * `operation` - The operation name (e.g., `:upload`)
    * `args` - List of arguments passed to the operation (raw, without the service struct)

  You can extract operation-specific metadata from `args` in your handlers:

    * For `:upload` - `[key, data, opts]` where opts may contain `:checksum`, `:content_type`
    * For `:download` - `[key]`
    * For `:download_chunk` - `[key, range]`
    * For `:delete` - `[key]`
    * For `:delete_prefixed` - `[prefix]`
    * For `:compose` - `[source_keys, destination_key, opts]`

  Exception events also include:

    * `kind` - Exception kind (`:error`, `:exit`, `:throw`)
    * `reason` - The exception/error reason
    * `stacktrace` - The exception stacktrace

  ## Examples

  ### Basic Logger

      defmodule MyApp.Telemetry do
        require Logger

        def attach do
          events = [
            [:storage_ex, :upload, :stop],
            [:storage_ex, :download, :stop],
            [:storage_ex, :delete, :stop]
          ]

          :telemetry.attach_many(
            "my-app-storage-logger",
            events,
            &__MODULE__.handle_event/4,
            nil
          )
        end

        def handle_event([:storage_ex, operation, :stop], measurements, metadata, _config) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          
          # Extract key from args if present (first arg for most operations)
          key = case metadata.args do
            [key | _] when is_binary(key) -> key
            _ -> nil
          end

          Logger.info("StorageEx operation completed",
            operation: operation,
            key: key,
            service: inspect(metadata.service),
            duration_ms: duration_ms
          )
        end
      end

  ### Metrics with Telemetry.Metrics

      defmodule MyApp.Telemetry do
        import Telemetry.Metrics

        def metrics do
          [
            # Track upload counts by service
            counter("storage_ex.upload.stop.count",
              tags: [:service]
            ),

            # Track upload duration
            distribution("storage_ex.upload.stop.duration",
              unit: {:native, :millisecond},
              tags: [:service]
            ),

            # Track download counts
            counter("storage_ex.download.stop.count",
              tags: [:service]
            ),

            # Track error rates
            counter("storage_ex.upload.exception.count",
              tags: [:service]
            )
          ]
        end
      end

  ### Error Tracking

      defmodule MyApp.ErrorTracker do
        require Logger

        def attach do
          events = [
            [:storage_ex, :upload, :exception],
            [:storage_ex, :download, :exception],
            [:storage_ex, :delete, :exception]
          ]

          :telemetry.attach_many(
            "my-app-storage-errors",
            events,
            &__MODULE__.handle_exception/4,
            nil
          )
        end

        def handle_exception([:storage_ex, operation, :exception], _measurements, metadata, _config) do
          # Extract key from args if present
          key = case metadata.args do
            [key | _] when is_binary(key) -> key
            _ -> nil
          end
          
          Logger.error("StorageEx operation failed",
            operation: operation,
            key: key,
            service: inspect(metadata.service),
            error: Exception.message(metadata.reason),
            stacktrace: Exception.format_stacktrace(metadata.stacktrace)
          )

          # Send to error tracking service
          # Sentry.capture_exception(metadata.reason, stacktrace: metadata.stacktrace)
        end
      end

  ### Custom Metrics Dashboard

      defmodule MyApp.StorageDashboard do
        use GenServer
        require Logger

        def start_link(_) do
          GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
        end

        def init(state) do
          events = [
            [:storage_ex, :upload, :stop],
            [:storage_ex, :download, :stop]
          ]

          :telemetry.attach_many(
            "storage-dashboard",
            events,
            &__MODULE__.handle_event/4,
            self()
          )

          {:ok, state}
        end

        def handle_event([:storage_ex, :upload, :stop], measurements, metadata, pid) do
          send(pid, {:metric, :upload, measurements, metadata})
        end

        def handle_event([:storage_ex, :download, :stop], measurements, metadata, pid) do
          send(pid, {:metric, :download, measurements, metadata})
        end

        def handle_info({:metric, operation, measurements, metadata}, state) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

          Logger.info("Storage metric",
            operation: operation,
            duration_ms: duration_ms,
            service: inspect(metadata.service)
          )

          # Update your dashboard/metrics here
          {:noreply, state}
        end
      end

  ## Integration with Phoenix LiveDashboard

  If using Phoenix LiveDashboard, you can add StorageEx metrics:

      # In your telemetry module
      def metrics do
        [
          # ... other metrics

          # StorageEx metrics
          summary("storage_ex.upload.stop.duration",
            unit: {:native, :millisecond},
            tags: [:service],
            tag_values: &tag_values/1
          ),

          summary("storage_ex.download.stop.duration",
            unit: {:native, :millisecond},
            tags: [:service],
            tag_values: &tag_values/1
          ),

          counter("storage_ex.upload.exception.count",
            tags: [:service],
            tag_values: &tag_values/1
          )
        ]
      end

      defp tag_values(metadata) do
        %{service: extract_service_name(metadata.service)}
      end

      defp extract_service_name(module) when is_atom(module) do
        module
        |> Module.split()
        |> List.last()
        |> String.downcase()
      end
  """

  require Logger

  @doc """
  Attaches a default handler that logs all StorageEx operations.

  This is useful for development and debugging.
  """
  def attach_default_handler do
    events = [
      [:storage_ex, :upload, :stop],
      [:storage_ex, :download, :stop],
      [:storage_ex, :download_chunk, :stop],
      [:storage_ex, :download_stream, :stop],
      [:storage_ex, :delete, :stop],
      [:storage_ex, :delete_prefixed, :stop],
      [:storage_ex, :exists?, :stop],
      [:storage_ex, :compose, :stop],
      [:storage_ex, :update_metadata, :stop],
      [:storage_ex, :upload, :exception],
      [:storage_ex, :download, :exception],
      [:storage_ex, :delete, :exception]
    ]

    :telemetry.attach_many(
      "storage-ex-default-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:storage_ex, operation, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Extract key from args if present (first arg for most operations)
    key =
      case metadata.args do
        [key | _] when is_binary(key) -> key
        _ -> nil
      end

    Logger.debug("StorageEx.#{operation} completed",
      key: key,
      service: inspect(metadata.service),
      duration_ms: duration_ms
    )
  end

  def handle_event([:storage_ex, operation, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Extract key from args if present
    key =
      case metadata.args do
        [key | _] when is_binary(key) -> key
        _ -> nil
      end

    Logger.error("StorageEx.#{operation} failed",
      key: key,
      service: inspect(metadata.service),
      duration_ms: duration_ms,
      error: Exception.message(metadata.reason)
    )
  end
end
