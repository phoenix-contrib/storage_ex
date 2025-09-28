defmodule StorageEx.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    original_env = Application.get_all_env(:storage_ex)

    on_exit(fn ->
      Application.put_all_env(storage_ex: original_env)
      StorageEx.Config.reload!()
    end)

    :ok
  end

  describe "default configuration" do
    test "creates a filesystem disk service when no configuration is provided" do
      # Clear all storage_ex configuration
      Application.delete_env(:storage_ex, :service)
      Application.delete_env(:storage_ex, :services)
      StorageEx.Config.reload!()

      # Get the services
      services = StorageEx.Config.services()

      # Should have a filesystem_disk service
      assert Map.has_key?(services, :filesystem_disk)

      # The service should be a DiskService
      service = services[:filesystem_disk]
      assert %StorageEx.Services.DiskService{} = service

      # It should have the default root path
      assert service.root == "priv/storage"
    end

    test "default service name is :local when not configured" do
      # Clear all storage_ex configuration
      Application.delete_env(:storage_ex, :service)
      Application.delete_env(:storage_ex, :services)
      StorageEx.Config.reload!()

      assert StorageEx.Config.default_service() == :local
    end

    test "does not create default filesystem service when services are configured" do
      Application.put_env(:storage_ex, :services, %{
        my_disk: %{
          service: StorageEx.Services.DiskService,
          configuration: %{root: "/tmp/custom"}
        }
      })

      StorageEx.Config.reload!()

      services = StorageEx.Config.services()

      # Should only have the configured service, not the default
      assert Map.keys(services) == [:my_disk]
      refute Map.has_key?(services, :filesystem_disk)
    end

    test "uses configured default service name" do
      Application.put_env(:storage_ex, :service, :my_custom_service)

      Application.put_env(:storage_ex, :services, %{
        my_custom_service: %{
          service: StorageEx.Services.DiskService,
          configuration: %{root: "/tmp/custom"}
        }
      })

      StorageEx.Config.reload!()

      assert StorageEx.Config.default_service() == :my_custom_service
    end
  end

  describe "get_service!/1" do
    test "retrieves default service when nil is passed" do
      # Configure a service that matches the default service name
      Application.put_env(:storage_ex, :service, :filesystem_disk)

      Application.put_env(:storage_ex, :services, %{
        filesystem_disk: %{
          service: StorageEx.Services.DiskService,
          configuration: %{root: "/tmp/test"}
        }
      })

      StorageEx.Config.reload!()

      # Getting service with nil should return the default service
      service = StorageEx.Config.get_service!(nil)
      assert %StorageEx.Services.DiskService{} = service
    end

    test "retrieves service by atom name" do
      Application.put_env(:storage_ex, :services, %{
        my_disk: %{
          service: StorageEx.Services.DiskService,
          configuration: %{root: "/tmp/test"}
        }
      })

      StorageEx.Config.reload!()

      service = StorageEx.Config.get_service!(:my_disk)
      assert %StorageEx.Services.DiskService{root: "/tmp/test"} = service
    end

    test "retrieves service by string name" do
      Application.put_env(:storage_ex, :services, %{
        my_disk: %{
          service: StorageEx.Services.DiskService,
          configuration: %{root: "/tmp/test"}
        }
      })

      StorageEx.Config.reload!()

      service = StorageEx.Config.get_service!("my_disk")
      assert %StorageEx.Services.DiskService{root: "/tmp/test"} = service
    end

    test "raises error for unknown service" do
      Application.put_env(:storage_ex, :services, %{})
      StorageEx.Config.reload!()

      assert_raise ArgumentError, ~r/Unknown service/, fn ->
        StorageEx.Config.get_service!(:nonexistent)
      end
    end

    test "raises error for invalid service name type" do
      assert_raise ArgumentError, ~r/Service name must be atom or string/, fn ->
        StorageEx.Config.get_service!(123)
      end
    end
  end

  describe "endpoint/0" do
    test "returns nil when no endpoint is configured" do
      Application.delete_env(:storage_ex, :endpoint)
      StorageEx.Config.reload!()

      assert StorageEx.Config.endpoint() == nil
    end

    test "returns configured endpoint" do
      Application.put_env(:storage_ex, :endpoint, MyAppWeb.Endpoint)
      StorageEx.Config.reload!()

      assert StorageEx.Config.endpoint() == MyAppWeb.Endpoint
    end
  end
end
