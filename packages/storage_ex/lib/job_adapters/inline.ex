defmodule StorageEx.JobAdapters.Inline do
  @moduledoc """
  Inline job adapter that executes jobs synchronously.

  This adapter runs all operations immediately in the current process,
  blocking until completion. It's useful for:

    * **Testing** - Predictable, synchronous execution
    * **Simple apps** - No background processing complexity
    * **Development** - See results immediately

  ## Configuration

      config :storage_ex, job_adapter: StorageEx.JobAdapters.Inline

  ## Behavior

  All `*_later` functions will execute immediately and return:

    * `{:ok, :completed}` - Operation completed successfully
    * `{:error, reason}` - Operation failed

  ## Example

      # Configure inline adapter
      config :storage_ex, job_adapter: StorageEx.JobAdapters.Inline

      # This will analyze the file immediately (blocking)
      {:ok, :completed} = StorageEx.analyze_later("photo.jpg", "image/jpeg", :local)

      # Same as calling the sync version directly
      {:ok, metadata} = StorageEx.analyze("photo.jpg", "image/jpeg", :local)

  ## Trade-offs

  | Aspect | Inline Adapter |
  |--------|----------------|
  | Blocking | Yes - blocks current process |
  | Persistence | No - lost on crash |
  | Retries | No - fails immediately |
  | Monitoring | No - no job visibility |
  | Best for | Tests, simple apps |

  For production apps needing persistence and retries, use `StorageExOban`.
  """

  @behaviour StorageEx.JobAdapter

  @impl true
  def enqueue_analyze(key, content_type, opts) do
    service_name = Keyword.get(opts, :service_name) || StorageEx.Config.default_service()

    case StorageEx.analyze(key, content_type, service_name) do
      {:ok, _metadata} -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def enqueue_purge(key, service_name, _opts) do
    case StorageEx.delete(key, service_name: service_name) do
      :ok -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def enqueue_preview(key, opts) do
    preview = StorageEx.preview(key, opts)

    case StorageEx.Preview.process(preview) do
      {:ok, _preview} -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def enqueue_transform(key, transformations, opts) do
    service_name = Keyword.get(opts, :service_name)
    variant = StorageEx.variant(key, transformations, service_name: service_name)

    case StorageEx.Variant.process(variant) do
      {:ok, _variant} -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end
end
