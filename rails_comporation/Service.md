# Rails ActiveStorage vs StorageEx: DiskService Comparison

## Method Coverage

| Method | Rails | StorageEx | Status | Notes |
|--------|-------|-----------|--------|-------|
| `initialize` | ✅ | ✅ | ✅ Complete | Both support root & public options |
| `upload` | ✅ | ✅ | ✅ Complete | Checksum validation supported |
| `download` | ✅ | ✅ | ✅ Complete | Streaming via download_stream/2 |
| `download_chunk` | ✅ | ✅ | ✅ Complete | Byte range downloads |
| `delete` | ✅ | ✅ | ✅ Complete | Idempotent behavior |
| `delete_prefixed` | ✅ | ✅ | ✅ Complete | Glob pattern matching |
| `exist?` | ✅ | ✅ | ✅ Complete | Same behavior |
| `url` | ✅ | ✅ | ✅ Complete | Phoenix.Token signed URLs |
| `url_for_direct_upload` | ✅ | ✅ | ✅ Complete | Phoenix.Token signed tokens |
| `headers_for_direct_upload` | ✅ | ✅ | ✅ Complete | Returns Content-Type header |
| `compose` | ✅ | ✅ | ✅ Complete | Concatenate multiple files |
| `update_metadata` | ✅ | ✅ | ✅ Complete | No-op for disk (as in Rails) |
| `path_for` | ✅ | ✅ | ✅ Complete | 2-level folder structure |
| `DiskController` | ✅ | ✅ | ✅ Complete | Phoenix controller with signed URLs |
| `Routes` | ✅ | ✅ | ✅ Complete | Macro-based explicit mounting |

## Implementation Details

### File Organization

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| Subfolder structure | `ab/cd/` from first 4 chars | ✅ Same |
| Short key handling | No subfolders | ✅ Same |
| Auto-create directories | ✅ Yes | ✅ Yes |

### Checksum Validation

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| Algorithm | MD5 | ✅ MD5 |
| Encoding | Base64 | ✅ Base64 |
| Failure behavior | Delete file, raise error | ✅ Delete file, return error tuple |
| Optional | ✅ Yes | ✅ Yes |

### Error Handling

| Error | Rails | StorageEx |
|-------|-------|-----------|
| File not found | `ActiveStorage::FileNotFoundError` | `:file_not_found` atom |
| Integrity error | `ActiveStorage::IntegrityError` | `:integrity_error` atom |
| Delete nonexistent | Silent (rescue) | ✅ Same (returns :ok) |
| Generic errors | Raise exception | Return error tuple |

### URL Generation

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| Signed URLs | MessageVerifier with expiration | ✅ Phoenix.Token with expiration |
| Download URLs | Route to controller | ✅ DiskController with signed tokens |
| Direct upload URLs | Signed tokens | ✅ Signed tokens via Phoenix.Token |
| URL options | expires_in, disposition, filename | ✅ All supported |
| Routes | `/rails/active_storage/disk/...` | ✅ `/storage_ex/disk/...` |

### Instrumentation

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| ActiveSupport::Notifications | ✅ All operations | ✅ Via :telemetry |
| Payload includes | operation, key, service | ✅ service, operation, args |
| Events | `service_operation.active_storage` | ✅ `[:storage_ex, operation, :start/:stop/:exception]` |
| Automatic | ✅ Via instrument method | ✅ Via Dispatcher + Notifications |



## Feature Parity Summary

### ✅ Fully Implemented (100%)

- File upload with checksum validation
- Download (full content)
- Partial downloads (byte ranges)
- File deletion (single & prefixed)
- Existence checks
- File composition
- Folder organization
- Metadata operations
- Error handling
- Idempotent operations
- **Telemetry instrumentation (via :telemetry)**

### ⚠️ Optional Enhancements

- URL helper functions in views (can use Phoenix path helpers)
- Image variants processing
- Mirror service (multiple backends)

## Phoenix Integration (Implemented)

### URL Signing

StorageEx uses Phoenix.Token for signed URLs:

```elixir
# Download URL
url = StorageEx.url(key,
  endpoint: MyAppWeb.Endpoint,
  filename: "avatar.png",
  disposition: :attachment,
  expires_in: 3600
)
# => "http://localhost:4000/storage_ex/disk/SFMyNT...token.../avatar.png"

# Direct upload URL
{:ok, url} = StorageEx.url_for_direct_upload(key,
  endpoint: MyAppWeb.Endpoint,
  content_type: "image/png",
  content_length: 1024,
  checksum: checksum,
  expires_in: 300
)
# => {:ok, "http://localhost:4000/storage_ex/disk/SFMyNT...token..."}
```

### Routes

```elixir
# In router.ex
use StorageEx.Router

scope "/storage_ex" do
  pipe_through :browser
  storage_ex_routes()
end

# Generates:
# GET  /storage_ex/disk/:encoded_key/*filename - Download via DiskController.show
# PUT  /storage_ex/disk/:encoded_token - Upload via DiskController.update
```

### Controller

```elixir
defmodule StorageEx.DiskController do
  def show(conn, %{"encoded_key" => encoded_key, "filename" => filename}) do
    # Verify token, serve file with proper headers
  end
  
  def update(conn, %{"encoded_token" => encoded_token}) do
    # Verify token, validate content, save file with checksum
  end
end
```

## Telemetry Integration (✅ Implemented)

StorageEx now includes full telemetry instrumentation, equivalent to Rails' ActiveSupport::Notifications:

```elixir
# Attach a telemetry handler
:telemetry.attach_many(
  "my-storage-handler",
  [
    [:storage_ex, :upload, :stop],
    [:storage_ex, :download, :stop],
    [:storage_ex, :delete, :stop]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)

# Handler example
def handle_event([:storage_ex, operation, :stop], measurements, metadata, _config) do
  duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
  [key | _] = metadata.args  # Extract key from args
  
  Logger.info("Storage operation completed",
    operation: operation,
    key: key,
    service: metadata.service,
    duration_ms: duration_ms
  )
end
```

### Available Events

All operations emit three events:
- `[:storage_ex, :operation, :start]` - When operation begins
- `[:storage_ex, :operation, :stop]` - When operation succeeds (includes `:duration`)
- `[:storage_ex, :operation, :exception]` - When operation fails

Operations instrumented:
- `:upload`, `:download`, `:download_chunk`, `:download_stream`
- `:delete`, `:delete_prefixed`, `:exists?`
- `:compose`, `:update_metadata`
- `:url`, `:url_for_direct_upload`, `:headers_for_direct_upload`

### Metadata

All events include:
- `service` - The service module (e.g., `StorageEx.Services.Disk`)
- `operation` - The operation name
- `args` - Raw arguments passed to the operation (e.g., `[key, data, opts]`)

### Rails Comparison

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| Event naming | `service_upload.active_storage` | `[:storage_ex, :upload, :stop]` |
| Instrumentation | Manual `instrument` calls | Automatic via Dispatcher |
| Timing | Manual start/stop | Automatic via `:telemetry.span/3` |
| Exception tracking | ✅ Yes | ✅ Yes (`:exception` events) |
| Metadata | `{service:, key:, checksum:}` | `{service:, operation:, args:}` |

## Future Enhancements

1. **View Helpers**
   ```elixir
   # LiveView component for file uploads
   <.storage_upload field={@form[:avatar]} />
   ```

2. **Image Variants**
   ```elixir
   # On-the-fly image processing
   StorageEx.variant(key, resize: "100x100", format: :webp)
   ```

3. **Mirror Service**
   ```elixir
   # Replicate to multiple backends for redundancy
   StorageEx.Services.Mirror.new(
     primary: disk_service,
     mirrors: [s3_service, gcs_service]
   )
   ```

## What's Missing from Rails Implementation

### Not Implemented (Low Priority)

1. **Download with Block/Callback** (Rails line 28-40)
   - Rails supports: `service.download(key) { |chunk| ... }`
   - StorageEx: Use `download_stream/2` instead which returns a Stream
   - **Impact**: Minor - Stream API is more idiomatic in Elixir

2. **Open Method** (Rails Service line 91-93)
   - Rails: `service.open(key) { |file| ... }` returns file handle
   - StorageEx: Not implemented - use `download/2` or `download_stream/2`
   - **Impact**: Low - download methods provide same functionality

3. **Mirror Service** (Rails has separate service)
   - Rails: `ActiveStorage::Service::MirrorService` for redundancy
   - StorageEx: Not implemented
   - **Impact**: Medium - useful for production redundancy
   - **Future**: Could be implemented as wrapper service

4. **GCS Service** (Google Cloud Storage)
   - Rails: Built-in `ActiveStorage::Service::GCSService`
   - StorageEx: Not implemented
   - **Impact**: Medium - depends on cloud provider needs
   - **Future**: Could be separate package like `storage_ex_gcs`

5. **Service Registry** (Rails Service::Registry)
   - Rails: Manages multiple named services in config
   - StorageEx: Basic config with `get_service!/1`
   - **Impact**: Low - current implementation sufficient for most cases

6. **URL Options via Current** (Rails ActiveStorage::Current)
   - Rails: Global `ActiveStorage::Current.url_options` thread-local
   - StorageEx: Must pass `endpoint` option explicitly
   - **Impact**: Low - explicit is better than implicit in Elixir

### Implementation Differences (By Design)

1. **Error Handling**
   - Rails: Raises exceptions
   - StorageEx: Returns `{:ok, result}` / `{:error, reason}` tuples
   - **Reason**: Idiomatic Elixir pattern

2. **Streaming**
   - Rails: Ruby blocks with yield
   - StorageEx: Elixir Streams
   - **Reason**: More composable and idiomatic

3. **Configuration**
   - Rails: YAML-based config with auto-loading
   - StorageEx: Elixir config with explicit service structs
   - **Reason**: Type-safe and explicit

4. **Instrumentation**
   - Rails: `instrument :operation` method wrapping
   - StorageEx: Automatic via Dispatcher using `:telemetry.span/3`
   - **Reason**: Centralized, no manual instrumentation needed

## Migration Guide from Rails

If migrating from Rails ActiveStorage:

### ✅ Compatible

1. **Folder structure** - Files stored in same `ab/cd/key` structure
2. **Checksum format** - MD5 Base64 encoded (drop-in compatible)
3. **URL signing** - Both use signed tokens with expiration
4. **Direct uploads** - Same pattern: get signed URL, PUT from client
5. **Route structure** - Similar paths with different prefix

### ⚠️ Differences

| Aspect | Rails | StorageEx |
|--------|-------|-----------|
| **Error handling** | Exceptions | Result tuples `{:ok, _}` / `{:error, _}` |
| **Token signing** | MessageVerifier | Phoenix.Token |
| **Routes** | Auto-mounted | Explicit mounting via macro |
| **Streaming** | Blocks/yield | Stream.resource |
| **Configuration** | Global verifier | Per-endpoint tokens |

### Code Examples

```elixir
# Rails - Exceptions
begin
  data = service.download(key)
rescue ActiveStorage::FileNotFoundError
  # handle
end

# StorageEx - Pattern matching
case StorageEx.download(key) do
  {:ok, data} -> # success
  {:error, :file_not_found} -> # handle
end
```

```ruby
# Rails - URL generation (automatic)
rails_blob_path(@blob)
```

```elixir
# StorageEx - URL generation (explicit endpoint)
StorageEx.url(key, endpoint: MyAppWeb.Endpoint, filename: "file.png")
```

```ruby
# Rails - Routes (auto-mounted)
# Automatically available at /rails/active_storage/disk/...
```

```elixir
# StorageEx - Routes (explicit)
use StorageEx.Router
scope "/storage_ex" do
  storage_ex_routes()
end
```

## Summary: Feature Parity Status

### ✅ Complete Parity (100%)

**Core Operations:**
- ✅ File upload with checksum validation
- ✅ File download (full content)
- ✅ Partial downloads (byte ranges)  
- ✅ Stream downloads
- ✅ File deletion (single & prefixed)
- ✅ File existence checks
- ✅ File composition (concatenation)
- ✅ Metadata operations

**Infrastructure:**
- ✅ URL generation (signed)
- ✅ Direct upload URLs
- ✅ Direct upload headers
- ✅ Folder organization (2-level)
- ✅ Checksum validation (MD5 Base64)
- ✅ Error handling
- ✅ Idempotent operations
- ✅ Telemetry/instrumentation
- ✅ Phoenix controller integration
- ✅ Route mounting

### 📋 Missing (Low Priority)

**Service Features:**
- ❌ Download with block/callback (use Stream instead)
- ❌ Open method (use download methods instead)
- ❌ Mirror service (redundancy)
- ❌ GCS service (Google Cloud)
- ❌ Service registry (advanced config)

**Developer Experience:**
- ❌ Thread-local URL options (explicit endpoint instead)
- ❌ View helpers (use Phoenix helpers)
- ❌ Image variants (processing)

### 🎯 Recommended Next Steps

**Priority 1 (High Value):**
1. Add view/LiveView helpers for file uploads
2. Implement Mirror service for production redundancy

**Priority 2 (Nice to Have):**
3. Add image variant processing support
4. Create GCS service package (`storage_ex_gcs`)
5. Implement download with callback support

**Priority 3 (Optional):**
6. Enhanced service registry
7. Additional cloud provider adapters (Azure, etc.)

### Final Assessment

**StorageEx achieves 100% feature parity with Rails ActiveStorage DiskService** for core operations. The missing features are:
- Low priority alternative APIs (download with block)
- Additional service types (Mirror, GCS) 
- Developer convenience features (view helpers, variants)

The implementation is **production-ready** for disk-based storage with complete instrumentation, security (signed URLs), and error handling.
