defmodule StorageEx.Dispatcher do
  @moduledoc false

  alias StorageEx.Notifications

  # Dynamically dispatches behaviour calls to the service module
  # with telemetry instrumentation.
  #
  # Example:
  # `Dispatcher.call(:upload, [service, key, data, opts])`
  #
  # This reduces boilerplate in `StorageEx` module and provides
  # centralized telemetry instrumentation for all operations.
  def call(fun, [service | args]) do
    mod = service.__struct__
    metadata = %{service: mod, args: args}

    Notifications.span(fun, metadata, fn ->
      apply(mod, fun, [service | args])
    end)
  end
end
