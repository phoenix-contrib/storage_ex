defmodule StorageEx.VariationTest do
  use ExUnit.Case, async: true

  alias StorageEx.Variation

  describe "Variation.new/1" do
    test "creates variation with transformations" do
      variation = Variation.new(resize_to_limit: [100, 100])

      assert variation.transformations == [resize_to_limit: [100, 100]]
      # default
      assert variation.format == :png
    end

    test "extracts format from transformations" do
      variation = Variation.new(resize_to_limit: [100, 100], format: :jpg)

      assert variation.transformations == [resize_to_limit: [100, 100]]
      assert variation.format == :jpg
    end

    test "accepts map of transformations" do
      variation = Variation.new(%{resize_to_limit: [100, 100], format: :webp})

      assert Enum.sort(variation.transformations) == [resize_to_limit: [100, 100]]
      assert variation.format == :webp
    end
  end

  describe "Variation.key/1" do
    test "generates consistent hash for same transformations" do
      variation1 = Variation.new(resize_to_limit: [100, 100], format: :png)
      variation2 = Variation.new(resize_to_limit: [100, 100], format: :png)

      assert Variation.key(variation1) == Variation.key(variation2)
    end

    test "generates different hash for different transformations" do
      variation1 = Variation.new(resize_to_limit: [100, 100])
      variation2 = Variation.new(resize_to_limit: [200, 200])

      refute Variation.key(variation1) == Variation.key(variation2)
    end

    test "generates different hash for different formats" do
      variation1 = Variation.new(resize_to_limit: [100, 100], format: :png)
      variation2 = Variation.new(resize_to_limit: [100, 100], format: :jpg)

      refute Variation.key(variation1) == Variation.key(variation2)
    end

    test "returns hex-encoded string" do
      variation = Variation.new(resize_to_limit: [100, 100])
      key = Variation.key(variation)

      assert is_binary(key)
      assert String.match?(key, ~r/^[0-9a-f]+$/)
      # SHA256 hex = 64 chars
      assert String.length(key) == 64
    end
  end

  describe "Variation.content_type/1" do
    test "returns correct MIME type for PNG" do
      variation = Variation.new(format: :png)
      assert Variation.content_type(variation) == "image/png"
    end

    test "returns correct MIME type for JPEG" do
      variation = Variation.new(format: :jpg)
      assert Variation.content_type(variation) == "image/jpeg"
    end

    test "returns correct MIME type for WebP" do
      variation = Variation.new(format: :webp)
      assert Variation.content_type(variation) == "image/webp"
    end

    test "returns correct MIME type for GIF" do
      variation = Variation.new(format: :gif)
      assert Variation.content_type(variation) == "image/gif"
    end
  end

  describe "Variation.extension/1" do
    test "returns correct extension for formats" do
      assert Variation.extension(Variation.new(format: :png)) == "png"
      assert Variation.extension(Variation.new(format: :jpg)) == "jpg"
      assert Variation.extension(Variation.new(format: :jpeg)) == "jpg"
      assert Variation.extension(Variation.new(format: :webp)) == "webp"
      assert Variation.extension(Variation.new(format: :gif)) == "gif"
    end
  end
end
