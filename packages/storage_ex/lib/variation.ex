defmodule StorageEx.Variation do
  @moduledoc """
  A set of transformations that can be applied to create a variant.

  This module encapsulates the transformation specification, similar to
  Rails' ActiveStorage::Variation.

  ## Examples

      variation = StorageEx.Variation.new(
        resize_to_limit: [100, 100],
        quality: 80,
        format: :webp
      )

      # Generate a unique key for this variation
      key = StorageEx.Variation.key(variation)

      # Get the content type
      content_type = StorageEx.Variation.content_type(variation)
      # => "image/webp"
  """

  defstruct [:transformations, :format]

  @type t :: %__MODULE__{
          transformations: keyword(),
          format: atom()
        }

  @doc """
  Creates a new Variation from a keyword list or map of transformations.

  The `:format` key determines the output format (default: :png).
  All other keys are transformation operations.

  ## Examples

      StorageEx.Variation.new(resize_to_limit: [100, 100])

      StorageEx.Variation.new(
        resize_to_fill: [200, 200],
        quality: 85,
        format: :jpg
      )
  """
  def new(transformations) when is_list(transformations) or is_map(transformations) do
    {format, transforms} = extract_format(transformations)

    %__MODULE__{
      transformations: normalize_transformations(transforms),
      format: format
    }
  end

  @doc """
  Generates a stable hash key for this variation.

  The key is a SHA256 hash of the transformations, used to identify
  cached variants in storage.
  """
  def key(%__MODULE__{transformations: transformations, format: format}) do
    data = :erlang.term_to_binary({transformations, format})
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  @doc """
  Returns the MIME content type for the variation's format.

  ## Examples

      variation = StorageEx.Variation.new(format: :png)
      StorageEx.Variation.content_type(variation)
      # => "image/png"
  """
  def content_type(%__MODULE__{format: format}) do
    case format do
      :png -> "image/png"
      :jpg -> "image/jpeg"
      :jpeg -> "image/jpeg"
      :webp -> "image/webp"
      :gif -> "image/gif"
      :tiff -> "image/tiff"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Returns the file extension for the variation's format.

  ## Examples

      variation = StorageEx.Variation.new(format: :jpg)
      StorageEx.Variation.extension(variation)
      # => "jpg"
  """
  def extension(%__MODULE__{format: format}) do
    case format do
      :jpg -> "jpg"
      :jpeg -> "jpg"
      :png -> "png"
      :webp -> "webp"
      :gif -> "gif"
      :tiff -> "tiff"
      format when is_atom(format) -> Atom.to_string(format)
      format when is_binary(format) -> format
    end
  end

  # Private helpers

  defp extract_format(transformations) when is_map(transformations) do
    {format, rest} = Map.pop(transformations, :format, :png)
    {format, Map.to_list(rest)}
  end

  defp extract_format(transformations) when is_list(transformations) do
    {format, rest} = Keyword.pop(transformations, :format, :png)
    {format, rest}
  end

  defp normalize_transformations(transformations) when is_map(transformations) do
    Enum.into(transformations, [])
  end

  defp normalize_transformations(transformations), do: transformations
end
