defmodule StorageEx.Services.DiskService do
  @moduledoc """
  Local storage service.

  Files are stored directly on disk under the configured root path.
  Files are organized in subdirectories based on the first 4 characters
  of the key (e.g., key "abcd1234" -> "ab/cd/abcd1234") for better
  filesystem performance with large numbers of files.

  ## Configuration

  - `:root` - Root directory for file storage (default: "priv/storage")
  - `:public` - Whether files are publicly accessible (default: false)
  - `:chunk_size` - Chunk size for streaming downloads in bytes (default: 5MB)

  ## Examples

      # Standard configuration with default 5MB chunks
      %{
        service: StorageEx.Services.DiskService,
        configuration: %{
          root: "priv/storage"
        }
      }

      # Custom chunk size for testing (50KB chunks)
      %{
        service: StorageEx.Services.DiskService,
        configuration: %{
          root: "test/storage",
          chunk_size: 50 * 1024
        }
      }

  Mirrors Rails' ActiveStorage::Service::DiskService.
  """

  @behaviour StorageEx.Service

  defstruct [:root, :chunk_size, public: false]

  alias __MODULE__
  alias StorageEx.Phoenix.URL

  @type t :: %__MODULE__{root: String.t(), chunk_size: pos_integer(), public: boolean()}

  # Default 5MB chunk size for streaming downloads (Rails-compatible)
  @default_chunk_size 5 * 1024 * 1024

  # -- Initialization ---------------------------------------------------------

  @spec new(map()) :: t() | {:error, String.t()}
  def new(config) when is_map(config) do
    root = Map.get(config, :root, default_root())
    public = Map.get(config, :public, false)
    chunk_size = Map.get(config, :chunk_size, @default_chunk_size)

    case File.mkdir_p(root) do
      :ok ->
        %__MODULE__{root: root, public: public, chunk_size: chunk_size}

      {:error, reason} ->
        {:error, "Failed to create storage directory #{root}: #{inspect(reason)}"}
    end
  end

  defp default_root, do: Path.expand("priv/storage")

  # -- Behaviour Callbacks ----------------------------------------------------

  @impl true
  def upload(%DiskService{} = service, key, binary, opts) when is_binary(binary) do
    path = make_path_for(service, key)

    with :ok <- File.write(path, binary),
         :ok <- ensure_integrity_of(service, key, opts[:checksum]) do
      {:ok, key}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_metadata(_service, _key, _metadata) do
    # Local disk doesn’t support metadata
    :ok
  end

  @impl true
  def download(%DiskService{} = service, key) do
    case File.read(path_for(service, key)) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def download_chunk(%DiskService{} = service, key, range) do
    path = path_for(service, key)

    case File.open(path, [:binary, :read]) do
      {:ok, io} ->
        try do
          :file.position(io, {:bof, range.first})
          size = range.last - range.first + 1
          {:ok, IO.binread(io, size)}
        after
          File.close(io)
        end

      {:error, :enoent} ->
        {:error, :file_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download_stream(%DiskService{} = service, key) do
    path = path_for(service, key)

    if File.exists?(path) do
      stream = create_file_stream(path, service.chunk_size)
      {:ok, stream}
    else
      {:error, :file_not_found}
    end
  end

  @impl true
  def compose(%DiskService{} = service, source_keys, destination_key, _opts) do
    dest_path = make_path_for(service, destination_key)

    case File.open(dest_path, [:binary, :write]) do
      {:ok, io} ->
        try do
          result =
            Enum.reduce_while(source_keys, :ok, fn key, _acc ->
              src_path = path_for(service, key)

              case File.read(src_path) do
                {:ok, data} ->
                  IO.binwrite(io, data)
                  {:cont, :ok}

                {:error, reason} ->
                  {:halt, {:error, reason}}
              end
            end)

          File.close(io)
          result
        rescue
          e ->
            File.close(io)
            {:error, e}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(%DiskService{} = service, key) do
    path = path_for(service, key)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_prefixed(%DiskService{} = service, prefix) do
    # Use recursive wildcard to find all files under root
    pattern = Path.join(service.root, "**/*")

    pattern
    |> Path.wildcard()
    |> Enum.filter(&file_matches_prefix?(&1, service.root, prefix))
    |> Enum.each(&File.rm/1)

    :ok
  end

  @impl true
  def exists?(%DiskService{} = service, key) do
    File.exists?(path_for(service, key))
  end

  # --- URL helpers -----------------------------------------------------------

  @impl true
  def url(%DiskService{} = _service, key, opts) do
    # Generate signed URL if endpoint is provided, otherwise return path
    case Keyword.get(opts, :endpoint) do
      nil ->
        # Fallback: return filesystem path with filename
        filename = Keyword.get(opts, :filename, key)
        "/storage_ex/disk/#{key}/#{filename}"

      endpoint ->
        URL.signed_url(key, opts ++ [endpoint: endpoint])
    end
  end

  @impl true
  def url_for_direct_upload(%DiskService{} = _service, key, opts) do
    case Keyword.get(opts, :endpoint) do
      nil ->
        # Fallback for backward compatibility
        {:ok, "/storage_ex/disk/#{key}"}

      endpoint ->
        URL.signed_upload_url(key, opts ++ [endpoint: endpoint])
    end
  end

  @impl true
  def headers_for_direct_upload(_service, _key, opts) do
    case Keyword.get(opts, :content_type) do
      nil -> %{}
      content_type -> %{"Content-Type" => content_type}
    end
  end

  # --- Private helpers -------------------------------------------------------

  @doc false
  def path_for(%DiskService{root: root}, key) do
    Path.join([root, folder_for(key), key])
  end

  defp make_path_for(service, key) do
    path = path_for(service, key)
    File.mkdir_p!(Path.dirname(path))
    path
  end

  # Organize files into subdirectories based on first 4 chars of key
  # This improves filesystem performance with large numbers of files
  # e.g., "abcd1234" -> "ab/cd"
  defp folder_for(key) when byte_size(key) >= 4 do
    <<a::binary-size(2), b::binary-size(2), _::binary>> = key
    Path.join(a, b)
  end

  defp folder_for(_key), do: ""

  defp ensure_integrity_of(_service, _key, nil), do: :ok

  defp ensure_integrity_of(service, key, expected_checksum) do
    path = path_for(service, key)

    case File.read(path) do
      {:ok, data} ->
        actual_checksum = :crypto.hash(:md5, data) |> Base.encode64()

        if actual_checksum == expected_checksum do
          :ok
        else
          File.rm(path)
          {:error, :integrity_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_file_stream(path, chunk_size) do
    Stream.resource(
      fn -> File.open!(path, [:binary, :read]) end,
      fn io ->
        case IO.binread(io, chunk_size) do
          data when is_binary(data) -> {[data], io}
          :eof -> {:halt, io}
        end
      end,
      fn io -> File.close(io) end
    )
  end

  defp file_matches_prefix?(path, root, prefix) do
    # Only process regular files, not directories
    if File.regular?(path) do
      # Extract the key from the path by removing root and folder structure
      relative = Path.relative_to(path, root)
      # The key is everything after the first two directory levels (e.g., "ab/cd/key" -> "key")
      # But the key itself might contain slashes, so we need to reconstruct it
      case Path.split(relative) do
        [_a, _b | rest] when rest != [] ->
          # Reconstruct the key from the remaining path components
          key = Path.join(rest)
          String.starts_with?(key, prefix)

        _ ->
          false
      end
    else
      false
    end
  end
end
