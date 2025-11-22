defmodule StorageEx.Analyzers.NullAnalyzer do
  @moduledoc """
  Fallback analyzer that accepts all content types but extracts no metadata.

  This analyzer serves as a catch-all for files that don't have specialized
  analyzers available. It mimics Rails ActiveStorage's NullAnalyzer behavior.

  ## Purpose

  - Provides graceful degradation when no specific analyzer is available
  - Ensures all files can be "analyzed" without errors
  - Returns empty metadata map `%{}` for consistency

  ## Rails Compatibility

  This analyzer provides the same functionality as Rails:
  - `ActiveStorage::Analyzer::NullAnalyzer`
  - Always accepts any content type
  - Always returns empty metadata
  - Never requires background processing
  - Always available (no dependencies)

  ## Usage

  The NullAnalyzer should be placed **last** in the analyzers list so it
  acts as a fallback after all specific analyzers have been tried.

      # config/config.exs
      config :storage_ex, :analyzers, [
        StorageEx.Analyzers.ImageAnalyzer,
        StorageEx.Analyzers.VideoAnalyzer,
        StorageEx.Analyzers.NullAnalyzer  # Always last!
      ]
  """

  @behaviour StorageEx.Analyzer

  @doc """
  Accepts all content types.

  This makes the NullAnalyzer a catch-all fallback for any file type
  that doesn't have a more specific analyzer.
  """
  @impl true
  def accept?(_content_type), do: true

  @doc """
  Returns false for immediate processing.

  Since the NullAnalyzer does no actual work, there's no need
  for background processing.
  """
  @impl true
  def analyze_later?, do: false

  @doc """
  Always available.

  The NullAnalyzer has no external dependencies and is always
  ready to process files.
  """
  @impl true
  def available?, do: true

  @doc """
  Returns empty metadata.

  The NullAnalyzer extracts no information from files, returning
  an empty map for consistency with other analyzers.

  ## Returns

  Always returns `{:ok, %{}}` regardless of file content or type.

  ## Examples

      metadata("/path/to/any/file.ext", "any/content-type")
      #=> {:ok, %{}}
  """
  @impl true
  def metadata(_file_path, _content_type) do
    {:ok, %{}}
  end
end
