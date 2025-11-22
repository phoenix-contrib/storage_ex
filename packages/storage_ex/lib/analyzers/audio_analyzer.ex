defmodule StorageEx.Analyzers.AudioAnalyzer do
  @moduledoc """
  Analyzer for extracting metadata from audio files using FFprobe.

  This analyzer extracts audio metadata including duration, bit rate, sample rate,
  and internal tags/metadata. It uses FFprobe from the FFmpeg suite, providing the
  same functionality as Rails ActiveStorage AudioAnalyzer.

  ## Supported Formats

  Supports all audio formats supported by FFmpeg, including:
  - MP3, AAC, FLAC, OGG, WAV
  - Various codecs and containers

  ## Metadata Format

  Returns metadata compatible with Rails ActiveStorage AudioAnalyzer:

      %{
        duration: 5.0, bit_rate: 320340, sample_rate: 44100,
        tags: %{encoder: "Lavc57.64", album: "My Album", ...}
      }

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

  1. **✅ Always Include**: AudioAnalyzer is included by default in configuration
  2. **🕰️ Runtime Check**: FFprobe availability checked during analysis, not accept time
  3. **🛡️ Graceful Degradation**: Returns empty metadata `%{}` when FFprobe unavailable
  4. **📝 Clear Logging**: INFO level logs guide users to optional enhancements

  ### User Experience Without FFmpeg

      # Analysis still works, returns empty metadata
      {:ok, %{}} = StorageEx.analyze(key, "audio/mp3", :local)

      # Log output (INFO level - not an error):
      [info] Skipping audio analysis because ffprobe isn't installed

  ### Enhanced Experience With FFmpeg

      # Returns rich metadata when FFprobe available
      {:ok, %{
        duration: 0.863379, bit_rate: 128000, sample_rate: 44100,
        tags: %{encoder: "Lavc57.64"}
      }} = StorageEx.analyze(key, "audio/mp3", :local)

  This ensures applications **never break** due to missing dependencies while providing
  clear guidance for optional enhancements.

  ## Rails Compatibility

  This analyzer provides the same functionality as:
  - `ActiveStorage::Analyzer::AudioAnalyzer`
  - Content type acceptance via `blob.audio?`
  - Rails-style graceful degradation when FFmpeg unavailable

  ## Dependency Strategy

  Following Rails' approach:
  1. **Always Include**: All analyzers are included by default in configuration
  2. **Runtime Check**: FFprobe availability is checked at analysis time, not accept? time
  3. **Graceful Degradation**: Returns empty metadata `%{}` when FFprobe unavailable
  4. **No App Breakage**: Missing dependencies never crash the application
  """

  @behaviour StorageEx.Analyzer

  alias StorageEx.Notifications

  @doc """
  Accepts all audio content types.

  Corresponds to Rails `blob.audio?` check.
  """
  @impl true
  def accept?("audio/" <> _), do: true
  def accept?(_), do: false

  @doc """
  Returns true for background processing.

  Audio analysis can be I/O intensive for large files and metadata extraction.
  """
  @impl true
  def analyze_later?, do: true

  @doc """
  Checks if FFprobe is available on the system.

  Returns false if FFmpeg/FFprobe is not installed.
  """
  @impl true
  def available? do
    case System.find_executable("ffprobe") do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Extracts audio metadata using FFprobe.

  Returns audio information including duration, bit rate, sample rate,
  and embedded tags/metadata.

  ## Returns

  - `{:ok, metadata}` - Analysis successful
  - `{:error, reason}` - Analysis failed

  ## Examples

      metadata("/path/to/audio.mp3", "audio/mpeg")
      #=> {:ok, %{duration: 5.0, bit_rate: 320340, sample_rate: 44100,
      #           tags: %{encoder: "LAME3.98", album: "My Album"}}}

      metadata("/path/to/audio.flac", "audio/flac")
      #=> {:ok, %{duration: 180.2, bit_rate: 1411200, sample_rate: 44100, ...}}
  """
  @impl true
  def metadata(file_path, _content_type) do
    case probe_audio(file_path) do
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
      {:error, {:audio_analysis_failed, error}}
  end

  # Private functions for audio analysis

  defp probe_audio(file_path) do
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
    audio_stream = find_audio_stream(probe_data)

    metadata = %{}

    # Add duration
    metadata = add_duration(metadata, audio_stream)

    # Add bit rate
    metadata = add_bit_rate(metadata, audio_stream)

    # Add sample rate
    metadata = add_sample_rate(metadata, audio_stream)

    # Add tags/metadata
    metadata = add_tags(metadata, audio_stream)

    # Remove nil values (Rails .compact behavior)
    metadata |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
  end

  defp find_audio_stream(probe_data) do
    probe_data
    |> Map.get("streams", [])
    |> Enum.find(fn stream -> Map.get(stream, "codec_type") == "audio" end)
    |> case do
      nil -> %{}
      stream -> stream
    end
  end

  defp add_duration(metadata, audio_stream) when map_size(audio_stream) == 0, do: metadata

  defp add_duration(metadata, audio_stream) do
    case get_float(audio_stream, "duration") do
      nil -> metadata
      duration -> Map.put(metadata, :duration, duration)
    end
  end

  defp add_bit_rate(metadata, audio_stream) when map_size(audio_stream) == 0, do: metadata

  defp add_bit_rate(metadata, audio_stream) do
    case get_integer(audio_stream, "bit_rate") do
      nil -> metadata
      bit_rate -> Map.put(metadata, :bit_rate, bit_rate)
    end
  end

  defp add_sample_rate(metadata, audio_stream) when map_size(audio_stream) == 0, do: metadata

  defp add_sample_rate(metadata, audio_stream) do
    case get_integer(audio_stream, "sample_rate") do
      nil -> metadata
      sample_rate -> Map.put(metadata, :sample_rate, sample_rate)
    end
  end

  defp add_tags(metadata, audio_stream) when map_size(audio_stream) == 0, do: metadata

  defp add_tags(metadata, audio_stream) do
    case Map.get(audio_stream, "tags") do
      nil ->
        metadata

      tags when is_map(tags) and map_size(tags) > 0 ->
        # Convert string keys to atoms for consistency (Rails behavior)
        converted_tags =
          tags
          |> Enum.map(fn {k, v} ->
            # Convert keys to lowercase atoms (common Rails pattern)
            key = k |> String.downcase() |> String.to_atom()
            {key, v}
          end)
          |> Map.new()

        Map.put(metadata, :tags, converted_tags)

      _ ->
        metadata
    end
  end

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

  defp get_integer(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        try do
          String.to_integer(value)
        rescue
          _ -> nil
        end

      value when is_integer(value) ->
        value

      value when is_float(value) ->
        round(value)

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
