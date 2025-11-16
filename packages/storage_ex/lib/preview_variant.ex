defmodule StorageEx.PreviewVariant do
  @moduledoc """
  Represents a variant of a preview image (preview + variant combined).

  This module combines preview generation and variant transformation into a single
  operation, matching Rails' ActiveStorage behavior more closely.

  ## Examples

      # Create a preview variant specification
      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )

      # Process (generates preview, then applies variant)
      {:ok, pv} = StorageEx.PreviewVariant.process(pv)

      # Get URL
      url = StorageEx.PreviewVariant.url(pv)

      # Download data
      {:ok, data} = StorageEx.PreviewVariant.download(pv)

  ## Options

  All preview options are supported, plus a `:variant` option:

      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05",              # Preview option
        format: :png,                   # Preview option
        variant: [                      # Variant options
          resize_to_limit: [100, 100],
          quality: 85
        ]
      )

  ## Storage

  Preview variants are stored at: `variants/{preview_key}/{variant_hash}`

  This allows the same preview to have multiple variant sizes cached independently.
  """

  alias StorageEx.{Preview, Variant, Variation}

  require Logger

  @derive {Jason.Encoder, only: []}
  defstruct [:preview, :variant, :service_name]

  @type t :: %__MODULE__{
          preview: Preview.t(),
          variant: Variant.t() | nil,
          service_name: atom() | nil
        }

  @doc """
  Creates a new PreviewVariant specification.

  ## Parameters

    * `blob_key` - The key of the original blob in storage
    * `opts` - Options:
      * `:content_type` - MIME type of the blob (required)
      * `:variant` - Variant transformations to apply (optional)
      * `:format` - Preview output format (`:png` or `:jpg`, default: `:png`)
      * `:service_name` - Service name (atom) or nil for default service
      * Additional preview-specific options (e.g., `:time` for videos)

  If no `:variant` is specified, this is equivalent to a plain preview.

  ## Examples

      # Preview with variant
      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )

      # Preview only (no variant)
      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4"
      )

      # With preview options
      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4",
        time: "00:00:05",
        variant: [resize_to_fill: [200, 200], format: :webp]
      )
  """
  def new(blob_key, opts) when is_binary(blob_key) and is_list(opts) do
    service_name = Keyword.get(opts, :service_name)
    variant_opts = Keyword.get(opts, :variant)

    # Create preview with all options except :variant
    preview_opts = Keyword.delete(opts, :variant)
    preview = Preview.new(blob_key, preview_opts)

    # Create variant if transformations specified
    variant =
      if variant_opts do
        # We'll create variant from preview key after preview is processed
        # For now, store the transformations
        Variation.new(variant_opts)
      else
        nil
      end

    %__MODULE__{
      preview: preview,
      variant: variant,
      service_name: service_name
    }
  end

  @doc """
  Returns the storage key for this preview variant.

  If no variant is specified, returns the preview key.
  Otherwise, returns the variant key.
  """
  def key(%__MODULE__{preview: preview, variant: nil}) do
    Preview.key(preview)
  end

  def key(%__MODULE__{preview: preview, variant: variation}) do
    # Generate variant key from preview key
    preview_key = Preview.key(preview)
    variation_key = Variation.key(variation)
    "variants/#{preview_key}/#{variation_key}"
  end

  @doc """
  Checks if the preview variant has been processed and exists in storage.
  """
  def processed?(%__MODULE__{service_name: service_name} = pv) do
    key = key(pv)
    StorageEx.exists?(key, service_name: service_name)
  end

  @doc """
  Processes the preview variant if not already processed.

  This:
  1. Generates the preview if not cached
  2. Applies variant transformations if specified
  3. Uploads the result to storage

  Returns `{:ok, preview_variant}` if successful or already processed.
  Returns `{:error, reason}` if processing fails.

  ## Examples

      pv = StorageEx.PreviewVariant.new("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )
      {:ok, pv} = StorageEx.PreviewVariant.process(pv)
  """
  def process(%__MODULE__{} = pv) do
    if processed?(pv) do
      {:ok, pv}
    else
      do_process(pv)
    end
  end

  @doc """
  Downloads the preview variant data.

  Processes the preview variant first if it hasn't been processed yet.

  Returns `{:ok, binary_data}` on success.
  """
  def download(%__MODULE__{service_name: service_name} = pv) do
    with {:ok, _} <- process(pv),
         key = key(pv) do
      StorageEx.download(key, service_name: service_name)
    end
  end

  @doc """
  Returns a URL for the preview variant.

  Processes first if not already processed.

  ## Options

    * `:expires_in` - Number of seconds until the URL expires
    * `:disposition` - Content disposition (`:inline` or `:attachment`)
    * `:filename` - Override the filename in the URL
    * `:endpoint` - Phoenix endpoint to use

  ## Examples

      pv = StorageEx.preview_variant("video.mp4",
        content_type: "video/mp4",
        variant: [resize_to_limit: [100, 100]]
      )
      url = StorageEx.PreviewVariant.url(pv)

      # With options
      url = StorageEx.PreviewVariant.url(pv,
        disposition: :inline,
        filename: "thumbnail.jpg"
      )
  """
  def url(%__MODULE__{service_name: service_name, variant: variation} = pv, opts \\ []) do
    with {:ok, _} <- process(pv),
         key = key(pv) do
      # Get content type
      content_type =
        if variation do
          Variation.content_type(variation)
        else
          preview_content_type(pv.preview.format)
        end

      # Build filename
      filename = build_filename(pv, Keyword.get(opts, :filename))

      # Merge options
      url_opts =
        opts
        |> Keyword.put_new(:content_type, content_type)
        |> Keyword.put_new(:filename, filename)
        |> Keyword.put_new(:service_name, service_name)

      StorageEx.url(key, url_opts)
    end
  end

  defp build_filename(%__MODULE__{preview: preview, variant: nil}, nil) do
    # Just preview, use preview filename
    blob_key = preview.blob_key
    base_name = blob_key |> Path.basename() |> Path.rootname()
    extension = format_to_extension(preview.format)
    "#{base_name}.#{extension}"
  end

  defp build_filename(%__MODULE__{preview: preview, variant: variation}, nil) do
    # Preview + variant, use variant extension
    blob_key = preview.blob_key
    base_name = blob_key |> Path.basename() |> Path.rootname()
    extension = Variation.extension(variation)
    "#{base_name}.#{extension}"
  end

  defp build_filename(_pv, filename) when is_binary(filename), do: filename

  @doc """
  Deletes the preview variant from storage.

  Note: This only deletes the variant, not the preview or original blob.
  """
  def delete(%__MODULE__{service_name: service_name} = pv) do
    key = key(pv)
    StorageEx.delete(key, service_name: service_name)
  end

  # Private implementation

  defp do_process(%__MODULE__{preview: preview, variant: nil, service_name: _service_name} = pv) do
    # No variant, just process preview
    case Preview.process(preview) do
      {:ok, _preview} -> {:ok, pv}
      error -> error
    end
  end

  defp do_process(
         %__MODULE__{
           preview: preview,
           variant: variation,
           service_name: service_name
         } = pv
       ) do
    opts = [service_name: service_name]

    with {:ok, _preview} <- Preview.process(preview),
         preview_key = Preview.key(preview),
         {:ok, preview_data} <- StorageEx.download(preview_key, opts),
         {:ok, variant_data} <- transform_preview_data(preview_data, variation),
         pv_key = key(pv),
         content_type = Variation.content_type(variation),
         {:ok, _} <-
           StorageEx.upload(
             pv_key,
             variant_data,
             opts ++ [content_type: content_type]
           ) do
      {:ok, pv}
    else
      {:error, reason} = error ->
        Logger.error(
          "Failed to process preview variant for #{preview.blob_key}: #{inspect(reason)}"
        )

        error
    end
  end

  defp transform_preview_data(input_data, variation) do
    transformer = StorageEx.Config.variant_transformer()
    input_path = nil
    output_path = nil

    try do
      with {:ok, path} <- write_temp_file(input_data, "pv_input"),
           input_path = path,
           output_path = temp_output_path(variation.format),
           {:ok, true} <- check_transformer(transformer),
           {:ok, _} <-
             transformer.transform(
               input_path,
               output_path,
               variation.transformations,
               variation.format
             ),
           {:ok, output_data} <- File.read(output_path) do
        {:ok, output_data}
      else
        {:error, reason} = error ->
          Logger.error("Transform failed: #{inspect(reason)}")
          error
      end
    after
      # Always cleanup temp files
      if input_path, do: File.rm(input_path)
      if output_path, do: File.rm(output_path)
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
      "storage_ex_pv_output_#{random_suffix}.#{extension}"
    )
  end

  defp check_transformer(transformer) do
    if transformer.available?() do
      {:ok, true}
    else
      {:error, :transformer_unavailable}
    end
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
