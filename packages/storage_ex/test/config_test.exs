defmodule StorageEx.ConfigTest do
  use ExUnit.Case, async: true

  alias StorageEx.Config

  describe "normalize_config/1 default behavior" do
    test "creates a filesystem disk service when no services configured" do
      config = Config.normalize_config(%{})

      assert Map.has_key?(config.services, :filesystem_disk)

      service_config = config.services[:filesystem_disk]
      assert service_config.service == StorageEx.Services.DiskService
      assert service_config.configuration.root == "priv/storage"
    end

    test "default service name is :local when not configured" do
      config = Config.normalize_config(%{})

      assert config.service == :local
    end

    test "does not create default filesystem service when services are configured" do
      config =
        Config.normalize_config(%{
          services: %{
            my_disk: %{
              service: StorageEx.Services.DiskService,
              configuration: %{root: "/tmp/custom"}
            }
          }
        })

      assert Map.keys(config.services) == [:my_disk]
      refute Map.has_key?(config.services, :filesystem_disk)
    end

    test "uses configured default service name" do
      config =
        Config.normalize_config(%{
          service: :my_custom_service,
          services: %{
            my_custom_service: %{
              service: StorageEx.Services.DiskService,
              configuration: %{root: "/tmp/custom"}
            }
          }
        })

      assert config.service == :my_custom_service
    end

    test "accepts keyword list input" do
      config =
        Config.normalize_config(
          service: :my_service,
          services: %{
            my_service: %{
              service: StorageEx.Services.DiskService,
              configuration: %{root: "/tmp/test"}
            }
          }
        )

      assert config.service == :my_service
    end
  end

  describe "normalize_config/1 with analyzers and previewers" do
    test "uses default analyzers when not configured" do
      config = Config.normalize_config(%{})

      assert StorageEx.Analyzers.ImageAnalyzer in config.analyzers
      assert StorageEx.Analyzers.VideoAnalyzer in config.analyzers
      assert StorageEx.Analyzers.AudioAnalyzer in config.analyzers
      assert StorageEx.Analyzers.PdfAnalyzer in config.analyzers
      assert StorageEx.Analyzers.NullAnalyzer in config.analyzers
    end

    test "uses custom analyzers when configured" do
      config =
        Config.normalize_config(%{
          analyzers: [StorageEx.Analyzers.NullAnalyzer]
        })

      assert config.analyzers == [StorageEx.Analyzers.NullAnalyzer]
    end

    test "uses default previewers when not configured" do
      config = Config.normalize_config(%{})

      assert StorageEx.Previewers.PopplerPDFPreviewer in config.previewers
      assert StorageEx.Previewers.MuPDFPreviewer in config.previewers
      assert StorageEx.Previewers.VideoPreviewer in config.previewers
    end

    test "uses custom previewers when configured" do
      config =
        Config.normalize_config(%{
          previewers: [StorageEx.Previewers.VideoPreviewer]
        })

      assert config.previewers == [StorageEx.Previewers.VideoPreviewer]
    end
  end

  describe "normalize_config/1 with endpoint" do
    test "endpoint is nil when not configured" do
      config = Config.normalize_config(%{})

      assert config.endpoint == nil
    end

    test "uses configured endpoint" do
      config = Config.normalize_config(%{endpoint: MyAppWeb.Endpoint})

      assert config.endpoint == MyAppWeb.Endpoint
    end
  end

  describe "get_service!/1" do
    test "retrieves service from test config by atom" do
      # Uses the actual test config (test_disk is configured in config/test.exs)
      service = Config.get_service!(:test_disk)
      assert %StorageEx.Services.DiskService{} = service
    end

    test "retrieves service by string name" do
      service = Config.get_service!("test_disk")
      assert %StorageEx.Services.DiskService{} = service
    end

    test "raises error for unknown service" do
      assert_raise ArgumentError, ~r/Unknown service/, fn ->
        Config.get_service!(:nonexistent_service_that_does_not_exist)
      end
    end

    test "raises error for invalid service name type" do
      assert_raise ArgumentError, ~r/Service name must be atom or string/, fn ->
        Config.get_service!(123)
      end
    end

    test "retrieves default service when nil is passed" do
      # Default service in test config is :test_disk
      service = Config.get_service!(nil)
      assert %StorageEx.Services.DiskService{} = service
    end
  end

  describe "public API functions" do
    test "default_service/0 returns configured default" do
      # From config/test.exs: service: :test_disk
      assert Config.default_service() == :test_disk
    end

    test "services/0 returns configured services map" do
      services = Config.services()

      assert is_map(services)
      assert Map.has_key?(services, :test_disk)
      assert Map.has_key?(services, :alternative_disk)
      assert Map.has_key?(services, :streaming_test)
    end

    test "analyzers/0 returns list of analyzers" do
      analyzers = Config.analyzers()

      assert is_list(analyzers)
      assert StorageEx.Analyzers.ImageAnalyzer in analyzers
    end

    test "previewers/0 returns list of previewers" do
      previewers = Config.previewers()

      assert is_list(previewers)
      assert StorageEx.Previewers.VideoPreviewer in previewers
    end
  end
end
