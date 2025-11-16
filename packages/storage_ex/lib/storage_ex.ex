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

  defp get_service(opts) do
    Config.get_service!(Keyword.get(opts, :service_name))
  end
end
