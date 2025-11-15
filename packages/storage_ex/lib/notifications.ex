defmodule StorageEx.Notifications do
  @moduledoc """
  Centralized telemetry wrapper for StorageEx instrumentation.

  Similar to Rails' ActiveSupport::Notifications, this module provides
  a pub/sub pattern for instrumentation and metrics using Erlang's `:telemetry`.

  All events are prefixed with `[:storage_ex]`.

  ## Measurements

  All `:stop` events include:

    * `:duration` - The time in native units it took to execute the operation

  ## Metadata

  All events include:

    * `:service` - The service module name (e.g., `StorageEx.Services.Disk`)
    * `:operation` - The operation name (e.g., `:upload`, `:download`)
    * `:args` - List of arguments passed to the operation (raw, without the service struct)

  You can extract operation-specific metadata from `:args` in your handlers:

    * For `:upload` - `[key, data, opts]`
    * For `:download` - `[key]`
    * For `:download_chunk` - `[key, range]`
    * For `:delete` - `[key]`
    * For `:compose` - `[source_keys, destination_key, opts]`
    * etc.

  ## Example: Attaching a Handler

      :telemetry.attach(
        "storage-ex-handler",
        [:storage_ex, :upload, :stop],
        &MyApp.Telemetry.handle_event/4,
        nil
      )

      defmodule MyApp.Telemetry do
        def handle_event([:storage_ex, :upload, :stop], measurements, metadata, _config) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

          # Extract key and opts from args
          [key, _data, opts] = metadata.args

          Logger.info("File uploaded",
            key: key,
            service: metadata.service,
            duration_ms: duration_ms,
            checksum: opts[:checksum]
          )
        end
      end

  ## Example: Attaching Multiple Handlers

      events = [
        [:storage_ex, :upload, :stop],
        [:storage_ex, :download, :stop],
        [:storage_ex, :delete, :stop]
      ]

      :telemetry.attach_many(
        "storage-ex-logger",
        events,
        &MyApp.Telemetry.handle_event/4,
        nil
      )
  """

  @prefix [:storage_ex]

  @doc """
  Execute telemetry span for an operation.

  Emits `:start`, `:stop`, and `:exception` events automatically.

  ## Parameters

    * `operation` - The operation name (e.g., `:upload`, `:download`)
    * `metadata` - Map with operation metadata (must include `:service`)
    * `fun` - Function to execute within the span

  ## Example

      result = Notifications.span(:upload, %{service: service, args: [key]}, fn ->
        # perform upload
        {:ok, result}
      end)
      # Returns: {:ok, result}
  """
  def span(operation, metadata, fun) when is_atom(operation) and is_map(metadata) do
    event = @prefix ++ [operation]
    start_metadata = Map.put(metadata, :operation, operation)

    # :telemetry.span/3 expects a function that returns {Result, Metadata}
    # It emits start/stop/exception events and returns just Result (unwrapped)
    :telemetry.span(event, start_metadata, fn ->
      result = fun.()
      {result, start_metadata}
    end)
  end

  @doc """
  Execute a telemetry event immediately.

  Used for operations that don't need start/stop timing.

  ## Parameters

    * `operation` - The operation name as a list or atom
    * `measurements` - Map with measurements (e.g., `%{count: 1}`)
    * `metadata` - Map with operation metadata

  ## Example

      Notifications.execute(:cache_hit, %{count: 1}, %{key: key})
  """
  def execute(operation, measurements \\ %{}, metadata \\ %{})

  def execute(operation, measurements, metadata) when is_atom(operation) do
    execute([operation], measurements, metadata)
  end

  def execute(operation, measurements, metadata) when is_list(operation) do
    event = @prefix ++ operation
    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Get the telemetry prefix used by StorageEx.

  Returns `[:storage_ex]`.
  """
  def prefix, do: @prefix
end
