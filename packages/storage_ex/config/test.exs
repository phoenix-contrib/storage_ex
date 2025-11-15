import Config

config :storage_ex,
  service: :test_disk,
  services: %{
    test_disk: %{
      service: StorageEx.Services.DiskService,
      configuration: %{
        root: Path.join(System.tmp_dir!(), "storage_ex_test")
      }
    }
  }
