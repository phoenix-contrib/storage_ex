defmodule StorageEx.Transformers.Vips do
  @moduledoc """
  Image transformer using libvips via the Image library.

  The Image library provides a high-level abstraction over Vix and libvips,
  similar to Ruby's image_processing gem.

  ## Requirements

  - libvips 8.6+ installed on the system
  - image Elixir package (which depends on vix)

  ## Installation

  Add to mix.exs:

      {:image, "~> 0.37"}

  Install libvips:

      # macOS
      brew install vips

      # Ubuntu/Debian
      apt-get install libvips-dev

      # Alpine Linux
      apk add vips-dev

  The `image` package will use pre-compiled binaries by default, which is
  great for development. For production with full format support, install
  libvips and set `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`.

  ## Performance

  libvips is typically 4-10x faster than ImageMagick and uses
  1/10th the memory for similar operations.

  ## Supported Transformations

  - `resize_to_limit` - Resize to fit within dimensions
  - `resize_to_fit` - Resize to exact dimensions
  - `resize_to_fill` - Resize and crop to exact dimensions
  - `crop` - Crop image to specified region
  - `rotate` - Rotate image by degrees
  - `quality` - Set output quality (for lossy formats)
  """

  @behaviour StorageEx.Transformer

  # Suppress warnings for optional Image dependency that's loaded at runtime
  @compile {:no_warn_undefined, Image}

  @impl true
  def available? do
    Code.ensure_loaded?(Image)
  end

  @impl true
  def transform(input_path, output_path, transformations, format) do
    with {:ok, image} <- Image.open(input_path),
         {:ok, transformed} <- apply_transformations(image, transformations),
         {:ok, _} <- write_image(transformed, output_path, format, transformations) do
      {:ok, output_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions for transformation operations

  defp apply_transformations(image, transformations) do
    Enum.reduce_while(transformations, {:ok, image}, fn {op, args}, {:ok, img} ->
      case apply_operation(img, op, args) do
        {:ok, new_img} -> {:cont, {:ok, new_img}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Resize operations using Image.thumbnail with :fit option
  # These match Rails ActiveStorage resize operations

  defp apply_operation(image, :resize_to_limit, [width, height]) do
    # Resize to fit within dimensions (shrink only)
    Image.thumbnail(image, "#{width}x#{height}", resize: :down, fit: :contain)
  end

  defp apply_operation(image, :resize_to_fit, [width, height]) do
    # Resize to fit within dimensions (can enlarge)
    Image.thumbnail(image, "#{width}x#{height}", resize: :both, fit: :contain)
  end

  defp apply_operation(image, :resize_to_fill, [width, height, opts]) when is_list(opts) do
    # Resize and crop to fill exact dimensions
    crop = Keyword.get(opts, :crop, :center)
    Image.thumbnail(image, "#{width}x#{height}", resize: :both, fit: :cover, crop: crop)
  end

  defp apply_operation(image, :resize_to_fill, [width, height]) do
    apply_operation(image, :resize_to_fill, [width, height, []])
  end

  defp apply_operation(image, :crop, [x, y, width, height]) do
    Image.crop(image, x, y, width, height)
  end

  defp apply_operation(image, :rotate, degrees) when is_number(degrees) do
    Image.rotate(image, degrees)
  end

  # Quality is handled during save, not as a transformation
  defp apply_operation(image, :quality, quality) when is_integer(quality) do
    {:ok, image}
  end

  defp apply_operation(_image, operation, _args) do
    {:error, {:unsupported_operation, operation}}
  end

  defp write_image(image, output_path, format, transformations) do
    quality = Keyword.get(transformations, :quality)
    extension = format_to_extension(format)
    final_path = ensure_extension(output_path, extension)

    write_opts =
      if quality do
        [quality: quality]
      else
        []
      end

    Image.write(image, final_path, write_opts)
  end

  @format_extensions %{
    jpg: ".jpg",
    jpeg: ".jpg",
    png: ".png",
    webp: ".webp",
    gif: ".gif",
    tiff: ".tiff",
    tif: ".tiff"
  }

  defp format_to_extension(format) when is_atom(format) do
    Map.get(@format_extensions, format, ".png")
  end

  defp format_to_extension(format) when is_binary(format) do
    ".#{format}"
  end

  defp format_to_extension(_format) do
    ".png"
  end

  defp ensure_extension(path, extension) do
    if String.ends_with?(path, extension) do
      path
    else
      path <> extension
    end
  end
end
