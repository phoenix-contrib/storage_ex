defmodule StorageEx.Analyzers.AudioAnalyzerTest do
  use ExUnit.Case, async: true

  alias StorageEx.Analyzers.AudioAnalyzer

  describe "unavailable_tools" do
    @tag :unavailable_tools
    test "returns false for available? when ffprobe not installed" do
      refute AudioAnalyzer.available?()
    end

    @tag :unavailable_tools
    test "returns empty metadata when ffprobe unavailable" do
      assert {:ok, %{}} = AudioAnalyzer.metadata("/tmp/test.mp3", "audio/mpeg")
    end
  end

  describe "accept?/1" do
    test "accepts audio content types" do
      assert AudioAnalyzer.accept?("audio/mp3")
      assert AudioAnalyzer.accept?("audio/mpeg")
      assert AudioAnalyzer.accept?("audio/aac")
      assert AudioAnalyzer.accept?("audio/flac")
      assert AudioAnalyzer.accept?("audio/ogg")
      assert AudioAnalyzer.accept?("audio/wav")
      assert AudioAnalyzer.accept?("audio/x-wav")
    end

    test "rejects non-audio content types" do
      refute AudioAnalyzer.accept?("video/mp4")
      refute AudioAnalyzer.accept?("image/jpeg")
      refute AudioAnalyzer.accept?("application/pdf")
      refute AudioAnalyzer.accept?("text/plain")
    end
  end

  describe "analyze_later?/0" do
    test "returns true for background processing" do
      assert AudioAnalyzer.analyze_later?()
    end
  end

  describe "available?/0" do
    test "returns boolean based on ffprobe availability" do
      result = AudioAnalyzer.available?()
      assert is_boolean(result)
    end

    test "checks ffprobe availability correctly" do
      # Test the actual availability logic
      case System.find_executable("ffprobe") do
        nil -> refute AudioAnalyzer.available?()
        _path -> assert AudioAnalyzer.available?()
      end
    end
  end

  describe "metadata/2" do
    test "handles missing files gracefully" do
      non_existent_file = "/tmp/does_not_exist_#{System.unique_integer([:positive])}.mp3"

      result = AudioAnalyzer.metadata(non_existent_file, "audio/mpeg")

      case result do
        {:error, :ffprobe_unavailable} ->
          # FFprobe not available, which is expected in some test environments
          :ok

        {:error, {:ffprobe_error, _}} ->
          # FFprobe available but file doesn't exist - expected behavior
          :ok

        {:error, _reason} ->
          # Other errors are also acceptable for non-existent files
          :ok

        {:ok, _metadata} ->
          # This shouldn't happen for non-existent files
          flunk("Expected error for non-existent file")
      end
    end

    test "handles ffprobe integration correctly" do
      # Test that the analyzer responds appropriately to ffprobe availability
      case AudioAnalyzer.available?() do
        true ->
          # FFprobe available - test with non-existent file should give ffprobe error
          result = AudioAnalyzer.metadata("/tmp/nonexistent.mp3", "audio/mpeg")
          assert match?({:error, {:ffprobe_error, _}}, result)

        false ->
          # FFprobe not available - should return unavailable error
          result = AudioAnalyzer.metadata("/any/path.mp3", "audio/mpeg")
          assert result == {:error, :ffprobe_unavailable}
      end
    end
  end
end
