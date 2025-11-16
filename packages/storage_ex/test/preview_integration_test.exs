defmodule StorageEx.PreviewIntegrationTest do
  use ExUnit.Case, async: false
  use StorageEx.Support.DiskCleanup

  alias StorageEx.Preview
  alias StorageEx.Previewers.{VideoPreviewer, PopplerPDFPreviewer}

  @fixtures_path Path.expand("fixtures/files", __DIR__)

  describe "Preview.process/1 with video" do
    @tag :integration
    test "generates and caches video preview" do
      if VideoPreviewer.available?() do
        # Upload the video to storage
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/video_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Create preview specification
          preview = Preview.new(video_key, content_type: "video/mp4")

          # Check it's not processed yet
          refute Preview.processed?(preview)

          # Process the preview
          assert {:ok, ^preview} = Preview.process(preview)

          # Check it's now processed (cached)
          assert Preview.processed?(preview)

          # Verify preview exists in storage
          preview_key = Preview.key(preview)
          assert StorageEx.exists?(preview_key)

          # Download and verify it's a valid image
          {:ok, preview_data} = Preview.download(preview)
          assert is_binary(preview_data)
          assert byte_size(preview_data) > 0

          # Verify it's a PNG (default format)
          assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = preview_data

          # Process again should return cached version immediately
          assert {:ok, ^preview} = Preview.process(preview)

          # Get URL
          url = Preview.url(preview)
          assert is_binary(url)
          assert url =~ "video"

          # Cleanup
          Preview.delete(preview)
          refute StorageEx.exists?(preview_key)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "generates JPEG preview when format specified" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/video_jpg_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Create preview with JPEG format
          preview = Preview.new(video_key, content_type: "video/mp4", format: :jpg)

          # Process the preview
          assert {:ok, ^preview} = Preview.process(preview)

          # Download and verify it's a valid JPEG
          {:ok, preview_data} = Preview.download(preview)
          assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = preview_data

          # Cleanup
          Preview.delete(preview)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "generates preview at specific time position" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/video_time_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Create preview at 1 second mark
          preview = Preview.new(video_key, content_type: "video/mp4", time: "00:00:01")

          # Process the preview
          assert {:ok, ^preview} = Preview.process(preview)

          # Verify it was cached with different key than default
          preview_default = Preview.new(video_key, content_type: "video/mp4")
          assert Preview.key(preview) != Preview.key(preview_default)

          # Cleanup
          Preview.delete(preview)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end

  describe "Preview.process/1 with PDF" do
    @tag :integration
    test "generates and caches PDF preview" do
      if PopplerPDFPreviewer.available?() or
           StorageEx.Previewers.MuPDFPreviewer.available?() do
        # Upload the PDF to storage
        pdf_path = Path.join(@fixtures_path, "report.pdf")
        pdf_data = File.read!(pdf_path)
        pdf_key = "test_pdfs/report_#{:rand.uniform(100_000)}.pdf"

        StorageEx.upload(pdf_key, pdf_data, content_type: "application/pdf")

        try do
          # Create preview specification
          preview = Preview.new(pdf_key, content_type: "application/pdf")

          # Check it's not processed yet
          refute Preview.processed?(preview)

          # Process the preview
          assert {:ok, ^preview} = Preview.process(preview)

          # Check it's now processed (cached)
          assert Preview.processed?(preview)

          # Verify preview exists in storage
          preview_key = Preview.key(preview)
          assert StorageEx.exists?(preview_key)

          # Download and verify it's a valid image
          {:ok, preview_data} = Preview.download(preview)
          assert is_binary(preview_data)
          assert byte_size(preview_data) > 0

          # Verify it's a PNG (default format)
          assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = preview_data

          # Get URL
          url = Preview.url(preview)
          assert is_binary(url)
          assert url =~ "report"

          # Cleanup
          Preview.delete(preview)
          refute StorageEx.exists?(preview_key)
        after
          StorageEx.delete(pdf_key)
        end
      else
        IO.puts("Skipping test: Neither Poppler nor MuPDF is installed")
      end
    end
  end

  describe "Preview.process/1 error handling" do
    @tag :integration
    test "returns error for unsupported content type" do
      # Upload a text file
      text_key = "test_files/text_#{:rand.uniform(100_000)}.txt"
      StorageEx.upload(text_key, "Hello, world!", content_type: "text/plain")

      try do
        preview = Preview.new(text_key, content_type: "text/plain")

        # Should fail because no previewer accepts text/plain
        assert {:error, :no_previewer} = Preview.process(preview)
      after
        StorageEx.delete(text_key)
      end
    end

    @tag :integration
    test "returns error for non-existent blob" do
      preview =
        Preview.new("nonexistent_#{:rand.uniform(100_000)}.mp4", content_type: "video/mp4")

      # Should fail because blob doesn't exist
      assert {:error, _reason} = Preview.process(preview)
    end
  end

  describe "Preview via public API" do
    @tag :integration
    test "works with StorageEx.preview/2" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/video_api_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Use public API
          preview = StorageEx.preview(video_key, content_type: "video/mp4")

          assert %Preview{} = preview
          assert {:ok, ^preview} = Preview.process(preview)

          url = Preview.url(preview)
          assert is_binary(url)

          # Cleanup
          Preview.delete(preview)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end
end
