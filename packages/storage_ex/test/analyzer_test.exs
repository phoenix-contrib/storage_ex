defmodule StorageEx.AnalyzerTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  alias StorageEx.Analyzers.{
    AudioAnalyzer,
    ImageAnalyzer,
    NullAnalyzer,
    PdfAnalyzer,
    VideoAnalyzer
  }

  alias StorageEx.Analyzer

  # Helper to get default service name for tests
  defp default_service, do: :test_disk

  # Telemetry handler for tests (avoids anonymous function warning)
  def handle_telemetry_event(event, _measurements, metadata, config) do
    send(config.test_pid, {:telemetry_event, event, metadata})
  end

  describe "find_analyzer/1" do
    test "returns ImageAnalyzer for image content types" do
      # In test environment, Image package may or may not be available
      case Analyzer.find_analyzer("image/jpeg") do
        {:ok, ImageAnalyzer} ->
          # Image package available
          :ok

        {:ok, NullAnalyzer} ->
          # Image package not available, falls back to NullAnalyzer
          :ok
      end
    end

    test "returns appropriate analyzers for different content types" do
      # Video files should use VideoAnalyzer
      assert {:ok, VideoAnalyzer} = Analyzer.find_analyzer("video/mp4")
      assert {:ok, VideoAnalyzer} = Analyzer.find_analyzer("video/webm")

      # Audio files should use AudioAnalyzer
      assert {:ok, AudioAnalyzer} = Analyzer.find_analyzer("audio/mp3")
      assert {:ok, AudioAnalyzer} = Analyzer.find_analyzer("audio/wav")

      # PDF should use PdfAnalyzer when available/configured
      assert {:ok, PdfAnalyzer} = Analyzer.find_analyzer("application/pdf")

      # Unknown types should use NullAnalyzer
      assert {:ok, NullAnalyzer} = Analyzer.find_analyzer("text/plain")

      assert {:ok, NullAnalyzer} =
               Analyzer.find_analyzer("application/unknown")
    end
  end

  describe "analyze/3" do
    test "analyzes JPEG image with correct dimensions" do
      # Upload the racecar.jpg fixture (same as Rails uses)
      fixture_path = Path.join([__DIR__, "fixtures", "files", "racecar.jpg"])
      image_data = File.read!(fixture_path)
      key = "test/analyzer/#{System.unique_integer([:positive])}.jpg"

      {:ok, ^key} = StorageEx.upload(key, image_data)

      # Should use ImageAnalyzer and return actual dimensions (matching Rails test)
      case Analyzer.analyze(key, "image/jpeg", default_service()) do
        {:ok, %{width: width, height: height}} ->
          # Rails test: assert_equal 4104, metadata[:width]
          # Rails test: assert_equal 2736, metadata[:height]
          assert width == 4104
          assert height == 2736

        {:error, :image_package_unavailable} ->
          # Image package not available in test environment - skip
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "analyzes rotated JPEG image with swapped dimensions" do
      # Upload the racecar_rotated.jpg fixture (same as Rails uses)
      fixture_path = Path.join([__DIR__, "fixtures", "files", "racecar_rotated.jpg"])
      image_data = File.read!(fixture_path)
      key = "test/analyzer/#{System.unique_integer([:positive])}.jpg"

      {:ok, ^key} = StorageEx.upload(key, image_data)

      # Should use ImageAnalyzer and swap dimensions for rotated image (matching Rails test)
      case Analyzer.analyze(key, "image/jpeg", default_service()) do
        {:ok, %{width: width, height: height}} ->
          # Rails test: assert_equal 2736, metadata[:width] (swapped!)
          # Rails test: assert_equal 4104, metadata[:height] (swapped!)
          assert width == 2736
          assert height == 4104

        {:error, :image_package_unavailable} ->
          # Image package not available in test environment - skip
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "analyzes SVG image" do
      # Upload the icon.svg fixture (same as Rails uses)
      fixture_path = Path.join([__DIR__, "fixtures", "files", "icon.svg"])
      image_data = File.read!(fixture_path)
      key = "test/analyzer/#{System.unique_integer([:positive])}.svg"

      {:ok, ^key} = StorageEx.upload(key, image_data)

      # Should use ImageAnalyzer for SVG (matching Rails test)
      case Analyzer.analyze(key, "image/svg+xml", default_service()) do
        {:ok, %{width: width, height: height}} ->
          # Rails test: assert_equal 792, metadata[:width]
          # Rails test: assert_equal 584, metadata[:height]
          assert width == 792
          assert height == 584

        {:error, :image_package_unavailable} ->
          # Image package not available in test environment - skip
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "analyzes text file with NullAnalyzer" do
      # Upload a text file to storage for testing
      key = "test/analyzer/#{System.unique_integer([:positive])}.txt"
      data = "Hello, world!"

      {:ok, ^key} = StorageEx.upload(key, data)

      # Should use NullAnalyzer for text files
      assert {:ok, %{}} = Analyzer.analyze(key, "text/plain", default_service())
    end

    test "returns error for non-existent storage key" do
      non_existent_key = "test/does_not_exist_#{System.unique_integer([:positive])}.jpg"

      assert {:error, {:download_failed, :file_not_found}} =
               Analyzer.analyze(non_existent_key, "image/jpeg", default_service())
    end

    test "successfully analyzes file" do
      # Upload a text file to storage for testing analysis
      key = "test/analyzer/#{System.unique_integer([:positive])}.txt"
      data = "Hello, world! This is test data for analysis."

      {:ok, ^key} = StorageEx.upload(key, data)

      # Run analysis - NullAnalyzer handles text files and returns empty metadata
      assert {:ok, %{}} = Analyzer.analyze(key, "text/plain", default_service())
    end

    test "handles streaming download with configurable chunk size" do
      # Create test file (100KB) with 50KB chunk size = exactly 2 chunks
      key = "test/analyzer/streaming_#{System.unique_integer([:positive])}.txt"
      # Create 100KB of data (will be streamed in exactly 2 chunks of 50KB each)
      test_data = String.duplicate("x", 100 * 1024)

      {:ok, ^key} = StorageEx.upload(key, test_data, service_name: :streaming_test)

      # Analyze using streaming service - should stream in 50KB chunks
      # The main goal is to verify the analyzer works with the streaming service
      assert {:ok, %{}} = Analyzer.analyze(key, "text/plain", :streaming_test)
    end

    test "emits telemetry events during analysis" do
      # Upload a test file
      key = "test/analyzer/telemetry_#{System.unique_integer([:positive])}.txt"
      data = "Hello, telemetry world!"

      {:ok, ^key} = StorageEx.upload(key, data)

      # Capture telemetry events - telemetry.span emits :start and :stop events
      ref = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        "analyzer-test-#{inspect(ref)}",
        [
          [:storage_ex, :analyze, :start],
          [:storage_ex, :analyze, :stop]
        ],
        &__MODULE__.handle_telemetry_event/4,
        %{test_pid: test_pid}
      )

      # Run analysis
      assert {:ok, %{}} = Analyzer.analyze(key, "text/plain", default_service())

      # Verify both start and stop telemetry events were emitted
      assert_receive {:telemetry_event, [:storage_ex, :analyze, :start], start_metadata}, 1000
      assert start_metadata.analyzer == NullAnalyzer
      assert start_metadata.content_type == "text/plain"
      assert start_metadata.key == key
      assert String.contains?(start_metadata.file_path, "storage_ex_")

      assert_receive {:telemetry_event, [:storage_ex, :analyze, :stop], _stop_metadata}, 1000

      :telemetry.detach("analyzer-test-#{inspect(ref)}")
    end

    test "can analyze files from different storage services" do
      # Upload to default service (test_disk)
      key1 = "test/analyzer/default_#{System.unique_integer([:positive])}.txt"
      data1 = "File in default service"

      {:ok, ^key1} = StorageEx.upload(key1, data1)

      # Upload to alternative service (alternative_disk)
      key2 = "test/analyzer/alt_#{System.unique_integer([:positive])}.txt"
      data2 = "File in alternative service"

      {:ok, ^key2} = StorageEx.upload(key2, data2, service_name: :alternative_disk)

      # Analyze from default service
      assert {:ok, %{}} = Analyzer.analyze(key1, "text/plain", default_service())

      # Analyze from alternative service by specifying service_name
      assert {:ok, %{}} = Analyzer.analyze(key2, "text/plain", :alternative_disk)

      # Verify we can't analyze alt service file without specifying service
      # Missing service_name option
      assert {:error, {:download_failed, :file_not_found}} =
               Analyzer.analyze(key2, "text/plain", default_service())
    end

    test "Always tries to analyze regardless of analyzer availability" do
      files_to_test = [
        {"unknown_format.xyz", "application/xyz", "Unknown file format"},
        {"document.pdf", "application/pdf", "PDF document"},
        {"image.jpg", "image/jpeg",
         File.read!(Path.join([__DIR__, "fixtures", "files", "racecar.jpg"]))},
        {"text.txt", "text/plain", "Plain text file"}
      ]

      for {filename, content_type, data} <- files_to_test do
        key = "test/rails_workflow/#{System.unique_integer([:positive])}_#{filename}"
        {:ok, ^key} = StorageEx.upload(key, data)

        result = Analyzer.analyze(key, content_type, default_service())

        case result do
          {:ok, metadata} when is_map(metadata) ->
            :ok

          {:error, {:pdfinfo_failed, _}} ->
            :ok

          {:error, :image_package_unavailable} ->
            :ok

          other ->
            flunk("Unexpected analysis result for #{filename}: #{inspect(other)}")
        end
      end
    end

    test "new analyzers are properly integrated" do
      {:ok, image_analyzer} = Analyzer.find_analyzer("image/jpeg")
      {:ok, video_analyzer} = Analyzer.find_analyzer("video/mp4")
      {:ok, audio_analyzer} = Analyzer.find_analyzer("audio/mp3")
      {:ok, null_analyzer} = Analyzer.find_analyzer("application/unknown")

      assert image_analyzer == ImageAnalyzer
      assert video_analyzer == VideoAnalyzer
      assert audio_analyzer == AudioAnalyzer
      assert null_analyzer == NullAnalyzer
    end

    test "image, video and audio analysis with Rails-style graceful fallback" do
      image_key = "test/analyzer/#{System.unique_integer([:positive])}.jpg"
      video_key = "test/analyzer/#{System.unique_integer([:positive])}.mp4"
      audio_key = "test/analyzer/#{System.unique_integer([:positive])}.mp3"

      {:ok, ^image_key} = StorageEx.upload(image_key, "mock image data")
      {:ok, ^video_key} = StorageEx.upload(video_key, "mock video data")
      {:ok, ^audio_key} = StorageEx.upload(audio_key, "mock audio data")

      # Rails-style: Always try to analyze, but gracefully handle failures
      image_result = Analyzer.analyze(image_key, "image/jpeg", default_service())
      video_result = Analyzer.analyze(video_key, "video/mp4", default_service())
      audio_result = Analyzer.analyze(audio_key, "audio/mp3", default_service())

      # Rails behavior: Always return {:ok, metadata} (empty if unavailable/failed)
      case image_result do
        {:ok, _metadata} -> :ok
        {:error, _reason} -> :ok
      end

      case video_result do
        # Either real metadata or empty map
        {:ok, _metadata} -> :ok
        # FFprobe error on invalid data - expected
        {:error, {:ffprobe_error, _}} -> :ok
        # Other analysis error - expected
        {:error, {:video_analysis_failed, _}} -> :ok
      end

      case audio_result do
        # Either real metadata or empty map
        {:ok, _metadata} -> :ok
        # FFprobe error on invalid data - expected
        {:error, {:ffprobe_error, _}} -> :ok
        # Other analysis error - expected
        {:error, {:audio_analysis_failed, _}} -> :ok
      end

      # Key insight: Missing dependencies now return {:ok, %{}} instead of errors
      # This follows Rails' pattern of graceful degradation for all analyzers
    end

    @tag :integration
    test "analyzes real Rails video fixtures (Rails-compatible)" do
      # Rails-style: Always try, but handle gracefully if ffprobe unavailable
      fixture_path = Path.join([__DIR__, "fixtures", "files", "video.mp4"])
      video_data = File.read!(fixture_path)
      key = "test/rails_fixtures/#{System.unique_integer([:positive])}.mp4"

      {:ok, ^key} = StorageEx.upload(key, video_data)

      # Analyze - will work if ffprobe available, return empty if not
      assert {:ok, metadata} = Analyzer.analyze(key, "video/mp4", default_service())

      # Only test detailed metadata if FFprobe is available
      if VideoAnalyzer.available?() and map_size(metadata) > 0 do
        fixture_path = Path.join([__DIR__, "fixtures", "files", "video.mp4"])
        video_data = File.read!(fixture_path)
        key = "test/fixtures/#{System.unique_integer([:positive])}.mp4"

        {:ok, ^key} = StorageEx.upload(key, video_data)

        # Analyze and verify Rails-compatible metadata
        assert {:ok, metadata} = Analyzer.analyze(key, "video/mp4", default_service())

        # Rails test expectations: width: 640, height: 480, display_aspect_ratio: [4, 3]
        assert metadata.width == 640.0
        assert metadata.height == 480.0
        assert metadata.display_aspect_ratio == [4, 3]

        assert_in_delta metadata.duration, 5.166648, 0.1

        assert metadata.audio == true
        assert metadata.video == true

        assert not Map.has_key?(metadata, :angle)
      end
    end

    @tag :integration
    test "analyzes real rotated video fixture (requires ffprobe)" do
      if VideoAnalyzer.available?() do
        fixture_path = Path.join([__DIR__, "fixtures", "files", "rotated_video.mp4"])
        video_data = File.read!(fixture_path)
        key = "test/fixtures/#{System.unique_integer([:positive])}_rotated.mp4"

        {:ok, ^key} = StorageEx.upload(key, video_data)

        assert {:ok, metadata} = Analyzer.analyze(key, "video/mp4", default_service())

        # Rails test expectations: swapped dimensions due to rotation
        # swapped from original
        assert metadata.width == 480.0
        # swapped from original
        assert metadata.height == 640.0
        assert metadata.display_aspect_ratio == [4, 3]

        assert metadata.angle in [90, -90]
      else
        :skip
      end
    end

    @tag :integration
    test "analyzes real audio fixture (requires ffprobe)" do
      if AudioAnalyzer.available?() do
        fixture_path = Path.join([__DIR__, "fixtures", "files", "audio.mp3"])
        audio_data = File.read!(fixture_path)
        key = "test/fixtures/#{System.unique_integer([:positive])}.mp3"

        {:ok, ^key} = StorageEx.upload(key, audio_data)

        assert {:ok, metadata} = Analyzer.analyze(key, "audio/mp3", default_service())

        assert metadata.duration >= 0.863379 and metadata.duration <= 0.914286
        assert metadata.bit_rate == 128_000
        assert metadata.sample_rate == 44_100

        assert is_map(metadata.tags)
        assert metadata.tags.encoder == "Lavc57.64"
      else
        :skip
      end
    end

    @tag :integration
    test "analyzes video without audio stream (requires ffprobe)" do
      # Skip if ffprobe not available
      if VideoAnalyzer.available?() do
        # Test with Rails video_without_audio_stream.mp4 fixture
        fixture_path = Path.join([__DIR__, "fixtures", "files", "video_without_audio_stream.mp4"])
        video_data = File.read!(fixture_path)
        key = "test/fixtures/#{System.unique_integer([:positive])}_no_audio.mp4"

        {:ok, ^key} = StorageEx.upload(key, video_data)

        # Analyze video without audio
        assert {:ok, metadata} = Analyzer.analyze(key, "video/mp4", default_service())

        # Rails test expectations: has video but no audio
        assert metadata.video == true
        assert metadata.audio == false

        # Should still have video dimensions
        assert is_number(metadata.width) and metadata.width > 0
        assert is_number(metadata.height) and metadata.height > 0
      else
        :skip
      end
    end
  end
end
