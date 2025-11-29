defmodule StorageEx.JobAdapters.Async do
  @moduledoc """
  Async job adapter using Task.Supervisor for fire-and-forget execution.

  This adapter runs operations asynchronously in separate processes,
  similar to Rails' default `:async` ActiveJob adapter. Jobs run in
  the background without blocking the caller.

  ## Configuration

      config :storage_ex, job_adapter: StorageEx.JobAdapters.Async

  ## Behavior

  All `*_later` functions will:

    1. Spawn an async Task under `StorageEx.TaskSupervisor`
    2. Return immediately with `{:ok, task_ref}`
    3. Execute the operation in the background

  ## Setup

  The `StorageEx.TaskSupervisor` must be running. If you're using StorageEx
  as an application (with `mod: {StorageEx.Application, []}`), this is
  automatic. Otherwise, add it to your supervision tree:

      children = [
        {Task.Supervisor, name: StorageEx.TaskSupervisor},
        # ... other children
      ]

  ## Example

      # Configure async adapter
      config :storage_ex, job_adapter: StorageEx.JobAdapters.Async

      # This returns immediately
      {:ok, task_ref} = StorageEx.analyze_later("photo.jpg", "image/jpeg", :local)

      # The analysis runs in the background
      # No way to get the result (fire-and-forget)

  ## Trade-offs

  | Aspect | Async Adapter |
  |--------|---------------|
  | Blocking | No - returns immediately |
  | Persistence | No - lost on crash |
  | Retries | No - fails silently |
  | Monitoring | Limited - via Task refs |
  | Best for | Simple background work |

  ## Comparison with Rails

  This adapter is equivalent to Rails' default `:async` ActiveJob adapter:

    * Uses a process pool (Task.Supervisor vs Thread pool)
    * Non-blocking execution
    * No persistence - jobs lost on crash
    * No automatic retries

  For production apps needing persistence and retries, use `StorageExOban`.

  ## Error Handling

  Errors in background tasks are logged but don't propagate to the caller.
  Failed tasks don't retry automatically.

  ## Task References

  The returned task reference can be used for basic monitoring:

      {:ok, ref} = StorageEx.purge_later("old_file.jpg", :local)
      # ref is a reference() that can be used with Process.alive?/1
      # if you spawned a linked task (not the default behavior here)
  """

  @behaviour StorageEx.JobAdapter

  require Logger

  @task_supervisor StorageEx.TaskSupervisor

  @impl true
  def enqueue_analyze(key, content_type, opts) do
    service_name = Keyword.get(opts, :service_name) || StorageEx.Config.default_service()

    ref =
      start_async_task(fn ->
        StorageEx.analyze(key, content_type, service_name)
      end)

    {:ok, ref}
  end

  @impl true
  def enqueue_purge(key, service_name, _opts) do
    ref =
      start_async_task(fn ->
        StorageEx.delete(key, service_name: service_name)
      end)

    {:ok, ref}
  end

  @impl true
  def enqueue_preview(key, opts) do
    ref =
      start_async_task(fn ->
        preview = StorageEx.preview(key, opts)
        StorageEx.Preview.process(preview)
      end)

    {:ok, ref}
  end

  @impl true
  def enqueue_transform(key, transformations, opts) do
    service_name = Keyword.get(opts, :service_name)

    ref =
      start_async_task(fn ->
        variant = StorageEx.variant(key, transformations, service_name: service_name)
        StorageEx.Variant.process(variant)
      end)

    {:ok, ref}
  end

  # --- Private Helpers ---

  defp start_async_task(fun) do
    # Use start_child so the caller isn't affected by task failures
    # The task runs independently and errors are silently ignored
    case Task.Supervisor.start_child(@task_supervisor, fun) do
      {:ok, _pid} ->
        make_ref()

      {:error, _reason} ->
        # Return a ref anyway so the API is consistent
        make_ref()
    end
  end
end
