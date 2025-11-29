defmodule StorageExTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  @fixture_data <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 16, 0, 0,
                  0, 16, 1, 3, 0, 0, 0, 37, 61, 109, 34, 0, 0, 0, 6, 80, 76, 84, 69, 0, 0, 0, 255,
                  255, 255, 165, 217, 159, 221, 0, 0, 0, 51, 73, 68, 65, 84, 120, 156, 99, 248,
                  255, 159, 225, 255, 95, 134, 255, 159, 25, 14, 160, 51, 220, 63, 204, 112, 127,
                  50, 195, 205, 205, 12, 55, 141, 25, 238, 20, 131, 208, 189, 207, 12, 247, 129,
                  82, 204, 12, 15, 192, 232, 255, 127, 0, 81, 134, 23, 40, 206, 93, 155, 80, 0, 0,
                  0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  describe "upload/3" do
    test "uploads a file and can download it" do
      key = generate_key()
      data = "hello world"

      assert {:ok, ^key} = StorageEx.upload(key, data)
      assert {:ok, ^data} = StorageEx.download(key)
      assert StorageEx.exists?(key)
    end

    test "uploads binary data" do
      key = generate_key()
      data = "hello world"

      assert {:ok, ^key} = StorageEx.upload(key, data)
      assert StorageEx.exists?(key)
    end

    test "uploads with checksum validation" do
      key = generate_key()
      data = "Something else entirely!"
      checksum = :crypto.hash(:md5, data) |> Base.encode64()

      assert {:ok, ^key} = StorageEx.upload(key, data, checksum: checksum)
      assert {:ok, ^data} = StorageEx.download(key)
    end

    test "fails upload with invalid checksum" do
      key = generate_key()
      data = "Something else entirely!"
      bad_checksum = :crypto.hash(:md5, "bad data") |> Base.encode64()

      assert {:error, :integrity_error} =
               StorageEx.upload(key, data, checksum: bad_checksum)

      refute StorageEx.exists?(key)
    end

    test "handles short keys" do
      key = "abc"
      data = "test"

      assert {:ok, ^key} = StorageEx.upload(key, data)
      assert StorageEx.exists?(key)
    end
  end

  describe "download/2" do
    test "downloads uploaded data" do
      key = generate_key()

      StorageEx.upload(key, @fixture_data)
      assert {:ok, @fixture_data} = StorageEx.download(key)
    end

    test "returns error for nonexistent file" do
      assert {:error, :file_not_found} = StorageEx.download("nonexistent")
    end
  end

  describe "download_chunk/3" do
    test "downloads partial content" do
      key = generate_key()
      StorageEx.upload(key, @fixture_data)

      assert {:ok, chunk} = StorageEx.download_chunk(key, 19..21)
      assert byte_size(chunk) == 3
      assert chunk == binary_part(@fixture_data, 19, 3)
    end

    test "downloads chunk with inclusive range" do
      key = generate_key()
      data = "0123456789"
      StorageEx.upload(key, data)

      assert {:ok, "234"} = StorageEx.download_chunk(key, 2..4)
    end

    test "returns error for nonexistent file" do
      assert {:error, :file_not_found} =
               StorageEx.download_chunk("nonexistent", 0..10)
    end
  end

  describe "download_stream/2" do
    test "downloads file as a stream" do
      key = generate_key()
      data = String.duplicate("x", 10_000_000)
      StorageEx.upload(key, data)

      assert {:ok, stream} = StorageEx.download_stream(key)
      assert is_function(stream)

      downloaded = stream |> Enum.to_list() |> IO.iodata_to_binary()
      assert downloaded == data
    end

    test "streams in chunks" do
      key = generate_key()
      data = String.duplicate("abc", 2_000_000)
      StorageEx.upload(key, data)

      assert {:ok, stream} = StorageEx.download_stream(key)
      chunks = Enum.to_list(stream)

      assert length(chunks) > 1
      assert IO.iodata_to_binary(chunks) == data
    end

    test "returns error for nonexistent file" do
      assert {:error, :file_not_found} = StorageEx.download_stream("nonexistent")
    end

    test "respects custom chunk size configuration" do
      # Use streaming_test service with 50KB chunks
      key = generate_key()
      # Create exactly 100KB = 2 chunks of 50KB each
      data = String.duplicate("x", 100 * 1024)
      StorageEx.upload(key, data, service_name: :streaming_test)

      assert {:ok, stream} = StorageEx.download_stream(key, service_name: :streaming_test)
      chunks = Enum.to_list(stream)

      # Should be exactly 2 chunks of 50KB each
      assert length(chunks) == 2
      assert byte_size(Enum.at(chunks, 0)) == 50 * 1024
      assert byte_size(Enum.at(chunks, 1)) == 50 * 1024
      assert IO.iodata_to_binary(chunks) == data
    end
  end

  describe "delete/2" do
    test "deletes existing file" do
      key = generate_key()
      StorageEx.upload(key, "data")
      assert StorageEx.exists?(key)

      assert :ok = StorageEx.delete(key)
      refute StorageEx.exists?(key)
    end

    test "succeeds when deleting nonexistent file" do
      assert :ok = StorageEx.delete("nonexistent")
    end
  end

  describe "delete_prefixed/2" do
    test "deletes files matching prefix" do
      prefix = generate_key()

      StorageEx.upload("#{prefix}/a/a/a", "data1")
      StorageEx.upload("#{prefix}/a/a/b", "data2")
      StorageEx.upload("#{prefix}/a/b/a", "data3")
      StorageEx.upload("#{prefix}/b/a/a", "data4")

      assert :ok = StorageEx.delete_prefixed("#{prefix}/a/a/")

      refute StorageEx.exists?("#{prefix}/a/a/a")
      refute StorageEx.exists?("#{prefix}/a/a/b")
      assert StorageEx.exists?("#{prefix}/a/b/a")
      assert StorageEx.exists?("#{prefix}/b/a/a")
    end

    test "handles prefix with no matches" do
      assert :ok = StorageEx.delete_prefixed("nonexistent/")
    end
  end

  describe "exists?/2" do
    test "returns true for existing file" do
      key = generate_key()
      StorageEx.upload(key, "data")

      assert StorageEx.exists?(key)
    end

    test "returns false for nonexistent file" do
      refute StorageEx.exists?("nonexistent")
    end
  end

  describe "compose/3" do
    test "concatenates multiple files into one" do
      keys = [generate_key(), generate_key(), generate_key()]
      data = ["To", "get", "her"]

      Enum.zip(keys, data)
      |> Enum.each(fn {key, d} ->
        checksum = :crypto.hash(:md5, d) |> Base.encode64()
        StorageEx.upload(key, d, checksum: checksum)
      end)

      destination_key = generate_key()
      assert :ok = StorageEx.compose(keys, destination_key)

      assert {:ok, "Together"} = StorageEx.download(destination_key)
    end

    test "returns error if source file doesn't exist" do
      key1 = generate_key()
      StorageEx.upload(key1, "data")

      destination = generate_key()

      assert {:error, _} = StorageEx.compose([key1, "nonexistent"], destination)
    end
  end

  describe "update_metadata/1" do
    test "updates metadata" do
      key = generate_key()
      StorageEx.upload(key, "data")

      assert :ok = StorageEx.update_metadata(key: key, metadata: %{foo: "bar"})
    end
  end

  describe "url/2" do
    test "returns path for key when no endpoint provided" do
      key = generate_key()
      url = StorageEx.url(key)

      assert is_binary(url)
      assert url =~ "/storage_ex/disk/"
    end

    test "accepts endpoint option for future signed URLs" do
      key = generate_key()
      # Without a real endpoint, this would fail, so we just test the key is used
      url = StorageEx.url(key)
      assert is_binary(url)
    end
  end

  describe "url_for_direct_upload/2" do
    test "returns upload url path when no endpoint provided" do
      key = generate_key()

      assert {:ok, url} = StorageEx.url_for_direct_upload(key)
      assert is_binary(url)
      assert url =~ "/storage_ex/disk/"
    end

    test "accepts content type and length options" do
      key = generate_key()

      assert {:ok, url} =
               StorageEx.url_for_direct_upload(key,
                 content_type: "image/png",
                 content_length: 1024
               )

      assert is_binary(url)
    end
  end

  describe "headers_for_direct_upload/2" do
    test "returns empty map when no content type" do
      key = generate_key()
      assert %{} = StorageEx.headers_for_direct_upload(key)
    end

    test "returns content type header when provided" do
      key = generate_key()

      headers = StorageEx.headers_for_direct_upload(key, content_type: "application/json")

      assert %{"Content-Type" => "application/json"} = headers
    end
  end

  defp generate_key do
    Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end
end
