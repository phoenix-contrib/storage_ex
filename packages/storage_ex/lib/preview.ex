defmodule StorageEx.Preview do
  @moduledoc """
  Represents a preview image extracted from a non-image blob (PDF, video, etc.).

  Previews are lazily processed and cached in the storage service,
  similar to Rails' ActiveStorage::Preview.

  ## JSON Serialization

  Previews can be serialized to JSON for use in JSON APIs or Inertia.js props:

      # Using Jason encoder (automatic)
      preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
      Jason.encode!(preview)
      # => {"url": "/path/to/preview", "key": "...", ...}

  ## Examples

      # Create a preview specification
      preview = StorageEx.Preview.new("video.mp4",
        content_type: "video/mp4"
      )

      # Process the preview (generates if needed, returns cached if exists)
      {:ok, preview} = StorageEx.Preview.process(preview)

      # Get the storage key for the preview
      key = StorageEx.Preview.key(preview)

      # Download the preview data
      {:ok, data} = StorageEx.Preview.download(preview)

      # Get a URL for the preview
      url = StorageEx.Preview.url(preview)

  ## Preview Options

  Different previewers support different options:

  ### Video Previews (FFmpeg)
    * `:time` - Time position to extract frame from (default: first frame)

      preview = StorageEx.Preview.new("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05"
      )

  ### PDF Previews (Poppler/MuPDF)
    * No additional options currently supported (renders first page)

  ## Format Options

  You can specify the output format for the preview:

      preview = StorageEx.Preview.new("document.pdf",
        content_type: "application/pdf",
        format: :jpg  # or :png (default)
      )
  """

  alias StorageEx.Previewer

  require Logger

  @derive {Jason.Encoder, only: []}
  defstruct [:blob_key, :content_type, :format, :preview_options, :service_name]

  @type t :: %__MODULE__{
          blob_key: String.t(),
          content_type: String.t(),
          format: atom(),
          preview_options: keyword(),
          service_name: atom() | nil
        }

  @doc """
  Creates a new Preview specification.

  ## Parameters

    * `blob_key` - The key of the original blob in storage
    * `opts` - Options:
      * `:content_type` - MIME type of the blob (required)
      * `:format` - Output format (`:png` or `:jpg`, default: `:png`)
      * `:service_name` - Service name (atom) or nil for default service
      * Additional previewer-specific options (e.g., `:time` for videos)

  Note: Following Rails' design, previews are stored in the same service as the original blob.

  ## Examples

      # Video preview with default options
      preview = StorageEx.Preview.new("video.mp4", content_type: "video/mp4")

      # Video preview at specific time
      preview = StorageEx.Preview.new("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05"
      )

      # PDF preview as JPEG
      preview = StorageEx.Preview.new("document.pdf",
        content_type: "application/pdf",
        format: :jpg
      )

      # Use specific service
      preview = StorageEx.Preview.new("video.mp4",
        content_type: "video/mp4",
        service_name: :s3
      )
  """
  def new(blob_key, opts) when is_binary(blob_key) and is_list(opts) do
    content_type = Keyword.fetch!(opts, :content_type)
    format = Keyword.get(opts, :format, :png)
    service_name = Keyword.get(opts, :service_name)

    # Extract preview-specific options (e.g., :time for videos)
    preview_options =
      opts
      |> Keyword.drop([:content_type, :format, :service_name])

    %__MODULE__{
      blob_key: blob_key,
      content_type: content_type,
      format: format,
      preview_options: preview_options,
      service_name: service_name
    }
  end

  @doc """
  Returns the storage key for this preview.

  Previews are stored at: `previews/{blob_key}/{preview_hash}`

  The hash is derived from the content type and preview options to ensure
  different preview configurations generate different cached previews.
  """
  def key(%__MODULE__{blob_key: blob_key} = preview) do
    preview_key = generate_preview_key(preview)
    "previews/#{blob_key}/#{preview_key}"
  end

  @doc """
  Checks if the preview has been processed and exists in storage.
  """
  def processed?(%__MODULE__{service_name: service_name} = preview) do
    preview_key = key(preview)
    StorageEx.exists?(preview_key, service_name: service_name)
  end

  @doc """
  Processes the preview if not already processed.

  This downloads the original blob, extracts a preview image using the
  appropriate previewer, and uploads the result to storage.

  Returns `{:ok, preview}` if successful or already processed.
  Returns `{:error, reason}` if processing fails.

  ## Examples

      preview = StorageEx.Preview.new("video.mp4", content_type: "video/mp4")
      {:ok, preview} = StorageEx.Preview.process(preview)
  """
  def process(%__MODULE__{} = preview) do
    if processed?(preview) do
      {:ok, preview}
    else
      do_process(preview)
    end
  end

  @doc """
  Downloads the preview data.

  Processes the preview first if it hasn't been processed yet.

  Returns `{:ok, binary_data}` on success.
  """
  def download(%__MODULE__{service_name: service_name} = preview) do
    with {:ok, _} <- process(preview) do
      preview_key = key(preview)
      StorageEx.download(preview_key, service_name: service_name)
    end
  end

  @doc """
  Returns a URL for the preview.

  Processes the preview first if it hasn't been processed yet.
  This is similar to Rails' `ActiveStorage::Preview#url`.

  ## Options

    * `:expires_in` - Number of seconds until the URL expires (default from config)
    * `:disposition` - Content disposition, either `:inline` or `:attachment` (default: `:inline`)
    * `:filename` - Override the filename in the URL
    * `:endpoint` - Phoenix endpoint to use (default from config)

  ## Examples

      preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
      url = StorageEx.Preview.url(preview)

      # With options
      url = StorageEx.Preview.url(preview, disposition: :inline, filename: "thumbnail.jpg")
  """
  def url(%__MODULE__{service_name: service_name} = preview, opts \\ []) do
    with {:ok, _} <- process(preview) do
      preview_key = key(preview)
      # Get content type for the preview image
      content_type = preview_content_type(preview.format)

      # Build filename with proper extension
      filename = build_filename(preview, Keyword.get(opts, :filename))

      # Merge options with preview-specific data
      url_opts =
        opts
        |> Keyword.put_new(:content_type, content_type)
        |> Keyword.put_new(:filename, filename)
        |> Keyword.put_new(:service_name, service_name)

      StorageEx.url(preview_key, url_opts)
    end
  end

  defp build_filename(%__MODULE__{blob_key: blob_key, format: format}, nil) do
    # Extract base name from blob key and add preview extension
    base_name = blob_key |> Path.basename() |> Path.rootname()
    extension = format_to_extension(format)
    "#{base_name}.#{extension}"
  end

  defp build_filename(_preview, filename) when is_binary(filename), do: filename

  @doc """
  Deletes the preview from storage.

  Note: This does not delete the original blob, only the preview.
  """
  def delete(%__MODULE__{service_name: service_name} = preview) do
    preview_key = key(preview)
    StorageEx.delete(preview_key, service_name: service_name)
  end

  # Private implementation

  defp do_process(
         %__MODULE__{
           blob_key: blob_key,
           content_type: content_type,
           format: format,
           preview_options: preview_options,
           service_name: service_name
         } = preview
       ) do
    opts = [service_name: service_name]

    with {:ok, previewer} <- find_previewer(content_type),
         {:ok, input_data} <- StorageEx.download(blob_key, opts),
         {:ok, output_data} <- extract_preview(previewer, input_data, format, preview_options),
         preview_key = key(preview),
         content_type = preview_content_type(format),
         {:ok, _} <-
           StorageEx.upload(
             preview_key,
             output_data,
             opts ++ [content_type: content_type]
           ) do
      {:ok, preview}
    else
      {:error, :no_previewer} = error ->
        error

      {:error, _reason} = error ->
        error
    end
  end

  defp find_previewer(content_type) do
    Previewer.find_previewer(content_type)
  end

  defp extract_preview(previewer, input_data, format, preview_options) do
    case write_temp_file(input_data, "preview_input") do
      {:ok, input_path} ->
        output_path = temp_output_path(format)

        try do
          with {:ok, _metadata} <- previewer.preview(input_path, output_path, preview_options),
               {:ok, output_data} <- File.read(output_path) do
            {:ok, output_data}
          else
            {:error, reason} = error ->
              Logger.error("Preview extraction failed: #{inspect(reason)}")
              error
          end
        after
          # Always cleanup temp files
          File.rm(input_path)
          File.rm(output_path)
        end

      error ->
        error
    end
  end

  defp write_temp_file(data, prefix) do
    random_suffix = :crypto.strong_rand_bytes(16) |> Base.encode16()
    path = Path.join(System.tmp_dir!(), "storage_ex_#{prefix}_#{random_suffix}")

    case File.write(path, data) do
      :ok -> {:ok, path}
      error -> error
    end
  end

  defp temp_output_path(format) do
    random_suffix = :crypto.strong_rand_bytes(16) |> Base.encode16()
    extension = format_to_extension(format)

    Path.join(
      System.tmp_dir!(),
      "storage_ex_preview_output_#{random_suffix}.#{extension}"
    )
  end

  defp generate_preview_key(preview) do
    # Hash content_type, format, and preview options to create unique key
    # This ensures different preview configurations are cached separately
    data =
      :erlang.term_to_binary({
        preview.content_type,
        preview.format,
        preview.preview_options
      })

    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp preview_content_type(:png), do: "image/png"
  defp preview_content_type(:jpg), do: "image/jpeg"
  defp preview_content_type(:jpeg), do: "image/jpeg"
  defp preview_content_type(_), do: "image/png"

  defp format_to_extension(:png), do: "png"
  defp format_to_extension(:jpg), do: "jpg"
  defp format_to_extension(:jpeg), do: "jpg"
  defp format_to_extension(format) when is_atom(format), do: Atom.to_string(format)
  defp format_to_extension(format) when is_binary(format), do: format
end
