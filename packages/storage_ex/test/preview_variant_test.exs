defmodule StorageEx.PreviewVariantTest do
  use ExUnit.Case, async: true

  alias StorageEx.PreviewVariant

  describe "new/2" do
    test "creates preview variant with variant transformations" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      assert pv.preview.blob_key == "video.mp4"
      assert pv.preview.content_type == "video/mp4"
      assert pv.variant != nil
      assert pv.service_name == nil
    end

    test "creates preview variant without variant (plain preview)" do
      pv = PreviewVariant.new("video.mp4", content_type: "video/mp4")

      assert pv.preview.blob_key == "video.mp4"
      assert pv.variant == nil
    end

    test "creates preview variant with preview options" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          time: "00:00:05",
          variant: [resize_to_limit: [100, 100]]
        )

      assert pv.preview.preview_options == [time: "00:00:05"]
      assert pv.variant != nil
    end

    test "creates preview variant with custom service" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          service_name: :s3,
          variant: [resize_to_limit: [100, 100]]
        )

      assert pv.service_name == :s3
    end

    test "creates preview variant with format options" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          format: :jpg,
          variant: [resize_to_limit: [100, 100], format: :webp]
        )

      assert pv.preview.format == :jpg
      assert pv.variant.format == :webp
    end
  end

  describe "key/1" do
    test "generates key for preview without variant" do
      pv = PreviewVariant.new("video.mp4", content_type: "video/mp4")
      key = PreviewVariant.key(pv)

      # Should be same as preview key
      assert String.starts_with?(key, "previews/video.mp4/")
    end

    test "generates key for preview with variant" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      key = PreviewVariant.key(pv)

      # Should be variants/{preview_key}/{variant_hash}
      assert String.starts_with?(key, "variants/previews/video.mp4/")
    end

    test "generates different keys for different variants" do
      pv1 =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      pv2 =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [200, 200]]
        )

      key1 = PreviewVariant.key(pv1)
      key2 = PreviewVariant.key(pv2)

      assert key1 != key2
    end

    test "generates same key for same configuration" do
      pv1 =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      pv2 =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      key1 = PreviewVariant.key(pv1)
      key2 = PreviewVariant.key(pv2)

      assert key1 == key2
    end
  end

  describe "processed?/1" do
    test "returns false for non-existent preview variant" do
      pv =
        PreviewVariant.new("nonexistent.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      refute PreviewVariant.processed?(pv)
    end

    test "returns true for existing preview variant" do
      # Upload a fake preview variant
      pv =
        PreviewVariant.new("test.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      pv_key = PreviewVariant.key(pv)

      StorageEx.upload(pv_key, "fake preview variant data")

      assert PreviewVariant.processed?(pv)

      # Cleanup
      StorageEx.delete(pv_key)
    end
  end

  describe "delete/1" do
    test "deletes preview variant from storage" do
      # Create and upload a fake preview variant
      pv =
        PreviewVariant.new("test_delete.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      pv_key = PreviewVariant.key(pv)

      StorageEx.upload(pv_key, "fake data")
      assert StorageEx.exists?(pv_key)

      # Delete the preview variant
      PreviewVariant.delete(pv)

      refute StorageEx.exists?(pv_key)
    end

    test "does not fail when preview variant doesn't exist" do
      pv =
        PreviewVariant.new("nonexistent.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      # Should not raise
      PreviewVariant.delete(pv)
    end
  end

  describe "StorageEx.preview_variant/2 public API" do
    test "creates preview variant via public API" do
      pv =
        StorageEx.preview_variant("video.mp4",
          content_type: "video/mp4",
          variant: [resize_to_limit: [100, 100]]
        )

      assert %PreviewVariant{} = pv
      assert pv.preview.blob_key == "video.mp4"
      assert pv.variant != nil
    end

    test "creates preview variant with all options via public API" do
      pv =
        StorageEx.preview_variant("video.mp4",
          content_type: "video/mp4",
          time: "00:00:05",
          format: :jpg,
          variant: [resize_to_fill: [200, 200], format: :webp]
        )

      assert pv.preview.format == :jpg
      assert pv.preview.preview_options == [time: "00:00:05"]
      assert pv.variant.format == :webp
    end

    test "creates preview without variant via public API" do
      pv = StorageEx.preview_variant("video.mp4", content_type: "video/mp4")

      assert %PreviewVariant{} = pv
      assert pv.variant == nil
    end
  end

  describe "format and content type handling" do
    test "uses preview format when no variant" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          format: :jpg
        )

      assert pv.preview.format == :jpg
      assert pv.variant == nil
    end

    test "uses variant format when variant specified" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          format: :png,
          variant: [resize_to_limit: [100, 100], format: :webp]
        )

      # Preview is PNG, variant is WebP
      assert pv.preview.format == :png
      assert pv.variant.format == :webp
    end

    test "variant inherits preview format if not specified" do
      pv =
        PreviewVariant.new("video.mp4",
          content_type: "video/mp4",
          format: :jpg,
          variant: [resize_to_limit: [100, 100]]
        )

      # Variant should default to :png (variation default)
      assert pv.variant.format == :png
    end
  end
end
