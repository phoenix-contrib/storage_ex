defmodule StorageEx.Previewers.PopplerPDFPreviewer do
  @moduledoc """
  Previewer for PDF files using Poppler's pdftoppm tool.

  Renders the first page of a PDF file to generate a preview image.
  Requires Poppler utilities to be installed on the system.

  ## Installation

  Install Poppler on your system:

      # macOS
      brew install poppler

      # Ubuntu/Debian
      apt-get install poppler-utils

      # Alpine Linux
      apk add poppler-utils

  ## Configuration (Optional)

  By default, uses `pdftoppm` from your system PATH.
  Only configure if you need a custom path:

      config :storage_ex,
        pdftoppm_path: "/usr/local/bin/pdftoppm"

  ## Output

  Generates a PNG image at 72 DPI (matching standard thumbnail dimensions).
  """

  @behaviour StorageEx.Previewer

  require Logger

  @impl true
  def accept?(content_type) when is_binary(content_type) do
    content_type in ["application/pdf", "application/x-pdf"]
  end

  @impl true
  def preview(input_path, output_path, _opts \\ []) do
    # pdftoppm with -singlefile writes to {base}.png
    # We'll use a base path without extension
    base_path = Path.rootname(output_path)

    case StorageEx.Previewer.execute_command(
           build_pdftoppm_command(input_path, base_path),
           "pdftoppm"
         ) do
      :ok ->
        # pdftoppm creates {base_path}.png with -singlefile flag
        generated_file = "#{base_path}.png"

        # Move to the desired output path if different
        if generated_file == output_path do
          {:ok, %{filename: "preview.png", content_type: "image/png"}}
        else
          case File.rename(generated_file, output_path) do
            :ok ->
              {:ok, %{filename: "preview.png", content_type: "image/png"}}

            {:error, reason} ->
              {:error, "Failed to move preview file: #{inspect(reason)}"}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available?() do
    StorageEx.Previewer.command_available?(pdftoppm_path())
  end

  # Private functions

  defp build_pdftoppm_command(input_path, base_output_path) do
    [
      pdftoppm_path(),
      # Only first page
      "-singlefile",
      # Use crop box for accurate dimensions
      "-cropbox",
      # 72 DPI to match thumbnail dimensions
      "-r",
      "72",
      # PNG format
      "-png",
      input_path,
      base_output_path
    ]
  end

  defp pdftoppm_path do
    Application.get_env(:storage_ex, :pdftoppm_path, "pdftoppm")
  end
end
