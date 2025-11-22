defmodule StorageEx.Analyzers.ImageAnalyzerTest do
  use ExUnit.Case, async: true

  alias StorageEx.Analyzers.ImageAnalyzer

  @fixtures_path Path.join([__DIR__, "..", "fixtures", "files"])

  describe "accept?/1" do
    test "accepts image content types" do
      assert ImageAnalyzer.accept?("image/jpeg")
      assert ImageAnalyzer.accept?("image/png")
      assert ImageAnalyzer.accept?("image/gif")
      assert ImageAnalyzer.accept?("image/webp")
      assert ImageAnalyzer.accept?("image/bmp")
      assert ImageAnalyzer.accept?("image/tiff")
      assert ImageAnalyzer.accept?("image/heic")
      assert ImageAnalyzer.accept?("image/heif")
      assert ImageAnalyzer.accept?("image/avif")
    end

    test "rejects non-image content types" do
      refute ImageAnalyzer.accept?("video/mp4")
      refute ImageAnalyzer.accept?("audio/mp3")
      refute ImageAnalyzer.accept?("application/pdf")
      refute ImageAnalyzer.accept?("text/plain")
    end
  end

  describe "available?/0" do
    test "returns boolean indicating Image package availability" do
      result = ImageAnalyzer.available?()
      assert is_boolean(result)
    end
  end

  describe "metadata/2" do
    test "extracts metadata from real image" do
      image_path = Path.join(@fixtures_path, "racecar.jpg")

      {:ok, metadata} = ImageAnalyzer.metadata(image_path, "image/jpeg")

      assert metadata[:width] == 4104
      assert metadata[:height] == 2736
    end

    test "extracts metadata from rotated image" do
      image_path = Path.join(@fixtures_path, "racecar_rotated.jpg")

      {:ok, metadata} = ImageAnalyzer.metadata(image_path, "image/jpeg")

      # Rotated image should still report correct dimensions
      assert is_integer(metadata[:width])
      assert is_integer(metadata[:height])
    end

    test "handles corrupted image files gracefully" do
      # Create a temp file with invalid data
      temp_path =
        Path.join(System.tmp_dir!(), "corrupted_#{:erlang.unique_integer([:positive])}.jpg")

      File.write!(temp_path, "this is not valid image data")

      try do
        result = ImageAnalyzer.metadata(temp_path, "image/jpeg")
        assert {:error, _reason} = result
      after
        File.rm(temp_path)
      end
    end

    test "handles missing files gracefully" do
      non_existent_file = "/tmp/does_not_exist_#{:erlang.unique_integer([:positive])}.jpg"

      result = ImageAnalyzer.metadata(non_existent_file, "image/jpeg")

      assert {:error, _reason} = result
    end
  end
end
