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

  defp get_service(opts) do
    Config.get_service!(Keyword.get(opts, :service_name))
  end
end
