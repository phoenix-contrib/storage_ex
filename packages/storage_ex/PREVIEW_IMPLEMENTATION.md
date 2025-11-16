# Preview Implementation Summary

## What Was Implemented

Following Rails' ActiveStorage design, we've implemented a complete **storage-only** preview system for StorageEx that works without requiring Ecto or database tables.

### Core Components

#### 1. StorageEx.Preview Module (`lib/preview.ex`)
High-level orchestration layer that manages the preview lifecycle:

- **Struct**: Holds blob_key, content_type, format, preview_options, service_name
- **Key Generation**: Hash-based keys from `{content_type, format, options}`
- **Storage Path**: `previews/{blob_key}/{hash}`
- **Lazy Processing**: Only generates if not cached
- **URL Generation**: Full support with signed URLs

**Key Functions:**
- `new/2` - Create preview specification
- `process/1` - Generate or return cached preview
- `download/1` - Download preview data
- `url/2` - Generate signed URL
- `delete/1` - Remove from storage
- `processed?/1` - Check if cached
- `key/1` - Get storage key

#### 2. Public API (`lib/storage_ex.ex`)
Added `StorageEx.preview/2` function to main API:

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
```

Follows the same pattern as `StorageEx.variant/3`.

#### 3. Integration with Existing Previewers
The Preview module uses the existing previewer infrastructure:

- `StorageEx.Previewer.find_previewer/1` - Auto-discovery by content type
- `StorageEx.Previewers.VideoPreviewer` - FFmpeg-based video previews
- `StorageEx.Previewers.PopplerPDFPreviewer` - Poppler PDF previews
- `StorageEx.Previewers.MuPDFPreviewer` - MuPDF PDF previews

#### 4. Comprehensive Testing

**Unit Tests** (`test/preview_test.exs`):
- Preview creation and configuration
- Key generation and hashing
- Format handling
- Public API integration

**Integration Tests** (`test/preview_integration_test.exs`):
- Real video preview generation
- Real PDF preview generation
- Caching behavior
- Error handling
- URL generation
- Preview + Variant workflow

## Design Decisions

### 1. Storage-Only (No Ecto)
Like the Variant system, Preview works purely with storage keys. No database required.

**Benefits:**
- Simple to use
- No migrations needed
- Works with any storage backend
- Can add Ecto later if needed

### 2. Hash-Based Caching
Preview keys include a hash of:
- Content type
- Output format
- Preview options (e.g., time position for videos)

This ensures different configurations create different cached previews.

**Example:**
```
previews/video.mp4/a1b2c3d4... (first frame, PNG)
previews/video.mp4/e5f6g7h8... (5 second mark, PNG)
previews/video.mp4/i9j0k1l2... (first frame, JPEG)
```

### 3. Explicit Content Type Requirement
Unlike Rails (which gets content_type from database blob record), StorageEx requires it:

```elixir
# Required
StorageEx.preview("video.mp4", content_type: "video/mp4")
```

This is necessary because we're storage-only and don't have a blob table.

### 4. Previewer-Specific Options
Options are passed through to previewers:

```elixir
# Video-specific
StorageEx.preview("video.mp4", content_type: "video/mp4", time: "00:00:05")

# Format option (applies to all)
StorageEx.preview("doc.pdf", content_type: "application/pdf", format: :jpg)
```

## Comparison with Rails

| Feature | Rails ActiveStorage | StorageEx | Notes |
|---------|-------------------|-----------|-------|
| Preview Module | `ActiveStorage::Preview` | `StorageEx.Preview` | ✅ Complete |
| Storage Path | `previews/{key}/{hash}` | `previews/{key}/{hash}` | ✅ Same |
| Lazy Processing | ✅ Yes | ✅ Yes | ✅ Same |
| Caching | ✅ Yes | ✅ Yes | ✅ Same |
| URL Generation | `preview.url(opts)` | `Preview.url(preview, opts)` | ✅ Module function |
| Auto-discovery | ✅ Yes | ✅ Yes | Via `find_previewer/1` |
| Content Type | From blob record | Passed as option | Difference due to no DB |
| Blob Association | Via database | Manual (storage-only) | Expected |
| Preview + Variant | Automatic | Two-step process | Can be improved |

## Usage Patterns

### Basic Preview

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)
url = StorageEx.Preview.url(preview)
```

### Preview + Variant

```elixir
# Generate preview
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Create thumbnail from preview
preview_key = StorageEx.Preview.key(preview)
thumbnail = StorageEx.variant(preview_key, resize_to_limit: [100, 100])
{:ok, thumbnail} = StorageEx.Variant.process(thumbnail)

thumbnail_url = StorageEx.Variant.url(thumbnail)
```

### Multiple Formats/Times

```elixir
# Different preview configurations
png_preview = StorageEx.preview("video.mp4", content_type: "video/mp4", format: :png)
jpg_preview = StorageEx.preview("video.mp4", content_type: "video/mp4", format: :jpg)
later_preview = StorageEx.preview("video.mp4", content_type: "video/mp4", time: "00:00:05")

# Each creates a separate cached preview
```

## Files Created/Modified

### New Files
1. `lib/preview.ex` - Preview module (360 lines)
2. `test/preview_test.exs` - Unit tests (216 lines)
3. `test/preview_integration_test.exs` - Integration tests (258 lines)
4. `PREVIEW_USAGE.md` - User guide
5. `PREVIEW_IMPLEMENTATION.md` - This file

### Modified Files
1. `lib/storage_ex.ex` - Added `preview/2` public API
2. `rails_comporation/Preview.md` - Updated comparison document

## What's NOT Implemented

### 1. Direct Preview + Variant Chaining
Rails allows: `blob.preview(resize: [200, 200])`

StorageEx requires two steps:
```elixir
{:ok, preview} = Preview.process(preview)
variant = StorageEx.variant(Preview.key(preview), resize_to_limit: [100, 100])
```

**Could be added** without Ecto by implementing a pipe operator or helper.

### 2. Ecto Integration
Rails features requiring database:
- Auto-attach preview to blob record
- `blob.preview()` method on records
- Automatic cleanup on blob deletion
- Preview metadata persistence

**Future work**: Could be added in `storage_ex_ecto` package.

## Testing

Run tests:

```bash
# All tests
cd packages/storage_ex && mix test

# Unit tests only
mix test test/preview_test.exs

# Integration tests (requires FFmpeg/Poppler)
mix test test/preview_integration_test.exs --only integration
```

## Dependencies

### Runtime
- `crypto` - For hash generation (built-in)
- Existing previewer dependencies (FFmpeg, Poppler, MuPDF) - optional

### No New Dependencies Added
The Preview module uses only what's already available in StorageEx.

## Performance

- **First preview**: Downloads blob, generates preview, uploads result (~1-2s for video)
- **Cached preview**: Storage exists check only (~10-50ms)
- **URL generation**: Same as regular blob URLs (signed with Phoenix.Token)

## Production Considerations

1. **Tool Availability**: Ensure FFmpeg/Poppler/MuPDF installed on servers
2. **Storage Space**: Previews are cached permanently until deleted
3. **Cleanup**: Implement cleanup jobs to remove unused previews
4. **Concurrent Processing**: Multiple requests for same preview race to process (first wins)

## Next Steps

### Optional Enhancements
1. Add preview pipe operator for cleaner chaining
2. Add preview variant transformation in one step
3. Implement background processing (via Oban/Quantum)
4. Add cleanup utilities

### Future Ecto Integration
When ready for database integration:
1. Create `storage_ex_ecto` package
2. Add blob/attachment tables
3. Implement auto-attachment
4. Add cascade delete support
