defmodule StorageEx.VariantTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  alias StorageEx.{Variant, Variation}

  @fixtures_path Path.expand("fixtures/files", __DIR__)

  setup %{namespace: namespace} do
    # Upload a test image from fixtures to the default service
    # Using racecar.jpg (same as Rails) - 1.1MB JPEG, 640x427px
    test_image_path = Path.join(@fixtures_path, "racecar.jpg")
    test_image_data = File.read!(test_image_path)
    test_key = "#{namespace}/test-images/racecar.jpg"

    {:ok, _} = StorageEx.upload(test_key, test_image_data, content_type: "image/jpeg")

    {:ok, test_key: test_key, test_image_path: test_image_path}
  end

  describe "Variant.new/3" do
    test "creates a variant specification", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [100, 100])

      assert variant.blob_key == test_key
      # Uses default service
      assert variant.service_name == nil
      assert %Variation{} = variant.variation
    end
  end

  describe "Variant.key/1" do
    test "generates consistent keys for same transformations", %{test_key: test_key} do
      variant1 = Variant.new(test_key, resize_to_limit: [100, 100])
      variant2 = Variant.new(test_key, resize_to_limit: [100, 100])

      assert Variant.key(variant1) == Variant.key(variant2)
    end

    test "generates different keys for different transformations", %{test_key: test_key} do
      variant1 = Variant.new(test_key, resize_to_limit: [100, 100])
      variant2 = Variant.new(test_key, resize_to_limit: [200, 200])

      refute Variant.key(variant1) == Variant.key(variant2)
    end

    test "key starts with variants/ prefix", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [100, 100])
      key = Variant.key(variant)

      assert String.starts_with?(key, "variants/#{test_key}/")
    end
  end

  describe "Variant.processed?/1" do
    test "returns false for unprocessed variant", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [100, 100])

      refute Variant.processed?(variant)
    end
  end

  describe "Variant.delete/1" do
    test "deletes variant from service", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [200, 200])

      # Upload a fake variant
      variant_key = Variant.key(variant)
      {:ok, _} = StorageEx.upload(variant_key, "fake data")

      assert StorageEx.exists?(variant_key)

      Variant.delete(variant)

      refute StorageEx.exists?(variant_key)
    end
  end

  describe "Variant.url/2" do
    test "returns URL for variant", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [150, 150], format: :webp)

      # Upload a fake variant to test URL generation
      variant_key = Variant.key(variant)
      {:ok, _} = StorageEx.upload(variant_key, "fake data", content_type: "image/webp")

      # Get URL (should not error)
      url = Variant.url(variant)

      # URL should be a string path (disk service returns path when no endpoint)
      assert is_binary(url)
      assert url =~ "variants/"
    end

    test "includes proper filename with variant extension", %{test_key: test_key} do
      variant = Variant.new(test_key, resize_to_limit: [175, 175], format: :jpg)

      variant_key = Variant.key(variant)
      {:ok, _} = StorageEx.upload(variant_key, "fake data", content_type: "image/jpeg")

      url = Variant.url(variant)

      # Should include the variant key
      assert url =~ variant_key
    end
  end

  # These tests require the `image` package to be installed
  describe "Variant.process/1 with image package" do
    @tag :integration
    test "processes variant and stores in service", %{test_key: test_key} do
      if Code.ensure_loaded?(Image) do
        variant = Variant.new(test_key, resize_to_limit: [50, 50], format: :png)

        assert {:ok, processed_variant} = Variant.process(variant)
        assert processed_variant == variant
        assert Variant.processed?(variant)

        # Verify variant exists in service
        variant_key = Variant.key(variant)
        assert StorageEx.exists?(variant_key)
      else
        IO.puts("Skipping test: Image package not installed")
      end
    end

    @tag :integration
    test "resizes JPEG to specified dimensions matching Rails behavior", %{test_key: test_key} do
      if Code.ensure_loaded?(Image) do
        # Rails test: resize racecar.jpg (1.1MB, 640x427) to [100, 100]
        # Expected result: 100x67 (maintains aspect ratio)
        variant = Variant.new(test_key, resize_to_limit: [100, 100], format: :jpg)

        assert {:ok, _} = Variant.process(variant)
        assert {:ok, data} = Variant.download(variant)

        # Verify dimensions match Rails expectations
        assert {:ok, image} = Image.from_binary(data)
        width = Image.width(image)
        height = Image.height(image)

        assert width == 100
        assert height == 67
      else
        IO.puts("Skipping test: Image package not installed")
      end
    end

    @tag :integration
    test "converts JPEG to PNG format", %{test_key: test_key} do
      if Code.ensure_loaded?(Image) do
        variant = Variant.new(test_key, resize_to_limit: [125, 125], format: :png)

        assert {:ok, _} = Variant.process(variant)
        assert {:ok, data} = Variant.download(variant)

        # Verify it's a valid PNG by checking header
        assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data
      else
        IO.puts("Skipping test: Image package not installed")
      end
    end

    test "returns cached variant on second process call", %{test_key: test_key} do
      if Code.ensure_loaded?(Image) do
        variant = Variant.new(test_key, resize_to_limit: [50, 50], format: :png)

        # First process
        assert {:ok, _} = Variant.process(variant)

        # Second process should use cached variant
        assert {:ok, _} = Variant.process(variant)
        assert Variant.processed?(variant)
      else
        IO.puts("Skipping test: Image package not installed")
      end
    end

    test "downloads processed variant data", %{test_key: test_key} do
      if Code.ensure_loaded?(Image) do
        variant = Variant.new(test_key, resize_to_limit: [50, 50], format: :png)

        assert {:ok, data} = Variant.download(variant)
        assert is_binary(data)
        assert byte_size(data) > 0

        # Verify it's a valid PNG by checking header
        assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data
      else
        IO.puts("Skipping test: Image package not installed")
      end
    end
  end
end
