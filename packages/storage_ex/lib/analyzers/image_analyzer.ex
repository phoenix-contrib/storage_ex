defmodule StorageEx.Analyzers.ImageAnalyzer do
  @moduledoc """
  Analyzer for extracting metadata from image files.

  This analyzer extracts width and height from image files using the Image package
  (libvips wrapper). It handles EXIF orientation data to swap dimensions for
  rotated images, providing the same behavior as Rails ActiveStorage.

  ## Supported Formats

  Supports all image formats supported by libvips, including:
  - JPEG, PNG, WEBP, TIFF, GIF
  - RAW formats (when libvips is compiled with appropriate support)
  - SVG (when libvips has SVG support)

  ## Metadata Format

  Returns metadata compatible with Rails ActiveStorage ImageAnalyzer:

      %{width: 1024, height: 768}

  ## EXIF Handling

  When an image has EXIF orientation data indicating 90° or 270° rotation,
  the width and height are automatically swapped for convenience, matching
  Rails ActiveStorage behavior.

  ## Dependencies & Rails-Style Graceful Degradation

  ### Image Package & libvips Installation (Optional but Recommended)

      # Add to mix.exs
      {:image, "~> 0.54"}

      # Install libvips system library:

      # macOS
      brew install vips

      # Ubuntu/Debian
      sudo apt update && sudo apt install libvips-dev

      # Alpine Linux (Docker)
      apk add --no-cache vips-dev

  ### Dependency Strategy (Following Rails ActiveStorage)

  StorageEx follows Rails' proven approach to image dependencies:

  1. **✅ Always Include**: ImageAnalyzer is included by default in configuration
  2. **🕰️ Runtime Check**: Image/libvips availability checked during analysis
  3. **🛡️ Graceful Degradation**: Returns empty metadata `%{}` when unavailable
  4. **📝 Clear Logging**: ERROR level logs for missing gems (more serious than binaries)

  ### User Experience Without Image/libvips

      # Analysis still works, returns empty metadata
      {:ok, %{}} = StorageEx.analyze(key, "image/jpeg", :local)

      # Log output (ERROR level - gem dependency more serious):
      [error] Skipping image analysis because the image gem isn't installed

  ### Enhanced Experience With Image/libvips

      # Returns rich metadata when Image package available
      {:ok, %{width: 1024, height: 768}} = StorageEx.analyze(key, "image/jpeg", :local)

  This ensures applications **never break** due to missing dependencies while providing
  clear guidance for optional enhancements.
  """

  @behaviour StorageEx.Analyzer
  @compile {:no_warn_undefined, Image}

  alias StorageEx.Notifications

  @doc """
  Accepts all image content types.

  Corresponds to Rails `blob.image?` check.
  """
  @impl true
  def accept?("image/" <> _), do: true
  def accept?(_), do: false

  @doc """
  Returns true for background processing.

  Image analysis can be CPU-intensive, especially for large images.
  """
  @impl true
  def analyze_later?, do: true

  @doc """
  Checks if the Image package is available.

  Returns false if the Image package is not installed or libvips
  is not available on the system.
  """
  @impl true
  def available? do
    Code.ensure_loaded?(Image) and check_libvips_available()
  end

  if Code.ensure_loaded?(Image) do
    defp check_libvips_available do
      # This will fail gracefully if libvips is not installed
      Image.new!(1, 1) |> Image.width()
      true
    rescue
      _ -> false
    catch
      _ -> false
    end
  else
    defp check_libvips_available, do: false
  end

  @doc """
  Extracts width and height metadata from image files.

  Handles EXIF orientation to automatically swap dimensions for
  rotated images (90° and 270° rotations).

  ## Returns

  - `{:ok, %{width: integer, height: integer}}` - Success
  - `{:error, reason}` - Analysis failed

  ## Examples

      metadata("/path/to/image.jpg", "image/jpeg")
      #=> {:ok, %{width: 1024, height: 768}}

      # Rotated image (EXIF orientation 6 or 8)
      metadata("/path/to/rotated.jpg", "image/jpeg")
      #=> {:ok, %{width: 768, height: 1024}}  # Dimensions swapped
  """
  @impl true
  def metadata(file_path, _content_type) do
    if available?() do
      analyze_image_file(file_path)
    else
      # Rails-style: ERROR level log for missing gem (more serious than missing binary)
      Notifications.execute(
        [:analyzer, :dependency_missing],
        %{count: 1},
        %{
          analyzer: __MODULE__,
          dependency: "image (Vix)",
          install_commands: %{
            mix: "mix deps.get",
            system: "Install libvips system dependency first"
          }
        }
      )

      {:ok, %{}}
    end
  rescue
    # Handle any unexpected errors gracefully
    error ->
      {:error, {:image_analysis_failed, error}}
  end

  if Code.ensure_loaded?(Image) do
    defp analyze_image_file(file_path) do
      case Image.open(file_path) do
        {:ok, image} ->
          width = Image.width(image)
          height = Image.height(image)

          # Check EXIF orientation and swap dimensions if rotated
          if rotated_image?(image) do
            {:ok, %{width: height, height: width}}
          else
            {:ok, %{width: width, height: height}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    # Private helper to check if image is rotated based on EXIF orientation
    # Corresponds to Rails ImageAnalyzer rotation logic
    defp rotated_image?(image) do
      case Image.exif(image) do
        {:ok, exif} ->
          orientation = get_orientation(exif)
          # Right-top (90°) or Left-bottom (270°)
          orientation in [6, 8]

        {:error, _} ->
          # No EXIF data or error reading it
          false
      end
    rescue
      # Any error reading EXIF, assume not rotated
      _ -> false
    end

    # Extract orientation value from EXIF data
    # The Image package uses :orientation key with string values like "Rotate 90 CW"
    defp get_orientation(exif) when is_map(exif) do
      case Map.get(exif, :orientation) do
        "Rotate 90 CW" ->
          6

        "Rotate 270 CW" ->
          8

        "Rotate 180" ->
          3

        # Try integer/string keys as fallback for other EXIF formats
        nil ->
          exif
          |> Map.get("Orientation", 1)
          |> case do
            orientation when is_integer(orientation) -> orientation
            orientation when is_binary(orientation) -> String.to_integer(orientation)
            _ -> 1
          end

        # Default to no rotation for any other values
        _ ->
          1
      end
    rescue
      # Default to no rotation on any parsing error
      _ -> 1
    end
  else
    defp analyze_image_file(_file_path) do
      {:error, "Image library not available"}
    end
  end
end
