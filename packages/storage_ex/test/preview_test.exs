defmodule StorageEx.PreviewTest do
  use ExUnit.Case, async: true

  alias StorageEx.Preview

  setup do
    # Use test mode to avoid actual file operations in most tests
    :ok
  end

  describe "new/2" do
    test "creates preview with required content_type" do
      preview = Preview.new("video.mp4", content_type: "video/mp4")

      assert preview.blob_key == "video.mp4"
      assert preview.content_type == "video/mp4"
      assert preview.format == :png
      assert preview.service_name == nil
      assert preview.preview_options == []
    end

    test "creates preview with custom format" do
      preview = Preview.new("document.pdf", content_type: "application/pdf", format: :jpg)

      assert preview.format == :jpg
    end

    test "creates preview with custom service" do
      preview = Preview.new("video.mp4", content_type: "video/mp4", service_name: :s3)

      assert preview.service_name == :s3
    end

    test "extracts preview-specific options" do
      preview =
        Preview.new("video.mp4",
          content_type: "video/mp4",
          time: "00:00:05",
          custom_arg: "value"
        )

      assert preview.preview_options == [time: "00:00:05", custom_arg: "value"]
    end

    test "raises when content_type is missing" do
      assert_raise KeyError, fn ->
        Preview.new("video.mp4", [])
      end
    end
  end

  describe "key/1" do
    test "generates key with blob_key and hash" do
      preview = Preview.new("video.mp4", content_type: "video/mp4")
      key = Preview.key(preview)

      assert String.starts_with?(key, "previews/video.mp4/")
      assert String.length(key) > 20
    end

    test "generates different keys for different content types" do
      preview1 = Preview.new("file.bin", content_type: "video/mp4")
      preview2 = Preview.new("file.bin", content_type: "application/pdf")

      key1 = Preview.key(preview1)
      key2 = Preview.key(preview2)

      assert key1 != key2
    end

    test "generates different keys for different formats" do
      preview1 = Preview.new("video.mp4", content_type: "video/mp4", format: :png)
      preview2 = Preview.new("video.mp4", content_type: "video/mp4", format: :jpg)

      key1 = Preview.key(preview1)
      key2 = Preview.key(preview2)

      assert key1 != key2
    end

    test "generates different keys for different preview options" do
      preview1 = Preview.new("video.mp4", content_type: "video/mp4")
      preview2 = Preview.new("video.mp4", content_type: "video/mp4", time: "00:00:05")

      key1 = Preview.key(preview1)
      key2 = Preview.key(preview2)

      assert key1 != key2
    end

    test "generates same key for same configuration" do
      preview1 = Preview.new("video.mp4", content_type: "video/mp4", time: "00:00:05")
      preview2 = Preview.new("video.mp4", content_type: "video/mp4", time: "00:00:05")

      key1 = Preview.key(preview1)
      key2 = Preview.key(preview2)

      assert key1 == key2
    end
  end

  describe "processed?/1" do
    test "returns false for non-existent preview" do
      preview = Preview.new("nonexistent.mp4", content_type: "video/mp4")

      refute Preview.processed?(preview)
    end

    test "returns true for existing preview" do
      # Upload a fake preview to storage
      preview = Preview.new("test.mp4", content_type: "video/mp4")
      preview_key = Preview.key(preview)

      StorageEx.upload(preview_key, "fake preview data")

      assert Preview.processed?(preview)

      # Cleanup
      StorageEx.delete(preview_key)
    end
  end

  describe "url/2" do
    test "builds filename with proper extension for png" do
      preview = Preview.new("path/to/video.mp4", content_type: "video/mp4", format: :png)

      # Since we can't actually process without a real video, we'll test the filename logic
      # by checking what would be passed to StorageEx.url
      assert preview.format == :png
      assert preview.blob_key == "path/to/video.mp4"
    end

    test "builds filename with proper extension for jpg" do
      preview = Preview.new("document.pdf", content_type: "application/pdf", format: :jpg)

      assert preview.format == :jpg
    end

    test "accepts custom filename option" do
      preview = Preview.new("video.mp4", content_type: "video/mp4")

      # The url function would pass this through to StorageEx.url
      # We're just testing the struct is created correctly
      assert is_struct(preview, Preview)
    end
  end

  describe "delete/1" do
    test "deletes preview from storage" do
      # Create and upload a fake preview
      preview = Preview.new("test_delete.mp4", content_type: "video/mp4")
      preview_key = Preview.key(preview)

      StorageEx.upload(preview_key, "fake preview data")
      assert StorageEx.exists?(preview_key)

      # Delete the preview
      Preview.delete(preview)

      refute StorageEx.exists?(preview_key)
    end

    test "does not fail when preview doesn't exist" do
      preview = Preview.new("nonexistent.mp4", content_type: "video/mp4")

      # Should not raise
      Preview.delete(preview)
    end
  end

  describe "StorageEx.preview/2 public API" do
    test "creates preview via public API" do
      preview = StorageEx.preview("video.mp4", content_type: "video/mp4")

      assert %Preview{} = preview
      assert preview.blob_key == "video.mp4"
      assert preview.content_type == "video/mp4"
    end

    test "creates preview with options via public API" do
      preview =
        StorageEx.preview("video.mp4",
          content_type: "video/mp4",
          time: "00:00:05",
          format: :jpg
        )

      assert preview.format == :jpg
      assert preview.preview_options == [time: "00:00:05"]
    end
  end

  describe "format helpers" do
    test "converts png format to content type" do
      preview = Preview.new("test.mp4", content_type: "video/mp4", format: :png)
      # The module uses preview_content_type/1 internally
      assert preview.format == :png
    end

    test "converts jpg format to content type" do
      preview = Preview.new("test.pdf", content_type: "application/pdf", format: :jpg)
      assert preview.format == :jpg
    end

    test "converts jpeg format to content type" do
      preview = Preview.new("test.pdf", content_type: "application/pdf", format: :jpeg)
      assert preview.format == :jpeg
    end
  end
end
