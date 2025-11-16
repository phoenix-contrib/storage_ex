defmodule StorageEx.Transformer do
  @moduledoc """
  Behaviour for image transformation implementations.

  A Transformer applies a set of transformations to an image, producing
  a new image in the specified format.

  This module is inspired by Rails' ActiveStorage transformers but adapted
  for Elixir idioms, using the `image` package (similar to how Rails uses
  the `image_processing` gem).

  ## Built-in Transformers

  - `StorageEx.Transformers.Vips` - Uses the `image` package (libvips-based, fast, low memory)
  - `StorageEx.Transformers.Null` - No-op transformer (disabled variants)

  ## Custom Transformers

  Implement this behavior to add support for other processors:

      defmodule MyApp.ImageMagickTransformer do
        @behaviour StorageEx.Transformer

        @impl true
        def available?() do
          System.find_executable("convert") != nil
        end

        @impl true
        def transform(input_path, output_path, transformations, format) do
          # Use ImageMagick via Mogrify or similar
        end
      end
  """

  @type transformations :: keyword() | map()
  @type format :: atom() | String.t()
  @type path :: String.t()

  @doc """
  Check if the transformer's dependencies are available.

  Returns true if the required system libraries/executables are present.
  """
  @callback available?() :: boolean()

  @doc """
  Transform an image file applying the given transformations.

  ## Parameters

  - `input_path` - Path to source image file
  - `output_path` - Path where transformed image should be written
  - `transformations` - Keyword list or map of transformation operations
  - `format` - Target format (e.g., :png, :jpg, :webp)

  ## Returns

  - `{:ok, output_path}` on success
  - `{:error, reason}` on failure
  """
  @callback transform(
              input_path :: path(),
              output_path :: path(),
              transformations :: transformations(),
              format :: format()
            ) :: {:ok, path()} | {:error, term()}
end
