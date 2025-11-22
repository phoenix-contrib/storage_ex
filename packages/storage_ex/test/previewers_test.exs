defmodule StorageEx.PreviewersTest do
  use ExUnit.Case, async: true

  alias StorageEx.Previewer
  alias StorageEx.Previewers.{MuPDFPreviewer, PopplerPDFPreviewer, VideoPreviewer}

  describe "Previewer.find_previewer/1" do
    test "finds video previewer for video content types" do
      if VideoPreviewer.available?() do
        assert {:ok, VideoPreviewer} = Previewer.find_previewer("video/mp4")
        assert {:ok, VideoPreviewer} = Previewer.find_previewer("video/webm")
        assert {:ok, VideoPreviewer} = Previewer.find_previewer("video/quicktime")
      else
        assert {:error, :no_previewer} = Previewer.find_previewer("video/mp4")
      end
    end

    test "finds PDF previewer for PDF content type" do
      result = Previewer.find_previewer("application/pdf")

      case result do
        {:ok, previewer} when previewer in [PopplerPDFPreviewer, MuPDFPreviewer] ->
          assert previewer.available?()

        {:error, :no_previewer} ->
          # Neither PDF previewer is available
          refute PopplerPDFPreviewer.available?()
          refute MuPDFPreviewer.available?()
      end
    end

    test "returns error for unsupported content types" do
      assert {:error, :no_previewer} = Previewer.find_previewer("text/plain")
      assert {:error, :no_previewer} = Previewer.find_previewer("application/json")
    end
  end

  describe "VideoPreviewer" do
    test "accept?/1 returns true for video content types" do
      assert VideoPreviewer.accept?("video/mp4")
      assert VideoPreviewer.accept?("video/webm")
      assert VideoPreviewer.accept?("video/quicktime")
      assert VideoPreviewer.accept?("video/x-msvideo")
    end

    test "accept?/1 returns false for non-video content types" do
      refute VideoPreviewer.accept?("application/pdf")
      refute VideoPreviewer.accept?("image/png")
      refute VideoPreviewer.accept?("text/plain")
    end

    test "available?/0 checks for ffmpeg" do
      has_ffmpeg = System.find_executable("ffmpeg") != nil
      assert VideoPreviewer.available?() == has_ffmpeg
    end
  end

  describe "PopplerPDFPreviewer" do
    test "accept?/1 returns true for PDF content types" do
      assert PopplerPDFPreviewer.accept?("application/pdf")
      assert PopplerPDFPreviewer.accept?("application/x-pdf")
    end

    test "accept?/1 returns false for non-PDF content types" do
      refute PopplerPDFPreviewer.accept?("video/mp4")
      refute PopplerPDFPreviewer.accept?("image/png")
      refute PopplerPDFPreviewer.accept?("text/plain")
    end

    test "available?/0 checks for pdftoppm" do
      has_pdftoppm = System.find_executable("pdftoppm") != nil
      assert PopplerPDFPreviewer.available?() == has_pdftoppm
    end
  end

  describe "MuPDFPreviewer" do
    test "accept?/1 returns true for PDF content types" do
      assert MuPDFPreviewer.accept?("application/pdf")
      assert MuPDFPreviewer.accept?("application/x-pdf")
    end

    test "accept?/1 returns false for non-PDF content types" do
      refute MuPDFPreviewer.accept?("video/mp4")
      refute MuPDFPreviewer.accept?("image/png")
      refute MuPDFPreviewer.accept?("text/plain")
    end

    test "available?/0 checks for mutool" do
      has_mutool = System.find_executable("mutool") != nil
      assert MuPDFPreviewer.available?() == has_mutool
    end
  end

  describe "Previewer.command_available?/1" do
    test "returns true for available commands" do
      # ls should be available on all systems
      assert Previewer.command_available?("ls")
    end

    test "returns false for unavailable commands" do
      refute Previewer.command_available?("this_command_does_not_exist_12345")
    end
  end

  describe "Config.previewers/0" do
    test "returns default previewers" do
      previewers = StorageEx.Config.previewers()

      assert is_list(previewers)
      assert PopplerPDFPreviewer in previewers
      assert MuPDFPreviewer in previewers
      assert VideoPreviewer in previewers
    end
  end
end
