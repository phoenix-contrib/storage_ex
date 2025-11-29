defmodule StorageEx.Analyzers.VideoAnalyzerTest do
  use ExUnit.Case, async: true

  alias StorageEx.Analyzers.VideoAnalyzer

  describe "unavailable_tools" do
    @tag :unavailable_tools
    test "returns false for available? when ffprobe not installed" do
      refute VideoAnalyzer.available?()
    end

    @tag :unavailable_tools
    test "returns empty metadata when ffprobe unavailable" do
      assert {:ok, %{}} = VideoAnalyzer.metadata("/tmp/test.mp4", "video/mp4")
    end
  end

  describe "accept?/1" do
    test "accepts video content types" do
      assert VideoAnalyzer.accept?("video/mp4")
      assert VideoAnalyzer.accept?("video/webm")
      assert VideoAnalyzer.accept?("video/avi")
      assert VideoAnalyzer.accept?("video/mov")
      assert VideoAnalyzer.accept?("video/quicktime")
      assert VideoAnalyzer.accept?("video/x-msvideo")
    end

    test "rejects non-video content types" do
      refute VideoAnalyzer.accept?("audio/mp3")
      refute VideoAnalyzer.accept?("image/jpeg")
      refute VideoAnalyzer.accept?("application/pdf")
      refute VideoAnalyzer.accept?("text/plain")
    end
  end

  describe "analyze_later?/0" do
    test "returns true for background processing" do
      assert VideoAnalyzer.analyze_later?()
    end
  end

  describe "available?/0" do
    test "returns boolean based on ffprobe availability" do
      result = VideoAnalyzer.available?()
      assert is_boolean(result)
    end

    test "checks ffprobe availability correctly" do
      # Test the actual availability logic
      case System.find_executable("ffprobe") do
        nil -> refute VideoAnalyzer.available?()
        _path -> assert VideoAnalyzer.available?()
      end
    end
  end

  describe "metadata/2" do
    test "handles missing files gracefully" do
      non_existent_file = "/tmp/does_not_exist_#{System.unique_integer([:positive])}.mp4"

      result = VideoAnalyzer.metadata(non_existent_file, "video/mp4")

      case result do
        {:error, :ffprobe_unavailable} ->
          :ok

        {:error, {:ffprobe_error, _}} ->
          :ok

        {:error, _reason} ->
          :ok

        {:ok, _metadata} ->
          flunk("Expected error for non-existent file")
      end
    end

    test "handles ffprobe integration correctly" do
      case VideoAnalyzer.available?() do
        true ->
          result = VideoAnalyzer.metadata("/tmp/nonexistent.mp4", "video/mp4")
          assert match?({:error, {:ffprobe_error, _}}, result)

        false ->
          result = VideoAnalyzer.metadata("/any/path.mp4", "video/mp4")
          assert result == {:error, :ffprobe_unavailable}
      end
    end

    @tag :integration
    test "extracts real video metadata when ffprobe is available" do
      if VideoAnalyzer.available?() do
        video_path = Path.join([__DIR__, "..", "fixtures", "files", "video.mp4"])

        if File.exists?(video_path) do
          {:ok, metadata} = VideoAnalyzer.metadata(video_path, "video/mp4")

          assert is_map(metadata)
          assert Map.has_key?(metadata, :width)
          assert Map.has_key?(metadata, :height)
          assert Map.has_key?(metadata, :duration)

          assert is_number(metadata.width)
          assert is_number(metadata.height)
          assert is_number(metadata.duration)
        else
          IO.puts("Skipping test: video fixture not found at #{video_path}")
        end
      else
        IO.puts("Skipping test: ffprobe not available")
      end
    end
  end
end
