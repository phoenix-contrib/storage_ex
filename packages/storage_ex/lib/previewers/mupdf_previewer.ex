defmodule StorageEx.Previewers.MuPDFPreviewer do
  @moduledoc """
  Previewer for PDF files using MuPDF's mutool.

  Renders the first page of a PDF file to generate a preview image.
  Requires MuPDF (mutool) to be installed on the system.

  ## Installation

  Install MuPDF on your system:

      # macOS
      brew install mupdf-tools

      # Ubuntu/Debian
      apt-get install mupdf-tools

      # Alpine Linux
      apk add mupdf-tools

  ## Configuration (Optional)

  By default, uses `mutool` from your system PATH.
  Only configure if you need a custom path:

      config :storage_ex,
        mutool_path: "/usr/local/bin/mutool"

  ## Output

  Generates a PNG image from the first page of the PDF.

  ## Note

  This previewer is an alternative to PopplerPDFPreviewer. Configure previewers
  in your application to choose which one to use first:

      config :storage_ex,
        previewers: [
          StorageEx.Previewers.MuPDFPreviewer,      # Try MuPDF first
          StorageEx.Previewers.PopplerPDFPreviewer, # Fallback to Poppler
          StorageEx.Previewers.VideoPreviewer
        ]
  """

  @behaviour StorageEx.Previewer

  require Logger

  @impl true
  def accept?(content_type) when is_binary(content_type) do
    content_type in ["application/pdf", "application/x-pdf"]
  end

  @impl true
  def preview(input_path, output_path, _opts \\ []) do
    case StorageEx.Previewer.execute_command(
           build_mutool_command(input_path, output_path),
           "mutool"
         ) do
      :ok ->
        {:ok, %{filename: "preview.png", content_type: "image/png"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available?() do
    # MuPDF's mutool exits with status 1 when called with no arguments
    # So we need a custom check
    case System.cmd(mutool_path(), [], stderr_to_stdout: true) do
      {_output, 1} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  # Private functions

  defp build_mutool_command(input_path, output_path) do
    [
      mutool_path(),
      "draw",
      # PNG format
      "-F",
      "png",
      # Output to file
      "-o",
      output_path,
      input_path,
      # First page only
      "1"
    ]
  end

  defp mutool_path do
    Application.get_env(:storage_ex, :mutool_path, "mutool")
  end
end
