defmodule StorageEx.Analyzers.VideoAnalyzer do
  @moduledoc """
  Analyzer for extracting metadata from video files using FFprobe.

  This analyzer extracts comprehensive video metadata including dimensions, duration,
  rotation angle, aspect ratio, and audio/video stream presence. It uses FFprobe from
  the FFmpeg suite, providing the same functionality as Rails ActiveStorage VideoAnalyzer.

  ## Supported Formats

  Supports all video formats supported by FFmpeg, including:
  - MP4, WebM, AVI, MOV, MKV
  - Various codecs (H.264, H.265, VP8, VP9, etc.)

  ## Metadata Format

  Returns metadata compatible with Rails ActiveStorage VideoAnalyzer:

      %{
        width: 640.0, height: 480.0, duration: 5.0, angle: 0,
        display_aspect_ratio: [4, 3], audio: true, video: true
      }

  ## Rotation Handling

  When a video's angle is 90°, -90°, 270°, or -270°, the width and height are
  automatically swapped for convenience, matching Rails ActiveStorage behavior.

  ## Dependencies & Rails-Style Graceful Degradation

  ### FFmpeg Installation (Optional but Recommended)

      # macOS
      brew install ffmpeg

      # Ubuntu/Debian
      sudo apt update && sudo apt install ffmpeg

      # Alpine Linux (Docker)
      apk add --no-cache ffmpeg

      # Verify installation
      ffprobe -version

  ### Dependency Strategy (Following Rails ActiveStorage)

  StorageEx follows Rails' proven approach to external dependencies:

  1. **✅ Always Include**: VideoAnalyzer is included by default in configuration
  2. **🕰️ Runtime Check**: FFprobe availability checked during analysis, not accept time
  3. **🛡️ Graceful Degradation**: Returns empty metadata `%{}` when FFprobe unavailable
  4. **📝 Clear Logging**: INFO level logs guide users to optional enhancements

  ### User Experience Without FFmpeg

      # Analysis still works, returns empty metadata
      {:ok, %{}} = StorageEx.analyze(key, "video/mp4", :local)

      # Log output (INFO level - not an error):
      [info] Skipping video analysis because ffprobe isn't installed

  ### Enhanced Experience With FFmpeg

      # Returns rich metadata when FFprobe available
      {:ok, %{
        width: 640.0, height: 480.0, duration: 5.166648,
        display_aspect_ratio: [4, 3], audio: true, video: true
      }} = StorageEx.analyze(key, "video/mp4", :local)

  This ensures applications **never break** due to missing dependencies while providing
  clear guidance for optional enhancements.
  """

  @behaviour StorageEx.Analyzer

  alias StorageEx.Notifications

  @doc """
  Accepts all video content types.

  Corresponds to Rails `blob.video?` check.
  """
  @impl true
  def accept?("video/" <> _), do: true
  def accept?(_), do: false

  @doc """
  Returns true for background processing.

  Video analysis can be CPU and I/O intensive, especially for large files.
  """
  @impl true
  def analyze_later?, do: true

  @doc """
  Checks if FFprobe is available on the system.

  Returns false if FFmpeg/FFprobe is not installed.
  Always returns true for accept?/1 - availability is checked at runtime.
  """
  @impl true
  def available? do
    case System.find_executable("ffprobe") do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Extracts video metadata using FFprobe.

  Returns comprehensive video information including dimensions, duration,
  rotation, aspect ratio, and stream information.

  ## Returns

  - `{:ok, metadata}` - Analysis successful
  - `{:error, reason}` - Analysis failed

  ## Examples

      metadata("/path/to/video.mp4", "video/mp4")
      #=> {:ok, %{width: 640.0, height: 480.0, duration: 5.0, angle: 0,
      #           display_aspect_ratio: [4, 3], audio: true, video: true}}

      # Rotated video (angle 90° or 270°)
      metadata("/path/to/rotated.mov", "video/quicktime")
      #=> {:ok, %{width: 480.0, height: 640.0, ...}}  # Dimensions swapped
  """
  @impl true
  def metadata(file_path, _content_type) do
    case probe_video(file_path) do
      {:ok, probe_data} ->
        {:ok, extract_metadata(probe_data)}

      {:error, :ffprobe_unavailable} ->
        # Rails-style: Log and return empty metadata instead of failing
        Notifications.execute(
          [:analyzer, :dependency_missing],
          %{count: 1},
          %{
            analyzer: __MODULE__,
            dependency: "ffprobe (FFmpeg)",
            install_commands: %{
              macos: "brew install ffmpeg",
              ubuntu: "apt-get install ffmpeg",
              debian: "apt-get install ffmpeg"
            }
          }
        )

        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, {:video_analysis_failed, error}}
  end

  # Private functions for video analysis

  defp probe_video(file_path) do
    # Rails-style: Check availability at runtime, not in accept?
    case System.find_executable("ffprobe") do
      nil ->
        {:error, :ffprobe_unavailable}

      _ffprobe_path ->
        ffprobe_cmd = [
          "ffprobe",
          "-print_format",
          "json",
          "-show_streams",
          "-show_format",
          "-v",
          "error",
          file_path
        ]

        case System.cmd("ffprobe", tl(ffprobe_cmd), stderr_to_stdout: true) do
          {output, 0} ->
            parse_ffprobe_output(output)

          {error_output, _exit_code} ->
            {:error, {:ffprobe_error, error_output}}
        end
    end
  end

  defp extract_metadata(probe_data) do
    video_stream = find_video_stream(probe_data)
    audio_stream = find_audio_stream(probe_data)
    format_data = Map.get(probe_data, "format", %{})

    metadata = %{}

    # Add dimensions (with rotation handling)
    metadata = add_dimensions(metadata, video_stream)

    # Add duration
    metadata = add_duration(metadata, video_stream, format_data)

    # Add rotation angle
    metadata = add_angle(metadata, video_stream)

    # Add display aspect ratio
    metadata = add_aspect_ratio(metadata, video_stream)

    # Add stream presence flags
    metadata = add_stream_flags(metadata, video_stream, audio_stream)

    # Remove nil values (Rails .compact behavior)
    metadata |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
  end

  defp find_video_stream(probe_data) do
    probe_data
    |> Map.get("streams", [])
    |> Enum.find(fn stream -> Map.get(stream, "codec_type") == "video" end)
    |> case do
      nil -> %{}
      stream -> stream
    end
  end

  defp find_audio_stream(probe_data) do
    probe_data
    |> Map.get("streams", [])
    |> Enum.find(fn stream -> Map.get(stream, "codec_type") == "audio" end)
  end

  defp add_dimensions(metadata, video_stream) when map_size(video_stream) == 0, do: metadata

  defp add_dimensions(metadata, video_stream) do
    encoded_width = get_float(video_stream, "width")
    encoded_height = get_float(video_stream, "height")
    angle = get_angle(video_stream)

    if encoded_width && encoded_height do
      {width, height} =
        if rotated?(angle) do
          # Swap for rotated videos
          {encoded_height, encoded_width}
        else
          {encoded_width, encoded_height}
        end

      metadata
      |> Map.put(:width, width)
      |> Map.put(:height, height)
    else
      metadata
    end
  end

  defp add_duration(metadata, video_stream, format_data) do
    duration = get_float(video_stream, "duration") || get_float(format_data, "duration")

    if duration do
      Map.put(metadata, :duration, duration)
    else
      metadata
    end
  end

  defp add_angle(metadata, video_stream) do
    # Always try to get angle, but only add to metadata if it exists and is not 0
    angle = get_angle(video_stream)

    case angle do
      nil -> metadata
      # Don't include angle: 0 (Rails behavior)
      0 -> metadata
      angle -> Map.put(metadata, :angle, angle)
    end
  end

  defp add_aspect_ratio(metadata, video_stream) do
    case get_display_aspect_ratio(video_stream) do
      nil -> metadata
      ratio -> Map.put(metadata, :display_aspect_ratio, ratio)
    end
  end

  defp add_stream_flags(metadata, video_stream, audio_stream) do
    metadata
    |> Map.put(:video, map_size(video_stream) > 0)
    |> Map.put(:audio, not is_nil(audio_stream))
  end

  defp get_angle(video_stream) do
    # Check tags.rotate first
    tags = Map.get(video_stream, "tags", %{})

    case Map.get(tags, "rotate") do
      nil ->
        # Check side_data for display matrix
        get_display_matrix_rotation(video_stream)

      rotate_value when is_binary(rotate_value) ->
        String.to_integer(rotate_value)

      rotate_value when is_integer(rotate_value) ->
        rotate_value
    end
  rescue
    _ -> nil
  end

  defp get_display_matrix_rotation(video_stream) do
    video_stream
    |> Map.get("side_data_list", [])
    |> Enum.find(fn data -> Map.get(data, "side_data_type") == "Display Matrix" end)
    |> case do
      nil ->
        nil

      display_matrix ->
        case Map.get(display_matrix, "rotation") do
          rotation when is_binary(rotation) -> String.to_integer(rotation)
          rotation when is_integer(rotation) -> rotation
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp get_display_aspect_ratio(video_stream) do
    case Map.get(video_stream, "display_aspect_ratio") do
      nil ->
        nil

      ratio_string when is_binary(ratio_string) ->
        case String.split(ratio_string, ":", parts: 2) do
          [num_str, den_str] ->
            try do
              numerator = String.to_integer(num_str)
              denominator = String.to_integer(den_str)

              if numerator > 0 && denominator > 0 do
                [numerator, denominator]
              else
                nil
              end
            rescue
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp rotated?(angle) when is_integer(angle) do
    angle == 90 or angle == 270 or angle == -90 or angle == -270
  end

  defp rotated?(_), do: false

  defp get_float(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        try do
          String.to_float(value)
        rescue
          _ ->
            try do
              String.to_integer(value) * 1.0
            rescue
              _ -> nil
            end
        end

      value when is_number(value) ->
        value * 1.0

      _ ->
        nil
    end
  end

  defp parse_ffprobe_output(output) do
    case Jason.decode(output) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end
end
