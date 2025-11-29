defmodule StorageEx.Analyzers.PdfAnalyzer do
  @moduledoc """
  Analyzer for extracting metadata from PDF files.

  This analyzer extracts page count, dimensions, and document information from PDF files
  using system tools like `pdfinfo` or `mutool`. It provides the same behavior as
  Rails ActiveStorage would if it had a PDF analyzer.

  ## Supported Formats

  - PDF files (application/pdf)

  ## Metadata Format

  Returns metadata with document information:

      %{
        pages: 10,
        width: 612.0,
        height: 792.0,
        title: "Document Title",
        author: "Document Author",
        creator: "Adobe Acrobat",
        producer: "Adobe PDF Library",
        creation_date: ~N[2023-01-01 12:00:00],
        modification_date: ~N[2023-01-01 12:00:00]
      }

  ## Dependencies & Rails-Style Graceful Degradation

  ### System Tools (Optional but Recommended)

      # Install pdfinfo (poppler-utils):

      # macOS
      brew install poppler

      # Ubuntu/Debian
      sudo apt update && sudo apt install poppler-utils

      # Alpine Linux (Docker)
      apk add --no-cache poppler-utils

      # Alternative: Install mutool (MuPDF):

      # macOS
      brew install mupdf-tools

      # Ubuntu/Debian
      sudo apt update && sudo apt install mupdf-tools

      # Alpine Linux (Docker)
      apk add --no-cache mupdf-tools

  ### Dependency Strategy (Following Rails ActiveStorage)

  StorageEx follows Rails' proven approach to system dependencies:

  1. **✅ Always Include**: PdfAnalyzer is included by default in configuration
  2. **🕰️ Runtime Check**: Tool availability checked during analysis
  3. **🛡️ Graceful Degradation**: Returns empty metadata `%{}` when unavailable
  4. **📝 Clear Logging**: WARN level logs for missing tools (less serious than gems)

  ### User Experience Without PDF Tools

      # Analysis still works, returns empty metadata
      {:ok, %{}} = StorageEx.analyze(key, "application/pdf", :local)

      # Log output (WARN level - system dependency less serious):
      [warning] Skipping PDF analysis because pdfinfo is not available. Install poppler-utils for PDF analysis support.

  ### Enhanced Experience With PDF Tools

      # Returns rich metadata when tools available
      {:ok, %{pages: 10, width: 612.0, height: 792.0, title: "Document"}} =
        StorageEx.analyze(key, "application/pdf", :local)

  This ensures applications **never break** due to missing dependencies while providing
  clear guidance for optional enhancements.
  """

  @behaviour StorageEx.Analyzer

  alias StorageEx.Notifications

  @doc """
  Accepts PDF content types.

  Corresponds to Rails `blob.pdf?` check (if it existed).
  """
  @impl true
  def accept?("application/pdf"), do: true
  def accept?(_), do: false

  @doc """
  Returns true for background processing.

  PDF analysis can be slow for large documents with many pages.
  """
  @impl true
  def analyze_later?, do: true

  @doc """
  Checks if PDF analysis tools are available.

  Returns false if neither pdfinfo nor mutool are installed.
  """
  @impl true
  def available? do
    pdfinfo_available?() or mutool_available?()
  end

  @doc """
  Extracts metadata from PDF files.

  Uses pdfinfo (preferred) or mutool as fallback to extract:
  - Page count
  - Page dimensions (width/height)
  - Document metadata (title, author, etc.)
  - Creation and modification dates

  ## Returns

  - `{:ok, metadata}` - Analysis successful
  - `{:error, reason}` - Analysis failed

  ## Examples

      metadata("/path/to/document.pdf", "application/pdf")
      #=> {:ok, %{pages: 5, width: 612.0, height: 792.0, title: "My Document"}}

      # When tools unavailable
      metadata("/path/to/document.pdf", "application/pdf")
      #=> {:ok, %{}}
  """
  @impl true
  def metadata(file_path, _content_type) do
    if available?() do
      analyze_pdf_file(file_path)
    else
      # Rails-style: WARN level log for missing system dependency (less serious than gems)
      Notifications.execute(
        [:analyzer, :dependency_missing],
        %{count: 1},
        %{
          analyzer: __MODULE__,
          dependency: "pdfinfo or mutool",
          install_commands: %{
            macos: "brew install poppler (for pdfinfo) or brew install mupdf-tools (for mutool)",
            ubuntu:
              "sudo apt install poppler-utils (for pdfinfo) or sudo apt install mupdf-tools (for mutool)",
            alpine: "apk add poppler-utils (for pdfinfo) or apk add mupdf-tools (for mutool)"
          }
        }
      )

      {:ok, %{}}
    end
  rescue
    # Handle any unexpected errors gracefully
    error ->
      {:error, {:pdf_analysis_failed, error}}
  end

  # Private functions

  defp analyze_pdf_file(file_path) do
    cond do
      pdfinfo_available?() ->
        analyze_with_pdfinfo(file_path)

      mutool_available?() ->
        analyze_with_mutool(file_path)

      true ->
        {:ok, %{}}
    end
  end

  defp analyze_with_pdfinfo(file_path) do
    case System.cmd("pdfinfo", [file_path], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_pdfinfo_output(output)}

      {error_output, _exit_code} ->
        {:error, {:pdfinfo_failed, error_output}}
    end
  rescue
    error ->
      {:error, {:pdfinfo_error, error}}
  end

  defp analyze_with_mutool(file_path) do
    case System.cmd("mutool", ["info", file_path], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_mutool_output(output)}

      {error_output, _exit_code} ->
        {:error, {:mutool_failed, error_output}}
    end
  rescue
    error ->
      {:error, {:mutool_error, error}}
  end

  defp parse_pdfinfo_output(output) do
    lines = String.split(output, "\n")

    Enum.reduce(lines, %{}, fn line, acc ->
      parse_pdfinfo_line(line, acc)
    end)
  end

  defp parse_pdfinfo_line(line, acc) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        key = String.trim(key) |> String.downcase() |> String.replace(" ", "_")
        value = String.trim(value)
        parse_pdfinfo_field(key, value, acc)

      _ ->
        acc
    end
  end

  defp parse_pdfinfo_field(key, value, acc) do
    cond do
      key == "pages" ->
        Map.put(acc, :pages, String.to_integer(value))

      key == "page_size" ->
        parse_page_size(value, acc)

      key in ["title", "author", "creator", "producer"] and value != "" ->
        Map.put(acc, String.to_atom(key), value)

      key == "creationdate" ->
        parse_and_set_date(value, :creation_date, acc)

      key == "moddate" ->
        parse_and_set_date(value, :modification_date, acc)

      true ->
        acc
    end
  end

  defp parse_and_set_date(value, key, acc) do
    case parse_pdf_date(value) do
      {:ok, date} -> Map.put(acc, key, date)
      _ -> acc
    end
  end

  defp parse_mutool_output(output) do
    lines = String.split(output, "\n")

    # mutool info output is different, look for specific patterns
    Enum.reduce(lines, %{}, fn line, acc ->
      parse_mutool_line(line, acc)
    end)
  end

  defp parse_mutool_line(line, acc) do
    cond do
      String.contains?(line, "Pages:") ->
        parse_mutool_pages(line, acc)

      String.contains?(line, "MediaBox:") ->
        parse_mutool_mediabox(line, acc)

      true ->
        acc
    end
  end

  defp parse_mutool_pages(line, acc) do
    case Regex.run(~r/Pages:\s*(\d+)/, line) do
      [_, pages] -> Map.put(acc, :pages, String.to_integer(pages))
      _ -> acc
    end
  end

  defp parse_mutool_mediabox(line, acc) do
    # MediaBox: [ 0 0 612 792 ]
    case Regex.run(~r/MediaBox:\s*\[\s*[\d.]+\s+[\d.]+\s+([\d.]+)\s+([\d.]+)\s*\]/, line) do
      [_, width, height] ->
        acc
        |> Map.put(:width, parse_number(width))
        |> Map.put(:height, parse_number(height))

      _ ->
        acc
    end
  end

  defp parse_page_size(value, acc) do
    # Parse "612 x 792 pts" or similar formats
    case Regex.run(~r/([\d.]+)\s*x\s*([\d.]+)/, value) do
      [_, width, height] ->
        acc
        |> Map.put(:width, parse_number(width))
        |> Map.put(:height, parse_number(height))

      _ ->
        acc
    end
  end

  defp parse_number(str) do
    if String.contains?(str, ".") do
      String.to_float(str)
    else
      String.to_integer(str) |> Kernel./(1.0)
    end
  end

  defp parse_pdf_date(date_string) do
    # PDF dates are in format: D:YYYYMMDDHHmmSSOHH'mm'
    # Example: D:20230101120000+00'00'
    case Regex.run(~r/D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/, date_string) do
      [_, year, month, day, hour, minute, second] ->
        NaiveDateTime.new(
          String.to_integer(year),
          String.to_integer(month),
          String.to_integer(day),
          String.to_integer(hour),
          String.to_integer(minute),
          String.to_integer(second)
        )

      _ ->
        {:error, :invalid_date_format}
    end
  rescue
    _ -> {:error, :date_parse_error}
  end

  defp pdfinfo_available? do
    case System.cmd("which", ["pdfinfo"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp mutool_available? do
    case System.cmd("which", ["mutool"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
