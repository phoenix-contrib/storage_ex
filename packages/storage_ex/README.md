# StorageEx

ActiveStorage-like file storage for Phoenix applications. Simple, powerful file uploads with support for local disk, S3, and more.

## Features

- 🗄️ **Multiple backends**: Local disk, Amazon S3, and extensible adapter system
- 🔒 **Signed URLs**: Secure, expiring URLs for downloads and direct uploads
- 📤 **Direct uploads**: Client-side uploads without going through your server
- 🔄 **Streaming**: Memory-efficient streaming for large files
- ✅ **Checksum validation**: Integrity checking with MD5
- 🎯 **Phoenix integration**: Drop-in routes and controllers

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_contrib_storage_ex, "~> 0.1"}
  ]
end
```

## Quick Start

### 1. Configure

In `config/runtime.exs`:

```elixir
config :storage_ex,
  service: :local,
  services: %{
    local: %{
      service: StorageEx.Services.DiskService,
      configuration: %{root: "priv/storage"}
    }
  },
  token_salt: "change-this-in-production"
```

### 2. Add Routes

In `lib/my_app_web/router.ex`:

```elixir
use StorageEx.Router

scope "/storage_ex" do
  pipe_through :browser
  storage_ex_routes()
end
```

### 3. Upload Files

```elixir
# Upload a file
{:ok, key} = StorageEx.upload("avatar.png", file_data)

# Generate signed download URL
url = StorageEx.url(key,
  endpoint: MyAppWeb.Endpoint,
  filename: "avatar.png"
)

# Download a file
{:ok, data} = StorageEx.download(key)

# Check if file exists
StorageEx.exists?(key)  # => true

# Delete a file
:ok = StorageEx.delete(key)
{:ok, content} = Storage.Services.Local.get(local_service, "hello.txt")
```

## Configuration

All configuration should be in `runtime.exs` to work properly with releases:

```elixir
config :my_app, MyApp.Storage,
  repo: MyApp.Repo,  # Your Ecto repo (required for database operations)
  services: %{
    local: %{
      service: Storage.Services.Local,
      configuration: %{root: "priv/storage"}
    }
  },
  service: :local  # Default service to use
```

### Automatic Local Service

If you don't configure any services, a local service will be automatically added:

```elixir
local: %{
  service: Storage.Services.Local,
  configuration: %{root: "priv/storage"}
}
```

## Services

### Built-in Services

- **Local Storage** (`Storage.Services.Local`) - Stores files on the local filesystem

### External Service Providers

Install additional packages for cloud storage:

- **S3-Compatible** - `{:phoenix_contrib_storage_s3, "~> 0.1"}` (AWS S3, Cloudflare R2, DigitalOcean Spaces, MinIO, etc.)
- **Azure Blob** - `{:phoenix_contrib_storage_azure, "~> 0.1"}` (coming soon)
- **Google Cloud Storage** - `{:phoenix_contrib_storage_gcs, "~> 0.1"}` (coming soon)

## Database Schema

This library requires database tables to store blob metadata and attachments. Generate the migration:

```bash
mix storage.migrate
```

This creates:

- `storage_blobs` - File metadata (key, filename, content_type, etc.)
- `storage_attachments` - Polymorphic associations between your models and blobs
- `storage_variants` - Processed versions of blobs (optional)

## Facade API

Your storage facade (e.g., `MyApp.Storage`) provides:

- `repo/0` - Returns your configured Ecto repo
- `services/0` - Returns a map of initialized service structs
- `default_service/0` - Returns the default service name (atom)
- `get_service!(name)` - Fetches a specific service by name
- `reload_config/0` - Reloads configuration (useful in tests)

## Local Service API

The `Storage.Services.Local` service provides:

- `put(service, key, binary)` - Store a file
- `get(service, key)` - Read a file
- `delete(service, key)` - Delete a file
- `exists?(service, key)` - Check if file exists
- `url(service, key)` - Get file path/URL

## Architecture

This library follows the facade pattern inspired by Oban:

1. **Facade Module** - Your app defines `MyApp.Storage` using the `Storage` macro
2. **Service Behavior** - All storage providers implement `Storage.Service`
3. **Caching** - Configuration is cached in `:persistent_term` for fast access
4. **Explicit Config** - Service modules are explicitly configured (no magic atom mapping)

## Development

The library is organized as an umbrella project:

- `apps/core` - This package (`phoenix_contrib_storage`)
- `apps/cloudflare_r2` - CloudflareR2 provider
- More providers coming soon...

## License

MIT
