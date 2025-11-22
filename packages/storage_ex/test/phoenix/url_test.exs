defmodule URLTest do
  use ExUnit.Case, async: true

  alias StorageEx.Phoenix.URL

  # Mock endpoint for testing
  defmodule TestEndpoint do
    def config(:url), do: [scheme: "http", host: "localhost", port: 4000]
    def config(:secret_key_base), do: String.duplicate("abcdef0123456789", 8)
  end

  describe "signed_url/2" do
    test "generates signed URL with endpoint option" do
      url =
        URL.signed_url("test.txt",
          endpoint: TestEndpoint,
          filename: "test.txt",
          disposition: :inline
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      assert url =~ "/test.txt"
    end

    test "includes disposition in token" do
      url =
        URL.signed_url("file.pdf",
          endpoint: TestEndpoint,
          filename: "document.pdf",
          disposition: :attachment
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      assert url =~ "/document.pdf"
    end

    test "supports custom service name" do
      url =
        URL.signed_url("image.png",
          endpoint: TestEndpoint,
          service_name: :custom_service,
          filename: "image.png"
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "supports custom expires_in" do
      url =
        URL.signed_url("file.txt",
          endpoint: TestEndpoint,
          filename: "file.txt",
          expires_in: 600
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "includes content type when provided" do
      url =
        URL.signed_url("file.txt",
          endpoint: TestEndpoint,
          filename: "file.txt",
          content_type: "text/plain"
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "raises error when no endpoint provided" do
      assert_raise ArgumentError, ~r/endpoint is required/, fn ->
        URL.signed_url("test.txt", filename: "test.txt")
      end
    end
  end

  describe "signed_upload_url/2" do
    test "generates signed upload URL with endpoint option" do
      {:ok, url} =
        URL.signed_upload_url("upload.txt",
          endpoint: TestEndpoint,
          content_type: "text/plain",
          content_length: 100
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
      # Token-based, no filename in path
      refute url =~ "upload.txt"
    end

    test "includes checksum in token" do
      checksum = :crypto.hash(:md5, "data") |> Base.encode64()

      {:ok, url} =
        URL.signed_upload_url("file.bin",
          endpoint: TestEndpoint,
          content_type: "application/octet-stream",
          content_length: 1024,
          checksum: checksum
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "supports custom service name and expires_in" do
      {:ok, url} =
        URL.signed_upload_url("file.bin",
          endpoint: TestEndpoint,
          service_name: :my_service,
          content_type: "application/octet-stream",
          content_length: 1024,
          expires_in: 600
        )

      assert url =~ "http://localhost:4000/storage_ex/disk/"
    end

    test "raises error when no endpoint provided" do
      assert_raise ArgumentError, ~r/endpoint is required/, fn ->
        URL.signed_upload_url("upload.txt",
          content_type: "text/plain",
          content_length: 100
        )
      end
    end
  end
end
