defmodule StorageEx.Variant do
  @moduledoc """
  Represents a transformed version of a blob.

  Variants are lazily processed and cached in the storage service,
  similar to Rails' ActiveStorage::Variant.

  ## JSON Serialization

  Variants can be serialized to JSON for use in JSON APIs or Inertia.js props:

      # Using Jason encoder (automatic)
      variant = StorageEx.variant("photo.jpg", resize_to_limit: [100, 100])
      Jason.encode!(variant)
      # => {"url": "/path/to/variant", "key": "...", ...}

      # Using to_map/2 for custom serialization
      Variant.to_map(variant, url_opts: [disposition: :inline])

  ## Examples

      # Create a variant specification
      variant = StorageEx.Variant.new("my-image-key",
        resize_to_limit: [100, 100],
        format: :webp
      )

      # Process the variant (generates if needed, returns cached if exists)
      {:ok, variant} = StorageEx.Variant.process(variant)

      # Get the storage key for the variant
      key = StorageEx.Variant.key(variant)

      # Download the variant data
      {:ok, data} = StorageEx.Variant.download(variant)
  """

  alias StorageEx.Variation

  require Logger

  @derive {Jason.Encoder, only: []}
  defstruct [:blob_key, :variation, :service_name]

  @type t :: %__MODULE__{
          blob_key: String.t(),
          variation: Variation.t(),
          service_name: atom() | nil
        }

  @doc """
  Creates a new Variant specification.

  ## Parameters

    * `blob_key` - The key of the original blob in storage
    * `transformations` - Keyword list of transformations to apply
    * `service_name` - Service name (atom) or nil for default service.

  Note: Following Rails' design, variants are stored in the same service as the original blob.

  ## Examples

      # Use default service
      variant = StorageEx.Variant.new("my-image-key", resize_to_limit: [100, 100])

      # Use specific service by name
      variant = StorageEx.Variant.new("my-image-key", [resize_to_limit: [100, 100]], :s3)
  """
  def new(blob_key, transformations, service_name \\ nil) when is_binary(blob_key) do
    variation = Variation.new(transformations)
    %__MODULE__{blob_key: blob_key, variation: variation, service_name: service_name}
  end

  @doc """
  Returns the storage key for this variant.

  Variants are stored at: `variants/{blob_key}/{variation_hash}`
  """
  def key(%__MODULE__{blob_key: blob_key, variation: variation}) do
    variation_key = Variation.key(variation)
    "variants/#{blob_key}/#{variation_key}"
  end

  @doc """
  Checks if the variant has been processed and exists in storage.
  """
  def processed?(%__MODULE__{service_name: service_name} = variant) do
    variant_key = key(variant)
    StorageEx.exists?(variant_key, service_name: service_name)
  end

  @doc """
  Processes the variant if not already processed.

  This downloads the original blob, applies transformations using the
  configured transformer, and uploads the result to storage.

  Returns `{:ok, variant}` if successful or already processed.
  Returns `{:error, reason}` if processing fails.

  ## Examples

      variant = StorageEx.Variant.new("photo.jpg", resize_to_limit: [100, 100])
      {:ok, variant} = StorageEx.Variant.process(variant)
  """
  def process(%__MODULE__{} = variant) do
    if processed?(variant) do
      {:ok, variant}
    else
      do_process(variant)
    end
  end

  @doc """
  Downloads the variant data.

  Processes the variant first if it hasn't been processed yet.

  Returns `{:ok, binary_data}` on success.
  """
  def download(%__MODULE__{service_name: service_name} = variant) do
    with {:ok, _} <- process(variant),
         variant_key = key(variant) do
      StorageEx.download(variant_key, service_name: service_name)
    end
  end

  @doc """
  Returns a URL for the variant.

  Processes the variant first if it hasn't been processed yet.
  This is similar to Rails' `ActiveStorage::Variant#url`.

  ## Options

    * `:expires_in` - Number of seconds until the URL expires (default from config)
    * `:disposition` - Content disposition, either `:inline` or `:attachment` (default: `:inline`)
    * `:filename` - Override the filename in the URL
    * `:endpoint` - Phoenix endpoint to use (default from config)

  ## Examples

      variant = StorageEx.variant("photo.jpg", resize_to_limit: [100, 100])
      url = StorageEx.Variant.url(variant)

      # With options
      url = StorageEx.Variant.url(variant, disposition: :attachment, filename: "thumbnail.jpg")
  """
  def url(%__MODULE__{service_name: service_name} = variant, opts \\ []) do
    with {:ok, _} <- process(variant),
         variant_key = key(variant) do
      # Get content type from the variation
      content_type = Variation.content_type(variant.variation)

      # Build filename with proper extension
      filename = build_filename(variant, Keyword.get(opts, :filename))

      # Merge options with variant-specific data
      url_opts =
        opts
        |> Keyword.put_new(:content_type, content_type)
        |> Keyword.put_new(:filename, filename)
        |> Keyword.put_new(:service_name, service_name)

      StorageEx.url(variant_key, url_opts)
    end
  end

  defp build_filename(%__MODULE__{blob_key: blob_key, variation: variation}, nil) do
    # Extract base name from blob key and add variant extension
    base_name = blob_key |> Path.basename() |> Path.rootname()
    extension = Variation.extension(variation)
    "#{base_name}.#{extension}"
  end

  defp build_filename(_variant, filename) when is_binary(filename), do: filename

  @doc """
  Deletes the variant from storage.

  Note: This does not delete the original blob, only the variant.
  """
  def delete(%__MODULE__{service_name: service_name} = variant) do
    variant_key = key(variant)
    StorageEx.delete(variant_key, service_name: service_name)
  end

  # Private implementation

  defp do_process(
         %__MODULE__{blob_key: blob_key, variation: variation, service_name: service_name} =
           variant
       ) do
    transformer = StorageEx.Config.variant_transformer()
    opts = [service_name: service_name]

    with {:ok, true} <- check_transformer(transformer),
         {:ok, input_data} <- StorageEx.download(blob_key, opts),
         {:ok, output_data} <- transform_data(transformer, input_data, variation),
         variant_key = key(variant),
         {:ok, _} <-
           StorageEx.upload(
             variant_key,
             output_data,
             opts ++ [content_type: Variation.content_type(variation)]
           ) do
      {:ok, variant}
    else
      {:error, :transformer_unavailable} = error ->
        Logger.warning("Transformer unavailable, cannot process variant for #{blob_key}")
        error

      {:error, reason} = error ->
        Logger.error("Failed to process variant for #{blob_key}: #{inspect(reason)}")
        error
    end
  end

  defp transform_data(transformer, input_data, variation) do
    input_path = nil
    output_path = nil

    try do
      with {:ok, path} <- write_temp_file(input_data, "input"),
           input_path = path,
           output_path = temp_output_path(variation.format),
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
    extension = Variation.extension(%Variation{format: format, transformations: []})

    Path.join(
      System.tmp_dir!(),
      "storage_ex_output_#{random_suffix}.#{extension}"
    )
  end

  defp check_transformer(transformer) do
    if transformer.available?() do
      {:ok, true}
    else
      {:error, :transformer_unavailable}
    end
  end
end
