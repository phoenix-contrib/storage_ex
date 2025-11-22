defmodule StorageEx.PreviewVariantIntegrationTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  alias StorageEx.PreviewVariant
  alias StorageEx.Previewers.{MuPDFPreviewer, PopplerPDFPreviewer, VideoPreviewer}

  @fixtures_path Path.expand("fixtures/files", __DIR__)

  describe "PreviewVariant.process/1 with video" do
    @tag :integration
    test "generates preview and applies variant transformation" do
      if VideoPreviewer.available?() do
        # Upload video
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_video_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Create preview variant
          pv =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [100, 100]]
            )

          # Not processed yet
          refute PreviewVariant.processed?(pv)

          # Process
          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Now processed
          assert PreviewVariant.processed?(pv)

          # Verify exists in storage
          pv_key = PreviewVariant.key(pv)
          assert StorageEx.exists?(pv_key)

          # Download and verify
          {:ok, pv_data} = PreviewVariant.download(pv)
          assert is_binary(pv_data)
          assert byte_size(pv_data) > 0

          # Verify it's a PNG (default format)
          assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = pv_data

          # Verify dimensions with Image if available
          if Code.ensure_loaded?(Image) do
            temp_path = Path.join(System.tmp_dir!(), "test_pv_#{:rand.uniform(100_000)}.png")

            try do
              File.write!(temp_path, pv_data)
              {:ok, image} = Image.open(temp_path)
              width = Image.width(image)
              height = Image.height(image)

              # Should be <= 100 in both dimensions
              assert width <= 100
              assert height <= 100
            after
              File.rm(temp_path)
            end
          end

          # Get URL
          url = PreviewVariant.url(pv)
          assert is_binary(url)
          assert url =~ "pv_video"

          # Process again should use cache
          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Cleanup
          PreviewVariant.delete(pv)
          refute StorageEx.exists?(pv_key)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "generates preview variant with JPEG format" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_jpg_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          pv =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [100, 100], format: :jpg]
            )

          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Download and verify it's JPEG
          {:ok, pv_data} = PreviewVariant.download(pv)
          assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = pv_data

          # Cleanup
          PreviewVariant.delete(pv)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "generates preview variant with time option" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_time_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Preview at 1 second with variant
          pv =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              time: "00:00:01",
              variant: [resize_to_limit: [100, 100]]
            )

          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Verify different key than default time
          pv_default =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [100, 100]]
            )

          assert PreviewVariant.key(pv) != PreviewVariant.key(pv_default)

          # Cleanup
          PreviewVariant.delete(pv)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "generates multiple sizes from same video" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_multi_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Create multiple sizes
          small =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [50, 50]]
            )

          medium =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [100, 100]]
            )

          large =
            PreviewVariant.new(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [200, 200]]
            )

          # Process all
          assert {:ok, ^small} = PreviewVariant.process(small)
          assert {:ok, ^medium} = PreviewVariant.process(medium)
          assert {:ok, ^large} = PreviewVariant.process(large)

          # All should have different keys
          assert PreviewVariant.key(small) != PreviewVariant.key(medium)
          assert PreviewVariant.key(medium) != PreviewVariant.key(large)

          # All should exist
          assert PreviewVariant.processed?(small)
          assert PreviewVariant.processed?(medium)
          assert PreviewVariant.processed?(large)

          # Cleanup
          PreviewVariant.delete(small)
          PreviewVariant.delete(medium)
          PreviewVariant.delete(large)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end

  describe "PreviewVariant.process/1 with PDF" do
    @tag :integration
    test "generates PDF preview with variant" do
      if PopplerPDFPreviewer.available?() or
           MuPDFPreviewer.available?() do
        pdf_path = Path.join(@fixtures_path, "report.pdf")
        pdf_data = File.read!(pdf_path)
        pdf_key = "test_pdfs/pv_report_#{:rand.uniform(100_000)}.pdf"

        StorageEx.upload(pdf_key, pdf_data, content_type: "application/pdf")

        try do
          pv =
            PreviewVariant.new(pdf_key,
              content_type: "application/pdf",
              variant: [resize_to_limit: [200, 200]]
            )

          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Verify exists
          assert PreviewVariant.processed?(pv)

          # Download and verify
          {:ok, pv_data} = PreviewVariant.download(pv)
          assert is_binary(pv_data)

          # Verify PNG
          assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = pv_data

          # Get URL
          url = PreviewVariant.url(pv)
          assert is_binary(url)

          # Cleanup
          PreviewVariant.delete(pv)
        after
          StorageEx.delete(pdf_key)
        end
      else
        IO.puts("Skipping test: Neither Poppler nor MuPDF is installed")
      end
    end
  end

  describe "PreviewVariant without variant" do
    @tag :integration
    test "works as plain preview when no variant specified" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_plain_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # No variant option
          pv = PreviewVariant.new(video_key, content_type: "video/mp4")

          assert {:ok, ^pv} = PreviewVariant.process(pv)

          # Should work like a plain preview
          {:ok, pv_data} = PreviewVariant.download(pv)
          assert is_binary(pv_data)

          # Cleanup
          PreviewVariant.delete(pv)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end

  describe "PreviewVariant via public API" do
    @tag :integration
    test "works with StorageEx.preview_variant/2" do
      if VideoPreviewer.available?() do
        video_path = Path.join(@fixtures_path, "video.mp4")
        video_data = File.read!(video_path)
        video_key = "test_videos/pv_api_#{:rand.uniform(100_000)}.mp4"

        StorageEx.upload(video_key, video_data, content_type: "video/mp4")

        try do
          # Use public API
          pv =
            StorageEx.preview_variant(video_key,
              content_type: "video/mp4",
              variant: [resize_to_limit: [100, 100]]
            )

          assert %PreviewVariant{} = pv
          assert {:ok, ^pv} = PreviewVariant.process(pv)

          url = PreviewVariant.url(pv)
          assert is_binary(url)

          # Cleanup
          PreviewVariant.delete(pv)
        after
          StorageEx.delete(video_key)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end
end
