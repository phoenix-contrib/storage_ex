defmodule StorageEx.Previewers.VideoPreviewer do
  @moduledoc """
  Previewer for video files using FFmpeg.

  Extracts a frame from a video file to generate a preview image.
  Requires FFmpeg to be installed on the system.

  ## Installation

  Install FFmpeg on your system:

      # macOS
      brew install ffmpeg

      # Ubuntu/Debian
      apt-get install ffmpeg

      # Alpine Linux
      apk add ffmpeg

  ## Configuration (Optional)

  By default, uses `ffmpeg` from your system PATH.
  Only configure if you need a custom path:

      config :storage_ex,
        ffmpeg_path: "/usr/local/bin/ffmpeg"

  ## Frame Selection

  By default, extracts the first frame. You can specify a different time position:

      VideoPreviewer.preview(input, output, time: "00:00:05")  # 5 seconds in
      VideoPreviewer.preview(input, output, time: "00:01:30")  # 1 minute 30 seconds in

  Or provide custom FFmpeg arguments:

      VideoPreviewer.preview(input, output, custom_args: ["-ss", "00:00:10", "-vframes", "1"])

  ## Supported Formats

  Supports all video formats that FFmpeg can handle, including:
  - MP4 (video/mp4)
  - WebM (video/webm)
  - MOV (video/quicktime)
  - AVI (video/x-msvideo)
  - And many more...
  """

  @behaviour StorageEx.Previewer

  @impl true
  def accept?(content_type) when is_binary(content_type) do
    String.starts_with?(content_type, "video/")
  end

  @impl true
  def preview(input_path, output_path, opts \\ []) do
    case StorageEx.Previewer.execute_command(
           build_ffmpeg_command(input_path, output_path, opts),
           "ffmpeg"
         ) do
      :ok ->
        {:ok, %{filename: "preview.jpg", content_type: "image/jpeg"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available? do
    StorageEx.Previewer.command_available?(ffmpeg_path())
  end

  # Private functions

  defp build_ffmpeg_command(input_path, output_path, opts) do
    base_args = [ffmpeg_path()]

    # Add time seeking if specified
    time_args =
      if time = Keyword.get(opts, :time) do
        ["-ss", time]
      else
        []
      end

    input_args = ["-i", input_path]
    preview_args = preview_arguments(opts)

    base_args ++ time_args ++ input_args ++ preview_args ++ [output_path]
  end

  defp ffmpeg_path do
    Application.get_env(:storage_ex, :ffmpeg_path, "ffmpeg")
  end

  defp preview_arguments(opts) do
    # Check for custom args first
    case Keyword.get(opts, :custom_args) do
      nil ->
        # Use default or configured args
        default_args = [
          "-y",
          "-vframes",
          "1",
          "-f",
          "image2"
        ]

        case Application.get_env(:storage_ex, :video_preview_arguments) do
          nil ->
            default_args

          args when is_binary(args) ->
            String.split(args, " ", trim: true)

          args when is_list(args) ->
            args
        end

      custom_args when is_list(custom_args) ->
        custom_args
    end
  end
end
