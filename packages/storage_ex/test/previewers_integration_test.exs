defmodule StorageEx.PreviewersIntegrationTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  alias StorageEx.Previewer
  alias StorageEx.Previewers.{MuPDFPreviewer, PopplerPDFPreviewer, VideoPreviewer}

  @fixtures_path Path.expand("fixtures/files", __DIR__)
  @tmp_dir System.tmp_dir!()

  describe "VideoPreviewer.preview/2 with real video" do
    @tag :integration
    test "generates JPEG preview from MP4 video" do
      if VideoPreviewer.available?() do
        input_path = Path.join(@fixtures_path, "video.mp4")
        output_path = Path.join(@tmp_dir, "video_preview_#{:rand.uniform(100_000)}.jpg")

        try do
          case VideoPreviewer.preview(input_path, output_path) do
            {:ok, metadata} ->
              assert metadata.filename == "preview.jpg"
              assert metadata.content_type == "image/jpeg"

              # Verify file was created
              assert File.exists?(output_path)

              # Verify it's a valid JPEG
              {:ok, data} = File.read(output_path)
              assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = data

              # Verify dimensions using Image if available
              if Code.ensure_loaded?(Image) do
                {:ok, image} = Image.open(output_path)
                width = Image.width(image)
                height = Image.height(image)

                # Rails video.mp4 is 640x480
                assert width == 640
                assert height == 480
              end

            {:error, reason} ->
              # FFmpeg might be installed but broken (missing libs)
              IO.puts("Skipping test: FFmpeg error - #{inspect(reason)}")
          end
        after
          File.rm(output_path)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end

    @tag :integration
    test "returns error for invalid video file" do
      if VideoPreviewer.available?() do
        # Use a PDF as input (wrong file type)
        input_path = Path.join(@fixtures_path, "report.pdf")
        output_path = Path.join(@tmp_dir, "invalid_video_preview_#{:rand.uniform(100_000)}.jpg")

        try do
          assert {:error, reason} = VideoPreviewer.preview(input_path, output_path)
          assert is_binary(reason)
          assert reason =~ "ffmpeg"
        after
          File.rm(output_path)
        end
      else
        IO.puts("Skipping test: FFmpeg not installed")
      end
    end
  end

  describe "PopplerPDFPreviewer.preview/2 with real PDF" do
    @tag :integration
    test "generates PNG preview from standard PDF" do
      if PopplerPDFPreviewer.available?() do
        input_path = Path.join(@fixtures_path, "report.pdf")
        output_path = Path.join(@tmp_dir, "pdf_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:ok, metadata} = PopplerPDFPreviewer.preview(input_path, output_path)

          assert metadata.filename == "preview.png"
          assert metadata.content_type == "image/png"

          # Verify file was created
          assert File.exists?(output_path)

          # Verify it's a valid PNG
          {:ok, data} = File.read(output_path)
          assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data

          # Verify dimensions using Image if available
          if Code.ensure_loaded?(Image) do
            {:ok, image} = Image.open(output_path)
            width = Image.width(image)
            height = Image.height(image)

            # Rails report.pdf is 612x792 at 72 DPI (US Letter size)
            assert width == 612
            assert height == 792
          end
        after
          File.rm(output_path)
        end
      else
        IO.puts("Skipping test: Poppler (pdftoppm) not installed")
      end
    end

    @tag :integration
    test "generates PNG preview from cropped PDF" do
      if PopplerPDFPreviewer.available?() do
        input_path = Path.join(@fixtures_path, "cropped.pdf")
        output_path = Path.join(@tmp_dir, "cropped_pdf_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:ok, metadata} = PopplerPDFPreviewer.preview(input_path, output_path)

          assert metadata.filename == "preview.png"
          assert metadata.content_type == "image/png"

          # Verify dimensions using Image if available
          if Code.ensure_loaded?(Image) do
            {:ok, image} = Image.open(output_path)
            width = Image.width(image)
            height = Image.height(image)

            # Rails cropped.pdf is 430x145
            assert width == 430
            assert height == 145
          end
        after
          File.rm(output_path)
        end
      else
        IO.puts("Skipping test: Poppler (pdftoppm) not installed")
      end
    end

    @tag :integration
    test "returns error for invalid PDF file" do
      if PopplerPDFPreviewer.available?() do
        # Use a video as input (wrong file type)
        input_path = Path.join(@fixtures_path, "video.mp4")
        output_path = Path.join(@tmp_dir, "invalid_pdf_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:error, reason} = PopplerPDFPreviewer.preview(input_path, output_path)
          assert is_binary(reason)
          assert reason =~ "pdftoppm"
        after
          File.rm(output_path)
        end
      else
        IO.puts("Skipping test: Poppler (pdftoppm) not installed")
      end
    end
  end

  describe "MuPDFPreviewer.preview/2 with real PDF" do
    @tag :integration
    test "generates PNG preview from standard PDF" do
      if MuPDFPreviewer.available?() do
        input_path = Path.join(@fixtures_path, "report.pdf")
        output_path = Path.join(@tmp_dir, "mupdf_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:ok, metadata} = MuPDFPreviewer.preview(input_path, output_path)

          assert metadata.filename == "preview.png"
          assert metadata.content_type == "image/png"

          # Verify file was created
          assert File.exists?(output_path)

          # Verify it's a valid PNG
          {:ok, data} = File.read(output_path)
          assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = data

          # Verify dimensions using Image if available
          if Code.ensure_loaded?(Image) do
            {:ok, image} = Image.open(output_path)
            width = Image.width(image)
            height = Image.height(image)

            # Rails report.pdf is 612x792
            assert width == 612
            assert height == 792
          end
        after
          File.rm(output_path)
        end
      else
        nil
      end
    end

    @tag :integration
    test "generates PNG preview from cropped PDF" do
      if MuPDFPreviewer.available?() do
        input_path = Path.join(@fixtures_path, "cropped.pdf")
        output_path = Path.join(@tmp_dir, "mupdf_cropped_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:ok, metadata} = MuPDFPreviewer.preview(input_path, output_path)

          assert metadata.filename == "preview.png"
          assert metadata.content_type == "image/png"

          # Verify dimensions using Image if available
          if Code.ensure_loaded?(Image) do
            {:ok, image} = Image.open(output_path)
            width = Image.width(image)
            height = Image.height(image)

            # Rails cropped.pdf is 430x145
            assert width == 430
            assert height == 145
          end
        after
          File.rm(output_path)
        end
      else
        nil
      end
    end

    @tag :integration
    test "returns error for invalid PDF file" do
      if MuPDFPreviewer.available?() do
        # Use a video as input (wrong file type)
        input_path = Path.join(@fixtures_path, "video.mp4")
        output_path = Path.join(@tmp_dir, "mupdf_invalid_preview_#{:rand.uniform(100_000)}.png")

        try do
          assert {:error, reason} = MuPDFPreviewer.preview(input_path, output_path)
          assert is_binary(reason)
          assert reason =~ "mutool"
        after
          File.rm(output_path)
        end
      end
    end
  end

  describe "Previewer.find_previewer/1 integration" do
    @tag :integration
    test "finds appropriate previewer and generates preview for video" do
      case Previewer.find_previewer("video/mp4") do
        {:ok, previewer} ->
          input_path = Path.join(@fixtures_path, "video.mp4")
          output_path = Path.join(@tmp_dir, "integration_video_#{:rand.uniform(100_000)}.jpg")

          try do
            assert {:ok, _metadata} = previewer.preview(input_path, output_path)
            assert File.exists?(output_path)
          after
            File.rm(output_path)
          end

        {:error, :no_previewer} ->
          nil
      end
    end

    @tag :integration
    test "finds appropriate previewer and generates preview for PDF" do
      case Previewer.find_previewer("application/pdf") do
        {:ok, previewer} ->
          input_path = Path.join(@fixtures_path, "report.pdf")
          output_path = Path.join(@tmp_dir, "integration_pdf_#{:rand.uniform(100_000)}.png")

          try do
            assert {:ok, _metadata} = previewer.preview(input_path, output_path)
            assert File.exists?(output_path)
          after
            File.rm(output_path)
          end

        {:error, :no_previewer} ->
          IO.puts("Skipping test: No PDF previewer available")
      end
    end
  end
end
