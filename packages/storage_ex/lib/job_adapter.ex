defmodule StorageEx.JobAdapter do
  @moduledoc """
  Behaviour for job queue adapters to handle StorageEx async operations.

  StorageEx provides async versions of heavy operations like file analysis,
  purging, preview generation, and variant transformation. These operations
  can run synchronously (blocking) or be delegated to a job queue.

  ## Built-in Adapters

  StorageEx ships with two built-in adapters:

    * `StorageEx.JobAdapters.Async` - Default. Runs jobs in separate Tasks (non-blocking).
      Like Rails' default `:async` adapter - fire-and-forget, no persistence.

    * `StorageEx.JobAdapters.Inline` - Runs jobs synchronously (blocking).
      Good for tests and simple apps that don't need background processing.

  ## External Adapters

  For production use with job persistence, retries, and monitoring:

    * `StorageExOban` - Oban adapter (separate package `storage_ex_oban`)

  ## Configuration

      # Async adapter (default) - fire-and-forget Tasks, like Rails
      config :storage_ex, job_adapter: StorageEx.JobAdapters.Async

      # Inline adapter - runs synchronously (good for tests)
      config :storage_ex, job_adapter: StorageEx.JobAdapters.Inline

      # Oban adapter (requires storage_ex_oban package) - persistence & retries
      config :storage_ex, job_adapter: StorageExOban

  ## Implementing a Custom Adapter

  To create a custom adapter, implement all callbacks:

      defmodule MyApp.CustomJobAdapter do
        @behaviour StorageEx.JobAdapter

        @impl true
        def enqueue_analyze(key, content_type, opts) do
          # Enqueue analysis job
          {:ok, job_id}
        end

        @impl true
        def enqueue_purge(key, service_name, opts) do
          # Enqueue purge job
          {:ok, job_id}
        end

        # ... implement all callbacks
      end

  ## Job Types

  | Job Type | Function | Purpose |
  |----------|----------|---------|
  | Analyze | `enqueue_analyze/3` | Extract metadata from files |
  | Purge | `enqueue_purge/3` | Delete files from storage |
  | Preview | `enqueue_preview/2` | Generate preview images |
  | Transform | `enqueue_transform/3` | Create image variants |
  """

  # --- Types ---

  @typedoc "Job identifier returned by adapters"
  @type job_id :: term()

  @typedoc "Job enqueue result"
  @type enqueue_result :: {:ok, job_id()} | {:error, term()}

  @typedoc "Storage service name"
  @type service_name :: atom()

  @typedoc "Image dimensions as [width, height]"
  @type dimensions :: [pos_integer()]

  @typedoc "Crop coordinates as [x, y, width, height]"
  @type crop_coords :: [non_neg_integer()]

  @typedoc "Image output format"
  @type image_format :: :png | :jpg | :jpeg | :webp | :gif | :avif

  @typedoc "Preview output format"
  @type preview_format :: :png | :jpg

  @typedoc """
  Options for `enqueue_analyze/3`.

    * `:service_name` - Storage service containing the file (default: configured default service)
  """
  @type analyze_opts :: [
          service_name: service_name()
        ]

  @typedoc """
  Options for `enqueue_purge/3`.

  Currently no options are used, but the parameter is kept for future extensibility.
  """
  @type purge_opts :: []

  @typedoc """
  Options for `enqueue_preview/2`.

    * `:content_type` - MIME type of the source file (required for previewer selection)
    * `:service_name` - Storage service containing the file
    * `:format` - Output image format (`:png` or `:jpg`, default: `:png`)
    * `:time` - Time position for video previews (e.g., `"00:00:05"` or `5.0`)
  """
  @type preview_opts :: [
          content_type: String.t(),
          service_name: service_name(),
          format: preview_format(),
          time: String.t() | float()
        ]

  @typedoc """
  Image transformation options for `enqueue_transform/3`.

    * `:resize_to_limit` - Resize to fit within dimensions, maintaining aspect ratio
    * `:resize_to_fit` - Resize to exact dimensions, may distort
    * `:resize_to_fill` - Resize and crop to exact dimensions
    * `:crop` - Crop region as `[x, y, width, height]`
    * `:rotate` - Rotation angle in degrees
    * `:quality` - Output quality for lossy formats (1-100)
    * `:format` - Output format (`:png`, `:jpg`, `:webp`, etc.)
  """
  @type transformations :: [
          resize_to_limit: dimensions(),
          resize_to_fit: dimensions(),
          resize_to_fill: dimensions(),
          crop: crop_coords(),
          rotate: number(),
          quality: 1..100,
          format: image_format()
        ]

  @typedoc """
  Additional options for `enqueue_transform/3`.

    * `:service_name` - Storage service containing the file
  """
  @type transform_opts :: [
          service_name: service_name()
        ]

  # --- Callbacks ---

  @doc """
  Enqueue a file analysis job.

  Analyzes a file to extract metadata (dimensions, duration, etc.).

  ## Parameters

    * `key` - Storage key of the file to analyze
    * `content_type` - MIME type for analyzer selection
    * `opts` - Analysis options:
      * `:service_name` - Service containing the file (atom)

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Example

      {:ok, job_id} = MyAdapter.enqueue_analyze("photo.jpg", "image/jpeg",
        service_name: :local
      )
  """
  @callback enqueue_analyze(
              key :: String.t(),
              content_type :: String.t(),
              opts :: analyze_opts()
            ) :: enqueue_result()

  @doc """
  Enqueue a file purge (deletion) job.

  Deletes a file from storage. Use this instead of direct deletion when
  you need the operation to happen outside the current request.

  ## Parameters

    * `key` - Storage key of the file to delete
    * `service_name` - Service containing the file (atom)
    * `opts` - Reserved for future use

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Example

      {:ok, job_id} = MyAdapter.enqueue_purge("old_photo.jpg", :local, [])
  """
  @callback enqueue_purge(
              key :: String.t(),
              service_name :: service_name(),
              opts :: purge_opts()
            ) :: enqueue_result()

  @doc """
  Enqueue a preview generation job.

  Generates a preview image from a non-image file (PDF, video, etc.).

  ## Parameters

    * `key` - Storage key of the source file
    * `opts` - Preview options:
      * `:content_type` - MIME type of the source file (required)
      * `:service_name` - Service containing the file (atom)
      * `:format` - Output format (`:png` or `:jpg`)
      * `:time` - Time position for video previews (e.g., `"00:00:05"`)

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Example

      {:ok, job_id} = MyAdapter.enqueue_preview("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05"
      )
  """
  @callback enqueue_preview(
              key :: String.t(),
              opts :: preview_opts()
            ) :: enqueue_result()

  @doc """
  Enqueue an image transformation job.

  Generates a transformed variant of an image (resize, crop, format conversion).

  ## Parameters

    * `key` - Storage key of the source image
    * `transformations` - Transformation options:
      * `:resize_to_limit` - Resize to fit within `[width, height]`
      * `:resize_to_fit` - Resize to exact `[width, height]`
      * `:resize_to_fill` - Resize and crop to exact `[width, height]`
      * `:crop` - Crop image `[x, y, width, height]`
      * `:rotate` - Rotate by degrees
      * `:quality` - JPEG/WebP quality (1-100)
      * `:format` - Output format (`:png`, `:jpg`, `:webp`)
    * `opts` - Additional options:
      * `:service_name` - Service containing the file (atom)

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Example

      {:ok, job_id} = MyAdapter.enqueue_transform("photo.jpg",
        [resize_to_limit: [100, 100], format: :webp],
        service_name: :local
      )
  """
  @callback enqueue_transform(
              key :: String.t(),
              transformations :: transformations(),
              opts :: transform_opts()
            ) :: enqueue_result()
end
