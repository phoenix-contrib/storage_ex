defmodule StorageEx.Previewer do
  @moduledoc """
  Behaviour for preview generation from non-image files.

  A Previewer extracts a preview image from a blob (PDF, video, etc.),
  similar to Rails' ActiveStorage::Previewer.

  ## Implementation

  Previewers must implement two callbacks:

    * `accept?/1` - Returns true if the previewer can handle the given content type
    * `preview/2` - Generates a preview image from input file to output file

  ## Example

      defmodule MyApp.Previewers.CustomPreviewer do
        @behaviour StorageEx.Previewer

        @impl true
        def accept?("application/custom"), do: true
        def accept?(_), do: false

        @impl true
        def preview(input_path, output_path) do
          # Generate preview image
          # ...
          {:ok, %{filename: "preview.png", content_type: "image/png"}}
        end

        @impl true
        def available?() do
          System.find_executable("custom-tool") != nil
        end
      end

  ## Built-in Previewers

  StorageEx provides these previewers out of the box:

    * `StorageEx.Previewers.VideoPreviewer` - Extracts first frame from videos using FFmpeg
    * `StorageEx.Previewers.PopplerPDFPreviewer` - Renders first page of PDFs using Poppler (pdftoppm)
    * `StorageEx.Previewers.MuPDFPreviewer` - Renders first page of PDFs using MuPDF (mutool)

  ## Configuration

  Configure available previewers in your config:

      config :storage_ex,
        previewers: [
          StorageEx.Previewers.PopplerPDFPreviewer,
          StorageEx.Previewers.MuPDFPreviewer,
          StorageEx.Previewers.VideoPreviewer
        ]

  The first previewer that returns `true` from `accept?/1` will be used.
  """

  @type content_type :: String.t()
  @type path :: String.t()
  @type preview_metadata :: %{
          filename: String.t(),
          content_type: String.t()
        }

  @doc """
  Determines if this previewer can handle the given content type.

  ## Examples

      VideoPreviewer.accept?("video/mp4")
      #=> true

      VideoPreviewer.accept?("application/pdf")
      #=> false
  """
  @callback accept?(content_type()) :: boolean()

  @doc """
  Generates a preview image from the input file and writes it to the output file.

  Returns `{:ok, metadata}` with preview filename and content type on success.
  Returns `{:error, reason}` on failure.

  ## Options

  Options are previewer-specific. For video previewers:
    * `:time` - Time position to extract frame from (e.g., "00:00:05" for 5 seconds)
    * `:custom_args` - Custom FFmpeg arguments to override defaults

  ## Examples

      VideoPreviewer.preview("/tmp/input.mp4", "/tmp/output.jpg")
      #=> {:ok, %{filename: "video.jpg", content_type: "image/jpeg"}}

      VideoPreviewer.preview("/tmp/input.mp4", "/tmp/output.jpg", time: "00:00:05")
      #=> {:ok, %{filename: "video.jpg", content_type: "image/jpeg"}}
  """
  @callback preview(input_path :: path(), output_path :: path(), opts :: keyword()) ::
              {:ok, preview_metadata()} | {:error, term()}

  @doc """
  Checks if the previewer's dependencies are available.

  Returns `true` if the required system commands/libraries are installed.

  ## Examples

      VideoPreviewer.available?()
      #=> true  # if FFmpeg is installed
  """
  @callback available?() :: boolean()

  @doc """
  Finds the first previewer that can handle the given content type.

  Returns `{:ok, previewer_module}` if a previewer is found, or `{:error, :no_previewer}` otherwise.

  ## Examples

      StorageEx.Previewer.find_previewer("video/mp4")
      #=> {:ok, StorageEx.Previewers.VideoPreviewer}

      StorageEx.Previewer.find_previewer("text/plain")
      #=> {:error, :no_previewer}
  """
  def find_previewer(content_type) do
    previewers = StorageEx.Config.previewers()

    Enum.find_value(previewers, {:error, :no_previewer}, fn previewer ->
      if previewer.available?() and previewer.accept?(content_type) do
        {:ok, previewer}
      else
        false
      end
    end)
  end

  @doc """
  Helper function to execute a system command and capture output to a file.

  This is useful for previewers that shell out to system tools.

  ## Examples

      StorageEx.Previewer.execute_command(
        ["ffmpeg", "-i", input_path, "-frames:v", "1", output_path],
        "ffmpeg"
      )
  """
  def execute_command(command_parts, command_name) do
    case System.cmd(List.first(command_parts), Enum.drop(command_parts, 1),
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        {:error, "#{command_name} failed (exit code #{exit_code}): #{String.trim(output)}"}
    end
  end

  @doc """
  Checks if a system command is available.

  ## Examples

      StorageEx.Previewer.command_available?("ffmpeg")
      #=> true

      StorageEx.Previewer.command_available?("nonexistent")
      #=> false
  """
  def command_available?(command_name) do
    case System.cmd("which", [command_name], stderr_to_stdout: true) do
      {_path, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
