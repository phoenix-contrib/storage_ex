defmodule StorageEx.Analyzers.PdfAnalyzerTest do
  use ExUnit.Case, async: true

  alias StorageEx.Analyzers.PdfAnalyzer

  describe "unavailable_tools" do
    @tag :unavailable_tools
    test "returns false for available? when pdfinfo/mutool not installed" do
      refute PdfAnalyzer.available?()
    end

    @tag :unavailable_tools
    test "returns empty metadata when PDF tools unavailable" do
      pdf_path = "/path/to/nonexistent/file.pdf"
      {:ok, metadata} = PdfAnalyzer.metadata(pdf_path, "application/pdf")
      assert metadata == %{}
    end
  end

  describe "accept?/1" do
    test "accepts PDF content types" do
      assert PdfAnalyzer.accept?("application/pdf")
    end

    test "rejects non-PDF content types" do
      refute PdfAnalyzer.accept?("image/jpeg")
      refute PdfAnalyzer.accept?("video/mp4")
      refute PdfAnalyzer.accept?("audio/mp3")
      refute PdfAnalyzer.accept?("text/plain")
      refute PdfAnalyzer.accept?("application/json")
    end
  end

  describe "analyze_later?/0" do
    test "returns true for background processing" do
      assert PdfAnalyzer.analyze_later?()
    end
  end

  describe "available?/0" do
    test "returns boolean based on PDF tool availability" do
      result = PdfAnalyzer.available?()
      assert is_boolean(result)
    end

    test "checks actual tool availability" do
      # Test that available? reflects actual system state
      has_pdfinfo = System.find_executable("pdfinfo") != nil
      has_mutool = System.find_executable("mutool") != nil

      if has_pdfinfo or has_mutool do
        assert PdfAnalyzer.available?()
      else
        refute PdfAnalyzer.available?()
      end
    end
  end

  describe "metadata/2" do
    test "handles missing files gracefully" do
      non_existent_file = "/tmp/does_not_exist_#{System.unique_integer([:positive])}.pdf"

      result = PdfAnalyzer.metadata(non_existent_file, "application/pdf")

      case result do
        {:ok, %{}} ->
          :ok

        {:error, _reason} ->
          :ok

        {:ok, _metadata} ->
          flunk("Expected error for non-existent file")
      end
    end
  end

  describe "Real PDF Integration Tests" do
    @real_pdf_path "test/fixtures/files/report.pdf"

    test "analyzes real PDF file with actual tools when available" do
      if PdfAnalyzer.available?() do
        pdf_path = Path.expand(@real_pdf_path)
        assert File.exists?(pdf_path), "Test PDF file should exist at #{pdf_path}"

        {:ok, metadata} = PdfAnalyzer.metadata(pdf_path, "application/pdf")

        # Verify we got actual metadata from the real PDF
        assert is_map(metadata)
        assert Map.has_key?(metadata, :pages)
        assert metadata.pages > 0

        # The test PDF should have dimensions (standard letter size)
        if Map.has_key?(metadata, :width) and Map.has_key?(metadata, :height) do
          assert metadata.width == 612.0
          assert metadata.height == 792.0
        end

        # Check for document metadata if available
        if Map.has_key?(metadata, :producer) do
          assert is_binary(metadata.producer)
        end
      else
        # Skip test when PDF tools not available
        IO.puts("Skipping real PDF test - no PDF tools available (pdfinfo/mutool)")
        :ok
      end
    end

    test "processes real PDF through StorageEx.Analyzer.analyze/3 integration" do
      if PdfAnalyzer.available?() do
        # Check if PDF analyzer is configured in the test environment
        analyzers = StorageEx.Config.analyzers()

        if StorageEx.Analyzers.PdfAnalyzer in analyzers do
          # First upload the PDF to storage
          pdf_path = Path.expand(@real_pdf_path)
          pdf_data = File.read!(pdf_path)
          key = "test/pdfs/integration_test_#{System.unique_integer([:positive])}.pdf"

          # Upload to storage
          {:ok, ^key} = StorageEx.upload(key, pdf_data, content_type: "application/pdf")

          try do
            # Analyze through the full StorageEx pipeline
            {:ok, metadata} = StorageEx.Analyzer.analyze(key, "application/pdf", :test_disk)

            # Verify we got proper analysis results
            assert is_map(metadata)
            assert Map.has_key?(metadata, :pages)
            # Based on the pdfinfo output above
            assert metadata.pages == 3

            assert metadata.width == 612.0
            assert metadata.height == 792.0
          after
            # Clean up
            StorageEx.delete(key)
          end
        else
          IO.puts(
            "Skipping full integration test - PDF analyzer not configured in test environment"
          )

          IO.puts("Available analyzers: #{inspect(analyzers)}")

          # Test direct analyzer functionality instead
          pdf_path = Path.expand(@real_pdf_path)
          {:ok, metadata} = PdfAnalyzer.metadata(pdf_path, "application/pdf")
          assert Map.has_key?(metadata, :pages)
          IO.puts("Direct analyzer test successful: #{inspect(metadata)}")
        end
      else
        IO.puts("Skipping integration test - no PDF tools available")
        :ok
      end
    end

    test "handles corrupted PDF file gracefully" do
      if PdfAnalyzer.available?() do
        # Create a fake PDF file with invalid content
        fake_pdf_path =
          Path.join(System.tmp_dir!(), "fake_#{System.unique_integer([:positive])}.pdf")

        File.write!(fake_pdf_path, "This is not a real PDF file content")

        try do
          # Should handle the error gracefully
          result = PdfAnalyzer.metadata(fake_pdf_path, "application/pdf")

          case result do
            {:error, _} ->
              # Expected - tools should report error for invalid PDF
              :ok

            {:ok, metadata} ->
              # Some tools might return empty metadata for invalid files
              assert metadata == %{}
          end
        after
          File.rm(fake_pdf_path)
        end
      else
        :ok
      end
    end

    test "compares pdfinfo vs mutool output on real file" do
      # Only run if both tools are available for comparison
      if System.cmd("which", ["pdfinfo"]) |> elem(1) == 0 and
           System.cmd("which", ["mutool"]) |> elem(1) == 0 do
        pdf_path = Path.expand(@real_pdf_path)

        # Test pdfinfo
        pdfinfo_result =
          case System.cmd("pdfinfo", [pdf_path]) do
            {output, 0} -> {:ok, output}
            {_, _} -> :error
          end

        # Test mutool
        mutool_result =
          case System.cmd("mutool", ["info", pdf_path]) do
            {output, 0} -> {:ok, output}
            {_, _} -> :error
          end

        assert pdfinfo_result != :error or mutool_result != :error
      else
        IO.puts("Skipping tool comparison - need both pdfinfo and mutool")
        :ok
      end
    end

    test "verifies PDF analyzer is found by StorageEx.Analyzer.find_analyzer/1" do
      # Check that PDF analyzer is available and accepts PDFs
      assert PdfAnalyzer.available?(), "PDF analyzer should be available"

      assert PdfAnalyzer.accept?("application/pdf"),
             "PDF analyzer should accept PDF content type"

      analyzers = StorageEx.Config.analyzers()

      if StorageEx.Analyzers.PdfAnalyzer in analyzers do
        {:ok, analyzer} = StorageEx.Analyzer.find_analyzer("application/pdf")

        assert analyzer == StorageEx.Analyzers.PdfAnalyzer,
               "Should find PDF analyzer, but got #{inspect(analyzer)}"

        pdf_index = Enum.find_index(analyzers, &(&1 == StorageEx.Analyzers.PdfAnalyzer))
        null_index = Enum.find_index(analyzers, &(&1 == StorageEx.Analyzers.NullAnalyzer))
        assert pdf_index < null_index, "PDF analyzer should come before NullAnalyzer"
      else
        assert PdfAnalyzer.available?()
        assert PdfAnalyzer.accept?("application/pdf")
      end
    end
  end
end
