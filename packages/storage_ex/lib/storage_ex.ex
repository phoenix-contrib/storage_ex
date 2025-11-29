defmodule StorageEx do
  @moduledoc """
  Public API for StorageEx.

  ## Examples

      # Upload a file to the default service
      StorageEx.upload("avatar.png", File.read!("avatar.png"))

      # Upload with content type and ACL
      StorageEx.upload("avatar.png", File.read!("avatar.png"),
        content_type: "image/png",
        acl: "public-read"
      )

      # Download a file
      {:ok, binary} = StorageEx.download("avatar.png")

      # Download as a stream (for large files)
      {:ok, stream} = StorageEx.download_stream("large_file.mp4")
      stream |> Stream.into(File.stream!("output.mp4")) |> Stream.run()

      # Check existence
      StorageEx.exists?("avatar.png")

      # Delete a file
      StorageEx.delete("avatar.png")

      # Compose multiple files into one
      StorageEx.compose(["part1.bin", "part2.bin"], "complete.bin")

      # Generate a signed URL
      {:ok, url} = StorageEx.url_for_direct_upload("avatar.png", expires_in: 600)

      # Update metadata
      StorageEx.update_metadata(key: "avatar.png", metadata: %{foo: "bar"})

  ## Image Variants

      # Create a variant (transformed image)
      variant = StorageEx.variant("photo.jpg", resize_to_limit: [100, 100], format: :webp)

      # Process the variant (generates if needed, returns cached if exists)
      {:ok, variant} = StorageEx.Variant.process(variant)

      # Download variant data
      {:ok, binary} = StorageEx.Variant.download(variant)

  ## Previews (PDF, Video)

      # Create a preview from a video
      preview = StorageEx.preview("video.mp4", content_type: "video/mp4")

      # Process the preview (generates if needed, returns cached if exists)
      {:ok, preview} = StorageEx.Preview.process(preview)

      # Get URL for the preview
      url = StorageEx.Preview.url(preview)

      # Preview from PDF
      preview = StorageEx.preview("document.pdf", content_type: "application/pdf")

  ## Preview Variants (Preview + Variant Combined)

      # Create thumbnail from video preview
      pv = StorageEx.preview_variant("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )

      {:ok, pv} = StorageEx.PreviewVariant.process(pv)
      url = StorageEx.PreviewVariant.url(pv)

  ## Analyzers (Metadata Extraction)

  StorageEx follows Rails ActiveStorage's dependency management: **always works, enhanced with optional tools**.

      # Image analysis - works without Image gem (returns empty), enhanced with Image/libvips
      {:ok, metadata} = StorageEx.analyze("photo.jpg", "image/jpeg", :local)
      # Without Image gem: %{}
      # With Image gem: %{width: 1024, height: 768}

      # Video analysis - works without FFmpeg (returns empty), enhanced with FFmpeg
      {:ok, metadata} = StorageEx.analyze("video.mp4", "video/mp4", :local)
      # Without FFmpeg: %{}
      # With FFmpeg: %{width: 640, height: 480, duration: 30.5, display_aspect_ratio: [4, 3]}

      # Audio analysis - works without FFmpeg (returns empty), enhanced with FFmpeg
      {:ok, metadata} = StorageEx.analyze("song.mp3", "audio/mpeg", :local)
      # Without FFmpeg: %{}
      # With FFmpeg: %{duration: 180.5, bit_rate: 320000, sample_rate: 44100}

      # Unknown content types use NullAnalyzer
      {:ok, metadata} = StorageEx.analyze("document.txt", "text/plain", :local)
      # => %{}

  ### Optional FFmpeg Enhancement

      # Install FFmpeg for video/audio analysis
      # macOS: brew install ffmpeg
      # Ubuntu: sudo apt install ffmpeg
      # Docker: RUN apk add --no-cache ffmpeg

      # Applications work immediately, enhanced when FFmpeg available
  """

  alias StorageEx.{Config, Dispatcher}

  # --- Upload ---

  @doc "Upload binary/stream/path to the given key."
  def upload(key, data, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:upload, [service, key, data, opts])
  end

  # --- Download ---

  @doc "Download the full file content."
  def download(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:download, [service, key])
  end

  @doc "Download a byte range from the file."
  def download_chunk(key, range, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:download_chunk, [service, key, range])
  end

  @doc "Download the file as a stream (5MB chunks by default)."
  def download_stream(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:download_stream, [service, key])
  end

  # --- Metadata ---

  @doc "Update metadata for a file on the provider."
  def update_metadata(opts) do
    service = get_service(opts)
    Dispatcher.call(:update_metadata, [service, opts[:key], opts[:metadata]])
  end

  # --- File management ---

  @doc "Compose multiple source files into a single destination file."
  def compose(source_keys, destination_key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:compose, [service, source_keys, destination_key, opts])
  end

  @doc "Delete a file."
  def delete(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:delete, [service, key])
  end

  @doc "Delete all files under the given prefix."
  def delete_prefixed(prefix, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:delete_prefixed, [service, prefix])
  end

  @doc "Check if a file exists."
  def exists?(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:exists?, [service, key])
  end

  # --- URL helpers ---

  @doc """
  Generate a signed URL for downloading the given key.

  ## Options

    * `:endpoint` - Phoenix endpoint module (optional if configured globally)
    * `:expires_in` - URL expiration in seconds (default: 300)
    * `:filename` - Original filename
    * `:disposition` - `:inline` or `:attachment` (default: `:inline`)
    * `:content_type` - MIME type

  Configure endpoint globally:

      config :storage_ex, endpoint: MyAppWeb.Endpoint

  ## Examples

      # Using configured endpoint
      StorageEx.url("avatar.png", filename: "avatar.png")

      # Overriding endpoint
      StorageEx.url("avatar.png", endpoint: MyAppWeb.Endpoint, filename: "avatar.png")
  """
  def url(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:url, [service, key, opts])
  end

  @doc """
  Generate a signed URL for direct client upload.

  ## Options

    * `:endpoint` - Phoenix endpoint module (optional if configured globally)
    * `:expires_in` - URL expiration in seconds (default: 300)
    * `:content_type` - Expected MIME type
    * `:content_length` - Expected file size in bytes
    * `:checksum` - Expected MD5 checksum (Base64 encoded)

  Configure endpoint globally:

      config :storage_ex, endpoint: MyAppWeb.Endpoint

  ## Examples

      # Using configured endpoint
      {:ok, url} = StorageEx.url_for_direct_upload("avatar.png",
        content_type: "image/png",
        content_length: 1024
      )

      # Overriding endpoint
      {:ok, url} = StorageEx.url_for_direct_upload("avatar.png",
        endpoint: MyAppWeb.Endpoint,
        content_type: "image/png",
        content_length: 1024
      )
  """
  def url_for_direct_upload(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:url_for_direct_upload, [service, key, opts])
  end

  @doc "Return headers required for direct upload."
  def headers_for_direct_upload(key, opts \\ []) do
    service = get_service(opts)
    Dispatcher.call(:headers_for_direct_upload, [service, key, opts])
  end

  # --- Image Variants ---

  @doc """
  Creates a variant specification for a blob.

  Returns a `StorageEx.Variant` struct that can be processed to generate
  a transformed version of the image.

  ## Parameters

    * `key` - The storage key of the original blob
    * `transformations` - Keyword list of image transformations to apply
    * `opts` - Options (currently only `:service_name`)

  ## Transformation Options

    * `:resize_to_limit` - Resize to fit within dimensions `[width, height]`
    * `:resize_to_fit` - Resize to exact dimensions `[width, height]`
    * `:resize_to_fill` - Resize and crop to exact dimensions `[width, height]`
    * `:crop` - Crop image `[x, y, width, height]`
    * `:rotate` - Rotate image by degrees
    * `:quality` - JPEG/WebP quality (1-100)
    * `:format` - Output format (`:png`, `:jpg`, `:webp`, `:gif`, `:tiff`)

  ## Service Options

    * `:service_name` - The service name (atom) to use. If nil, uses the default service.
      Note: Following Rails' design, variants should use the same service as the original blob.

  ## Examples

      # Create thumbnail variant with default service
      variant = StorageEx.variant("photo.jpg", resize_to_limit: [100, 100])

      # Create WebP variant with quality
      variant = StorageEx.variant("photo.jpg",
        resize_to_fill: [200, 200],
        quality: 85,
        format: :webp
      )

      # Use specific service
      variant = StorageEx.variant("avatar.jpg", [resize_to_limit: [100, 100]], service_name: :s3)

      # Process and download
      {:ok, variant} = StorageEx.Variant.process(variant)
      {:ok, binary} = StorageEx.Variant.download(variant)
  """
  def variant(key, transformations, opts \\ []) do
    service_name = Keyword.get(opts, :service_name)
    StorageEx.Variant.new(key, transformations, service_name)
  end

  # --- Previews ---

  @doc """
  Creates a preview specification for a non-image blob (PDF, video, etc.).

  Returns a `StorageEx.Preview` struct that can be processed to extract
  a preview image from the blob.

  ## Parameters

    * `key` - The storage key of the original blob
    * `opts` - Preview options:
      * `:content_type` - MIME type of the blob (required)
      * `:format` - Output format (`:png` or `:jpg`, default: `:png`)
      * `:service_name` - The service name (atom) to use (nil for default)
      * Additional previewer-specific options

  ## Previewer-Specific Options

  ### Video Previews (requires FFmpeg)
    * `:time` - Time position to extract frame from (e.g., "00:00:05")

  ### PDF Previews (requires Poppler or MuPDF)
    * No additional options (renders first page)

  ## Service Options

    * `:service_name` - The service name (atom) to use. If nil, uses the default service.
      Note: Following Rails' design, previews are stored in the same service as the original blob.

  ## Examples

      # Create video preview
      preview = StorageEx.preview("video.mp4", content_type: "video/mp4")

      # Video preview at specific time
      preview = StorageEx.preview("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05"
      )

      # PDF preview as JPEG
      preview = StorageEx.preview("document.pdf",
        content_type: "application/pdf",
        format: :jpg
      )

      # Use specific service
      preview = StorageEx.preview("video.mp4",
        content_type: "video/mp4",
        service_name: :s3
      )

      # Process and download
      {:ok, preview} = StorageEx.Preview.process(preview)
      {:ok, binary} = StorageEx.Preview.download(preview)

      # Get URL
      url = StorageEx.Preview.url(preview)
  """
  def preview(key, opts) when is_binary(key) and is_list(opts) do
    StorageEx.Preview.new(key, opts)
  end

  # --- Preview Variants ---

  @doc """
  Creates a preview variant specification (preview + variant combined).

  This combines preview generation and variant transformation into a single
  operation, providing a more convenient API similar to Rails' ActiveStorage.

  ## Parameters

    * `key` - The storage key of the original blob
    * `opts` - Preview and variant options:
      * `:content_type` - MIME type of the blob (required)
      * `:variant` - Variant transformations to apply (optional)
      * `:format` - Preview output format (`:png` or `:jpg`, default: `:png`)
      * `:service_name` - The service name (atom) to use (nil for default)
      * Additional preview-specific options (e.g., `:time` for videos)

  ## Examples

      # Video preview with thumbnail variant
      pv = StorageEx.preview_variant("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )

      # Process and get URL
      {:ok, pv} = StorageEx.PreviewVariant.process(pv)
      url = StorageEx.PreviewVariant.url(pv)

      # With preview options
      pv = StorageEx.preview_variant("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05",
        variant: [resize_to_fill: [200, 200], format: :webp]
      )

      # PDF preview as thumbnail
      pv = StorageEx.preview_variant("document.pdf",
        content_type: "application/pdf",
        variant: [resize_to_limit: [300, 300]]
      )

      # Preview without variant (equivalent to StorageEx.preview/2)
      pv = StorageEx.preview_variant("video.mp4", content_type: "video/mp4")
  """
  def preview_variant(key, opts) when is_binary(key) and is_list(opts) do
    StorageEx.PreviewVariant.new(key, opts)
  end

  # --- Async Jobs (Background Processing) ---

  @doc """
  Enqueues an analysis job to run in the background.

  This is the async version of `analyze/3`. It enqueues a job to extract
  metadata from a file without blocking the current process.

  By default, uses `StorageEx.JobAdapters.Async` which runs jobs in
  lightweight Elixir Tasks (fire-and-forget, like Rails' default).

  ## Parameters

    * `key` - Storage key of the file to analyze
    * `content_type` - MIME type for analyzer selection
    * `opts` - Options:
      * `:service_name` - Service containing the file (default: default service)

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Examples

      # Async analysis (non-blocking)
      {:ok, ref} = StorageEx.analyze_later("photo.jpg", "image/jpeg")

      # With specific service
      {:ok, ref} = StorageEx.analyze_later("video.mp4", "video/mp4",
        service_name: :s3
      )
  """
  @spec analyze_later(String.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def analyze_later(key, content_type, opts \\ []) do
    Config.job_adapter().enqueue_analyze(key, content_type, opts)
  end

  @doc """
  Enqueues a file deletion job to run in the background.

  This is the async version of `delete/2`. It enqueues a job to delete
  a file without blocking the current process.

  ## Parameters

    * `key` - Storage key of the file to delete
    * `opts` - Options:
      * `:service_name` - Service containing the file (default: default service)

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Examples

      # Async deletion (non-blocking)
      {:ok, ref} = StorageEx.purge_later("old_photo.jpg")

      # With specific service
      {:ok, ref} = StorageEx.purge_later("old_video.mp4", service_name: :s3)
  """
  @spec purge_later(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def purge_later(key, opts \\ []) do
    service_name = Keyword.get(opts, :service_name) || Config.default_service()
    Config.job_adapter().enqueue_purge(key, service_name, opts)
  end

  @doc """
  Enqueues a preview generation job to run in the background.

  This is the async version of `Preview.process/1`. It enqueues a job to
  generate a preview image from a non-image file (PDF, video, etc.).

  ## Parameters

    * `key` - Storage key of the source file
    * `opts` - Preview options:
      * `:content_type` - MIME type of the source file (required)
      * `:format` - Output format (`:png` or `:jpg`)
      * `:service_name` - Service containing the file
      * `:time` - Time position for video previews

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Examples

      # Async video preview
      {:ok, ref} = StorageEx.preview_later("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05"
      )

      # Async PDF preview
      {:ok, ref} = StorageEx.preview_later("document.pdf",
        content_type: "application/pdf"
      )
  """
  @spec preview_later(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def preview_later(key, opts) do
    Config.job_adapter().enqueue_preview(key, opts)
  end

  @doc """
  Enqueues an image transformation job to run in the background.

  This is the async version of `Variant.process/1`. It enqueues a job to
  create a transformed version of an image.

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
      * `:service_name` - Service containing the file

  ## Returns

    * `{:ok, job_id}` - Job successfully enqueued
    * `{:error, reason}` - Failed to enqueue

  ## Examples

      # Async thumbnail generation
      {:ok, ref} = StorageEx.transform_later("photo.jpg",
        resize_to_limit: [100, 100],
        format: :webp
      )

      # With specific service
      {:ok, ref} = StorageEx.transform_later("image.png",
        [resize_to_fill: [200, 200]],
        service_name: :s3
      )
  """
  @spec transform_later(String.t(), keyword(), keyword()) :: {:ok, term()} | {:error, term()}
  def transform_later(key, transformations, opts \\ []) do
    Config.job_adapter().enqueue_transform(key, transformations, opts)
  end

  # --- Analyzers ---

  @doc """
  Analyzes a file and extracts metadata.

  Downloads the file from storage and runs it through the appropriate analyzer
  to extract metadata such as dimensions, duration, or other file properties.

  This is fully compatible with Rails ActiveStorage analyzer functionality, including
  the same graceful dependency handling strategy.

  ## Rails-Style Dependency Management

  StorageEx follows Rails ActiveStorage's proven approach to external dependencies:

  ### ✅ Progressive Enhancement (Never Breaks Apps)

  - **Image Analysis**: Returns empty `%{}` without Image/libvips, rich metadata with Image/libvips
  - **Video Analysis**: Returns empty `%{}` without FFmpeg, rich metadata with FFmpeg
  - **Audio Analysis**: Returns empty `%{}` without FFmpeg, rich metadata with FFmpeg

  ### 🔧 Optional Dependency Installation

      # Image analysis enhancement
      # Add to mix.exs: {:image, "~> 0.54"}
      # macOS: brew install vips
      # Ubuntu: sudo apt install libvips-dev

      # Video/Audio analysis enhancement
      # macOS: brew install ffmpeg
      # Ubuntu: sudo apt install ffmpeg
      # Docker: apk add --no-cache ffmpeg

  ### 📊 User Experience Examples

      # Without dependencies - works immediately
      {:ok, %{}} = StorageEx.analyze("photo.jpg", "image/jpeg", :local)
      # Log: [error] Skipping image analysis because the image gem isn't installed

      {:ok, %{}} = StorageEx.analyze("video.mp4", "video/mp4", :local)
      # Log: [info] Skipping video analysis because ffprobe isn't installed

      # With dependencies - enhanced metadata
      {:ok, %{width: 1024, height: 768}} = StorageEx.analyze("photo.jpg", "image/jpeg", :local)
      {:ok, %{width: 640.0, height: 480.0, duration: 5.1}} = StorageEx.analyze("video.mp4", "video/mp4", :local)

  ## Parameters

    * `key` - The storage key of the file to analyze
    * `content_type` - MIME type of the file
    * `service_name` - The service name (atom) to use

  ## Returns

    * `{:ok, metadata}` - Analysis successful, metadata is a map (empty if analyzer unavailable)
    * `{:error, reason}` - Analysis failed (file not found, invalid format, etc.)

  ## Metadata Examples

      # Image analysis (enhanced with Image gem)
      StorageEx.analyze("photo.jpg", "image/jpeg", :local)
      #=> {:ok, %{width: 1024, height: 768}}

      # Video analysis (enhanced with FFmpeg)
      StorageEx.analyze("video.mp4", "video/mp4", :local)
      #=> {:ok, %{width: 640, height: 480, duration: 30.5, display_aspect_ratio: [4, 3]}}

      # Audio analysis (enhanced with FFmpeg)
      StorageEx.analyze("song.mp3", "audio/mpeg", :local)
      #=> {:ok, %{duration: 180.5, bit_rate: 320000, sample_rate: 44100}}

      # Unknown content type (uses NullAnalyzer)
      StorageEx.analyze("document.txt", "text/plain", :local)
      #=> {:ok, %{}}

  ## Examples

      # Basic usage
      {:ok, metadata} = StorageEx.analyze("avatar.png", "image/png", :local)
      width = metadata.width
      height = metadata.height

      # Use different storage service
      {:ok, metadata} = StorageEx.analyze("video.mp4", "video/mp4", :s3)

      # Handle different scenarios
      case StorageEx.analyze("media.mov", "video/quicktime", :local) do
        {:ok, metadata} when map_size(metadata) > 0 ->
          # Rich metadata available - FFmpeg installed and working
          process_video_metadata(metadata)
        {:ok, %{}} ->
          # FFmpeg not available - install for enhanced video analysis
          log_ffmpeg_suggestion()
        {:error, reason} ->
          # Analysis failed - file not found, invalid format, etc.
          handle_analysis_error(reason)
      end

  This ensures applications work **immediately out-of-the-box** while providing clear
  paths for enhanced functionality as requirements grow.
  """
  @spec analyze(String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def analyze(key, content_type, service_name) when is_atom(service_name) do
    StorageEx.Analyzer.analyze(key, content_type, service_name)
  end

  defp get_service(opts) do
    Config.get_service!(Keyword.get(opts, :service_name))
  end
end
