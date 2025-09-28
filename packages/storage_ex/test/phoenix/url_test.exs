defmodule StorageEx.Phoenix.URLTest do
  use ExUnit.Case, async: false
  use StorageEx.Support.DiskCleanup

  # Mock endpoint for testing
  defmodule TestEndpoint do
    def config(:url), do: [scheme: "http", host: "localhost", port: 4000]
    def config(:secret_key_base), do: String.duplicate("abcdef0123456789", 8)
  end

  setup do
    original_env = Application.get_all_env(:storage_ex)

    on_exit(fn ->
      Application.put_all_env(storage_ex: original_env)
      StorageEx.Config.reload!()
    end)

    :ok
  end

  describe "signed_url/2" do
    test "generates signed URL with endpoint option" do
      url =
        StorageEx.Phoenix.URL.signed_url("test.txt",
          endpoint: TestEndpoint,
          filename: "test.txt",
          disposition: :inline
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      assert url =~ "/test.txt"
    end

    test "uses configured endpoint when not provided" do
      Application.put_env(:storage_ex, :endpoint, TestEndpoint)
      StorageEx.Config.reload!()

      url =
        StorageEx.Phoenix.URL.signed_url("test.txt",
          filename: "test.txt",
          disposition: :inline
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      assert url =~ "/test.txt"
    end

    test "endpoint option takes precedence over configured endpoint" do
      Application.put_env(:storage_ex, :endpoint, :wrong_endpoint)
      StorageEx.Config.reload!()

      url =
        StorageEx.Phoenix.URL.signed_url("test.txt",
          endpoint: TestEndpoint,
          filename: "test.txt"
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "raises error when no endpoint provided or configured" do
      Application.delete_env(:storage_ex, :endpoint)
      StorageEx.Config.reload!()

      assert_raise ArgumentError, ~r/endpoint is required/, fn ->
        StorageEx.Phoenix.URL.signed_url("test.txt", filename: "test.txt")
      end
    end

    test "includes disposition in token" do
      url =
        StorageEx.Phoenix.URL.signed_url("file.pdf",
          endpoint: TestEndpoint,
          filename: "document.pdf",
          disposition: :attachment
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      assert url =~ "/document.pdf"
    end

    test "supports custom service name" do
      url =
        StorageEx.Phoenix.URL.signed_url("image.png",
          endpoint: TestEndpoint,
          service_name: :custom_service,
          filename: "image.png"
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "supports custom expires_in" do
      url =
        StorageEx.Phoenix.URL.signed_url("file.txt",
          endpoint: TestEndpoint,
          filename: "file.txt",
          expires_in: 600
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "includes content type when provided" do
      url =
        StorageEx.Phoenix.URL.signed_url("file.txt",
          endpoint: TestEndpoint,
          filename: "file.txt",
          content_type: "text/plain"
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end
  end

  describe "signed_upload_url/2" do
    test "generates signed upload URL with endpoint option" do
      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url("upload.txt",
          endpoint: TestEndpoint,
          content_type: "text/plain",
          content_length: 100
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      # Token-based, no filename in path
      refute url =~ "upload.txt"
    end

    test "uses configured endpoint when not provided" do
      Application.put_env(:storage_ex, :endpoint, TestEndpoint)
      StorageEx.Config.reload!()

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url("upload.txt",
          content_type: "text/plain",
          content_length: 100
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "raises error when no endpoint provided or configured" do
      Application.delete_env(:storage_ex, :endpoint)
      StorageEx.Config.reload!()

      assert_raise ArgumentError, ~r/endpoint is required/, fn ->
        StorageEx.Phoenix.URL.signed_upload_url("upload.txt",
          content_type: "text/plain",
          content_length: 100
        )
      end
    end

    test "includes checksum in token" do
      checksum = :crypto.hash(:md5, "data") |> Base.encode64()

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url("file.bin",
          endpoint: TestEndpoint,
          content_type: "application/octet-stream",
          content_length: 1024,
          checksum: checksum
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "supports custom service name and expires_in" do
      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url("file.bin",
          endpoint: TestEndpoint,
          service_name: :my_service,
          content_type: "application/octet-stream",
          content_length: 1024,
          expires_in: 600
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end
  end
end
