defmodule StorageEx.Phoenix.DiskControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  use StorageEx.Support.DiskCleanup

  # Mock endpoint for token signing
  defmodule TestEndpoint do
    def config(:secret_key_base), do: String.duplicate("abcdef0123456789", 8)
    def config(:url), do: [scheme: "http", host: "localhost", port: 4000]
  end

  setup do
    # Set up config
    Application.put_env(:storage_ex, :token_salt, "test_salt")
    Application.put_env(:storage_ex, :endpoint, TestEndpoint)
    StorageEx.Config.reload!()

    :ok
  end

  defp generate_key, do: "test_#{System.unique_integer([:positive])}"

  describe "show/2 - file download" do
    test "downloads file with valid token" do
      # Upload a test file
      key = generate_key()
      data = "test content"
      {:ok, ^key} = StorageEx.upload(key, data)

      # Generate signed URL
      url =
        StorageEx.Phoenix.URL.signed_url(key,
          endpoint: TestEndpoint,
          filename: "test.txt",
          content_type: "text/plain",
          disposition: :attachment
        )

      # Extract encoded_key from URL
      [encoded_key, _filename] = String.split(url, "/disk/") |> List.last() |> String.split("/")

      # Make request
      conn =
        conn(:get, "/storage_ex/disk/#{encoded_key}/test.txt")
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.show(conn, %{
          "encoded_key" => encoded_key,
          "filename" => "test.txt"
        })

      assert conn.status == 200
      assert conn.resp_body == data
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "content-disposition") == ["attachment; filename=\"test.txt\""]
    end

    test "returns 404 for invalid token" do
      conn =
        conn(:get, "/storage_ex/disk/invalid_token/test.txt")
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.show(conn, %{
          "encoded_key" => "invalid_token",
          "filename" => "test.txt"
        })

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end

    test "returns 404 for non-existent file" do
      # Generate valid token for non-existent file
      key = "nonexistent_#{System.unique_integer([:positive])}"

      url =
        StorageEx.Phoenix.URL.signed_url(key,
          endpoint: TestEndpoint,
          filename: "test.txt"
        )

      [encoded_key, _filename] = String.split(url, "/disk/") |> List.last() |> String.split("/")

      conn =
        conn(:get, "/storage_ex/disk/#{encoded_key}/test.txt")
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.show(conn, %{
          "encoded_key" => encoded_key,
          "filename" => "test.txt"
        })

      assert conn.status == 404
    end

    test "supports inline disposition" do
      key = generate_key()
      data = "inline content"
      {:ok, ^key} = StorageEx.upload(key, data)

      url =
        StorageEx.Phoenix.URL.signed_url(key,
          endpoint: TestEndpoint,
          filename: "inline.txt",
          disposition: :inline
        )

      [encoded_key, _filename] = String.split(url, "/disk/") |> List.last() |> String.split("/")

      conn =
        conn(:get, "/storage_ex/disk/#{encoded_key}/inline.txt")
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.show(conn, %{
          "encoded_key" => encoded_key,
          "filename" => "inline.txt"
        })

      assert conn.status == 200
      assert get_resp_header(conn, "content-disposition") == ["inline; filename=\"inline.txt\""]
    end
  end

  describe "update/2 - file upload" do
    test "uploads file with valid token and matching content" do
      key = generate_key()
      data = "upload content"
      checksum = :crypto.hash(:md5, data) |> Base.encode64()

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url(key,
          endpoint: TestEndpoint,
          content_type: "text/plain",
          content_length: byte_size(data),
          checksum: checksum
        )

      # Extract token from URL
      encoded_token = String.split(url, "/disk/") |> List.last()

      conn =
        conn(:put, "/storage_ex/disk/#{encoded_token}", data)
        |> put_req_header("content-type", "text/plain")
        |> put_req_header("content-length", to_string(byte_size(data)))
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.update(conn, %{
          "encoded_token" => encoded_token
        })

      assert conn.status == 204
      assert StorageEx.exists?(key)
      assert {:ok, ^data} = StorageEx.download(key)
    end

    test "returns 422 for content type mismatch" do
      key = generate_key()
      data = "content"

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url(key,
          endpoint: TestEndpoint,
          content_type: "text/plain",
          content_length: byte_size(data)
        )

      encoded_token = String.split(url, "/disk/") |> List.last()

      conn =
        conn(:put, "/storage_ex/disk/#{encoded_token}", data)
        # Wrong type!
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", to_string(byte_size(data)))
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.update(conn, %{
          "encoded_token" => encoded_token
        })

      assert conn.status == 422
      refute StorageEx.exists?(key)
    end

    test "returns 422 for content length mismatch" do
      key = generate_key()
      data = "content"

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url(key,
          endpoint: TestEndpoint,
          content_type: "text/plain",
          # Wrong length!
          content_length: 999
        )

      encoded_token = String.split(url, "/disk/") |> List.last()

      conn =
        conn(:put, "/storage_ex/disk/#{encoded_token}", data)
        |> put_req_header("content-type", "text/plain")
        |> put_req_header("content-length", to_string(byte_size(data)))
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.update(conn, %{
          "encoded_token" => encoded_token
        })

      assert conn.status == 422
      refute StorageEx.exists?(key)
    end

    test "returns 422 for invalid checksum" do
      key = generate_key()
      data = "content"
      wrong_checksum = :crypto.hash(:md5, "wrong data") |> Base.encode64()

      {:ok, url} =
        StorageEx.Phoenix.URL.signed_upload_url(key,
          endpoint: TestEndpoint,
          content_type: "text/plain",
          content_length: byte_size(data),
          checksum: wrong_checksum
        )

      encoded_token = String.split(url, "/disk/") |> List.last()

      conn =
        conn(:put, "/storage_ex/disk/#{encoded_token}", data)
        |> put_req_header("content-type", "text/plain")
        |> put_req_header("content-length", to_string(byte_size(data)))
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.update(conn, %{
          "encoded_token" => encoded_token
        })

      assert conn.status == 422
      assert conn.resp_body == "Integrity check failed"
      refute StorageEx.exists?(key)
    end

    test "returns 404 for invalid token" do
      conn =
        conn(:put, "/storage_ex/disk/invalid_token", "data")
        |> put_req_header("content-type", "text/plain")
        |> put_private(:phoenix_endpoint, TestEndpoint)

      conn =
        StorageEx.Phoenix.DiskController.update(conn, %{
          "encoded_token" => "invalid_token"
        })

      assert conn.status == 404
    end
  end
end
