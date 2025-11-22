import Config

# NOTE: Not necessary to configure all previewers and analyzers for tests,
# but help understand how they're configured in real usage.
# In case you're here checking. Hi! 👋
config :storage_ex,
  service: :test_disk,
  analyzers: [
    StorageEx.Analyzers.ImageAnalyzer,
    StorageEx.Analyzers.VideoAnalyzer,
    StorageEx.Analyzers.AudioAnalyzer,
    StorageEx.Analyzers.PdfAnalyzer,
    StorageEx.Analyzers.NullAnalyzer
  ],
  previewers: [
    StorageEx.Previewers.PopplerPDFPreviewer,
    StorageEx.Previewers.MuPDFPreviewer,
    StorageEx.Previewers.VideoPreviewer
  ],
  services: %{
    test_disk: %{
      service: StorageEx.Services.DiskService,
      configuration: %{
        root: Path.join(System.tmp_dir!(), "storage_ex_test")
      }
    },
    alternative_disk: %{
      service: StorageEx.Services.DiskService,
      configuration: %{
        root: Path.join(System.tmp_dir!(), "storage_ex_test_alt")
      }
    },
    streaming_test: %{
      service: StorageEx.Services.DiskService,
      configuration: %{
        root: Path.join(System.tmp_dir!(), "storage_ex_streaming_test"),
        # 50KB chunks for efficient testing
        chunk_size: 50 * 1024
      }
    }
  }
