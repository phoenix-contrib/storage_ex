defmodule StorageEx.Analyzer do
  @moduledoc """
  Behaviour for analyzing uploaded files to extract metadata.

  This module defines the contract that all analyzers must implement.
  Analyzers extract metadata from files (images, videos, audio, etc.)
  in a manner compatible with Rails ActiveStorage analyzers.

  ## Usage

  Implement this behaviour in your custom analyzer:

      defmodule MyApp.CustomAnalyzer do
        @behaviour StorageEx.Analyzer

        @impl true
        def accept?(content_type), do: content_type == "application/custom"

        @impl true
        def analyze_later?(), do: true

        @impl true
        def available?(), do: true

        @impl true
        def metadata(file_path, content_type) do
          # Extract metadata from file at file_path
          {:ok, %{custom_field: "value"}}
        end
      end
  """

  @doc """
  Determines whether this analyzer can handle the given content type.

  Corresponds to Rails `ActiveStorage::Analyzer.accept?(blob)`.

  ## Parameters

  - `content_type` - MIME type of the file (e.g., "image/jpeg", "video/mp4")

  ## Returns

  - `true` if this analyzer can process files of this content type
  - `false` otherwise

  ## Examples

      # Image analyzer
      def accept?("image/" <> _), do: true
      def accept?(_), do: false

      # Video analyzer
      def accept?("video/" <> _), do: true
      def accept?(_), do: false
  """
  @callback accept?(content_type :: String.t()) :: boolean()

  @doc """
  Determines whether analysis should be performed asynchronously in a background job.

  Corresponds to Rails `ActiveStorage::Analyzer.analyze_later?`.

  ## Returns

  - `true` if analysis should be queued for background processing (default)
  - `false` if analysis should be performed immediately

  ## Examples

      # Heavy analysis that should be background processed
      def analyze_later?(), do: true

      # Light analysis that can be done immediately
      def analyze_later?(), do: false
  """
  @callback analyze_later?() :: boolean()

  @doc """
  Checks whether this analyzer's dependencies are available.

  This is StorageEx-specific and provides graceful degradation when
  system dependencies (libvips, ffmpeg, etc.) are not installed.

  Rails uses LoadError rescue patterns instead.

  ## Returns

  - `true` if all dependencies are available and analyzer can function
  - `false` if dependencies are missing and analyzer should be skipped
  """
  @callback available?() :: boolean()

  @doc """
  Extracts metadata from the file at the given path.

  Corresponds to Rails `ActiveStorage::Analyzer#metadata` instance method.

  ## Parameters

  - `file_path` - Absolute path to the file to analyze
  - `content_type` - MIME type of the file

  ## Returns

  - `{:ok, metadata}` - Analysis successful, metadata is a map
  - `{:error, reason}` - Analysis failed, reason describes the error

  The metadata map should contain keys similar to Rails analyzers:
  - Images: `%{width: 1024, height: 768}`
  - Videos: `%{width: 640, height: 480, duration: 30.5, angle: 0}`
  - Audio: `%{duration: 180.2, bit_rate: 128000}`
  """
  @callback metadata(file_path :: String.t(), content_type :: String.t()) ::
              {:ok, metadata :: map()} | {:error, reason :: term()}

  @doc """
  Analyzes a file from storage and returns metadata using the appropriate analyzer.

  Downloads the file from the specified storage service and analyzes it locally.
  This maintains the storage abstraction - all file access goes through StorageEx services.

  Following functional programming principles, the service_name is mandatory to ensure
  explicit dependencies and avoid hidden state. This is especially important for
  background jobs which need to know exactly where the file is stored.

  ## Parameters

  - `key` - Storage key of the file to analyze (e.g., "uploads/user/123/avatar.jpg")
  - `content_type` - MIME type of the file
  - `service_name` - Atom identifying which storage service contains the file

  ## Returns

  - `{:ok, metadata}` - Analysis successful
  - `{:error, reason}` - Analysis failed

  ## Examples

      # Analyze from local disk service
      StorageEx.Analyzer.analyze("uploads/image.jpg", "image/jpeg", :local)
      #=> {:ok, %{width: 1024, height: 768}}

      # Analyze from S3 service
      StorageEx.Analyzer.analyze("user/avatar.png", "image/png", :s3)
      #=> {:ok, %{width: 512, height: 512}}

      # Background job usage
      def perform(key, content_type, service_name) do
        StorageEx.Analyzer.analyze(key, content_type, service_name)
      end
  """
  @spec analyze(String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def analyze(key, content_type, service_name) when is_atom(service_name) do
    # First check if we have an analyzer for this content type
    case find_analyzer(content_type) do
      {:ok, analyzer_module} ->
        # Download file and analyze it with automatic cleanup
        download_file_for_analysis(key, [service_name: service_name], fn temp_file_path ->
          perform_analysis(analyzer_module, temp_file_path, content_type, key)
        end)

      {:error, :no_analyzer} ->
        {:error, :no_analyzer}
    end
  end

  @doc """
  Finds the first analyzer that can handle the given content type.

  Iterates through the configured analyzers list and returns the first
  one that both accepts the content type and has its dependencies available.

  This corresponds to Rails' analyzer selection logic where the first
  accepting analyzer in the list is used.

  ## Parameters

  - `content_type` - MIME type to find an analyzer for

  ## Returns

  - `{:ok, analyzer_module}` - Found a suitable analyzer
  - `{:error, :no_analyzer}` - No analyzer can handle this content type

  ## Examples

      StorageEx.Analyzer.find_analyzer("image/jpeg")
      #=> {:ok, StorageEx.Analyzers.ImageAnalyzer}

      StorageEx.Analyzer.find_analyzer("application/unknown")
      #=> {:ok, StorageEx.Analyzers.NullAnalyzer}
  """
  @spec find_analyzer(String.t()) :: {:ok, module()} | {:error, :no_analyzer}
  def find_analyzer(content_type) do
    analyzers = StorageEx.Config.analyzers()

    analyzer =
      Enum.find(analyzers, fn analyzer_module ->
        analyzer_module.available?() and analyzer_module.accept?(content_type)
      end)

    case analyzer do
      nil -> {:error, :no_analyzer}
      analyzer_module -> {:ok, analyzer_module}
    end
  end

  # Private functions

  defp download_file_for_analysis(key, opts, fun) do
    case StorageEx.download_stream(key, opts) do
      {:ok, stream} ->
        temp_file =
          Path.join(System.tmp_dir!(), "storage_ex_#{System.unique_integer([:positive])}")

        try do
          File.open!(temp_file, [:write, :binary], fn file ->
            stream
            |> Stream.each(fn chunk -> IO.binwrite(file, chunk) end)
            |> Stream.run()
          end)

          # Call the analysis function with the temp file
          fun.(temp_file)
        rescue
          error ->
            {:error, {:file_creation_failed, error}}
        after
          # Always clean up temp file
          File.rm(temp_file)
        end

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp perform_analysis(analyzer_module, temp_file_path, content_type, key) do
    # Analyze with telemetry
    metadata = %{
      analyzer: analyzer_module,
      content_type: content_type,
      key: key,
      file_path: temp_file_path
    }

    StorageEx.Notifications.span(:analyze, metadata, fn ->
      analyzer_module.metadata(temp_file_path, content_type)
    end)
  end
end
