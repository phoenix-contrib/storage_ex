# Phoenix Integration Guide

This guide shows how to integrate StorageEx with Phoenix for serving files from disk storage.

## Installation

Add to your dependencies:

```elixir
def deps do
  [
    {:phoenix_contrib_storage_ex, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure your storage service in `config/runtime.exs`:

```elixir
config :storage_ex,
  service: :local,
  services: %{
    local: %{
      service: StorageEx.Services.DiskService,
      configuration: %{
        root: Path.join(["priv", "storage"])
      }
    }
  },
  # Token salt for signed URLs (change this!)
  token_salt: "your-secret-salt-here"
```

## Router Setup

Add StorageEx routes to your router:

```elixir
# In lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use StorageEx.Router

  # ... your other routes ...

  scope "/storage_ex" do
    pipe_through :browser  # or :api
    storage_ex_routes()
  end
end
```

This mounts two routes:
- `GET /storage_ex/disk/:encoded_key/*filename` - Download files
- `PUT /storage_ex/disk/:encoded_token` - Upload files (direct upload)

## Basic Usage

### Upload a File

```elixir
# Upload a file
key = "avatars/#{user_id}/avatar.png"
{:ok, data} = File.read("path/to/avatar.png")
{:ok, ^key} = StorageEx.upload(key, data)
```

### Generate Download URL

```elixir
# Generate a signed URL for downloading
url = StorageEx.url(key,
  endpoint: MyAppWeb.Endpoint,
  filename: "avatar.png",
  disposition: :attachment,
  expires_in: 3600  # 1 hour
)

# Use in template
<a href={url}>Download Avatar</a>
```

### Generate Direct Upload URL

```elixir
# For client-side direct uploads
{:ok, upload_url} = StorageEx.url_for_direct_upload(key,
  endpoint: MyAppWeb.Endpoint,
  content_type: "image/png",
  content_length: 1024,
  checksum: checksum,
  expires_in: 300  # 5 minutes
)

# Client can PUT to this URL with appropriate headers
```

## Example: File Upload Controller

```elixir
defmodule MyAppWeb.UploadController do
  use MyAppWeb, :controller

  def create(conn, %{"file" => upload}) do
    # Generate unique key
    key = "uploads/#{Ecto.UUID.generate()}/#{upload.filename}"
    
    # Read file data
    {:ok, data} = File.read(upload.path)
    
    # Upload to storage
    case StorageEx.upload(key, data) do
      {:ok, ^key} ->
        # Generate download URL
        url = StorageEx.url(key,
          endpoint: MyAppWeb.Endpoint,
          filename: upload.filename,
          disposition: :inline
        )
        
        json(conn, %{url: url, key: key})
        
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
  
  def show(conn, %{"key" => key}) do
    case StorageEx.download(key) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> send_resp(200, data)
        
      {:error, :file_not_found} ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
```

## Example: Direct Upload (Client-Side)

### 1. Get Upload URL from Server

```elixir
defmodule MyAppWeb.DirectUploadController do
  use MyAppWeb, :controller

  def create(conn, %{"filename" => filename, "content_type" => content_type, "size" => size}) do
    key = "uploads/#{Ecto.UUID.generate()}/#{filename}"
    
    {:ok, upload_url} = StorageEx.url_for_direct_upload(key,
      endpoint: MyAppWeb.Endpoint,
      content_type: content_type,
      content_length: size,
      expires_in: 300
    )
    
    headers = StorageEx.headers_for_direct_upload(key,
      content_type: content_type
    )
    
    json(conn, %{
      upload_url: upload_url,
      headers: headers,
      key: key
    })
  end
end
```

### 2. Upload from JavaScript

```javascript
// Get upload URL
const response = await fetch('/api/direct_uploads', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    filename: file.name,
    content_type: file.type,
    size: file.size
  })
});

const { upload_url, headers, key } = await response.json();

// Upload file directly
await fetch(upload_url, {
  method: 'PUT',
  headers: headers,
  body: file
});

// File is now uploaded with key
console.log('Uploaded:', key);
```

## Streaming Large Files

For large files, use streaming download:

```elixir
{:ok, stream} = StorageEx.download_stream(key)

# Write to local file
stream
|> Stream.into(File.stream!("output.mp4"))
|> Stream.run()

# Or send as HTTP response
conn
|> put_resp_content_type("video/mp4")
|> send_chunked(200)
|> stream_response(stream)

defp stream_response(conn, stream) do
  Enum.reduce_while(stream, conn, fn chunk, conn ->
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end)
end
```

## Security Considerations

1. **Token Salt**: Change the default token salt in production:
   ```elixir
   config :storage_ex, token_salt: System.fetch_env!("STORAGE_EX_TOKEN_SALT")
   ```

2. **Expiration**: Use short expiration times for sensitive files:
   ```elixir
   StorageEx.url(key, endpoint: MyAppWeb.Endpoint, expires_in: 60)  # 1 minute
   ```

3. **Content Type**: Always specify content type for uploads to prevent MIME confusion:
   ```elixir
   StorageEx.url_for_direct_upload(key,
     endpoint: MyAppWeb.Endpoint,
     content_type: "image/png"
   )
   ```

4. **Checksums**: Use checksums for integrity verification:
   ```elixir
   checksum = :crypto.hash(:md5, data) |> Base.encode64()
   StorageEx.upload(key, data, checksum: checksum)
   ```

## Testing

In tests, you may want to use the filesystem path directly:

```elixir
# In test environment, URLs return paths without signing
config :storage_ex, token_salt: "test-salt"

# In tests
test "file upload" do
  {:ok, key} = StorageEx.upload("test.txt", "content")
  assert StorageEx.exists?(key)
end
```

## Comparison with Rails ActiveStorage

If you're migrating from Rails:

| Rails | StorageEx |
|-------|-----------|
| `rails_blob_path(@blob)` | `StorageEx.url(key, endpoint: Endpoint)` |
| `rails_disk_service_url(token)` | Generated automatically |
| `ActiveStorage.verifier` | `Phoenix.Token` |
| `/rails/active_storage/disk/...` | `/storage_ex/disk/...` |
| `ActiveStorage::DiskController` | `StorageEx.DiskController` |

Both use signed tokens for security and support direct uploads.
