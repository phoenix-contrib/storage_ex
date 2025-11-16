# PreviewVariant Implementation Summary

## What Was Added

Following Rails' ActiveStorage pattern, we've added `StorageEx.PreviewVariant` to combine preview generation and variant transformation into a single, convenient operation.

## Problem It Solves

### Before (Two-Step Process)

```elixir
# Step 1: Generate preview
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Step 2: Create variant from preview
preview_key = StorageEx.Preview.key(preview)
variant = StorageEx.variant(preview_key, resize_to_limit: [100, 100])
{:ok, variant} = StorageEx.Variant.process(variant)

# Get URL
url = StorageEx.Variant.url(variant)
```

### After (Single Operation)

```elixir
# One step: preview + variant
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)

{:ok, pv} = StorageEx.PreviewVariant.process(pv)
url = StorageEx.PreviewVariant.url(pv)
```

## Rails Comparison

### Rails
```ruby
# In view
image_tag video.preview(resize_to_limit: [100, 100]).processed.url
```

### StorageEx
```elixir
# In controller
pv = StorageEx.preview_variant(video_key,
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)
{:ok, pv} = StorageEx.PreviewVariant.process(pv)
url = StorageEx.PreviewVariant.url(pv)
```

Much closer to Rails' API!

## Implementation Details

### Module: `StorageEx.PreviewVariant`

**Struct:**
```elixir
%StorageEx.PreviewVariant{
  preview: %StorageEx.Preview{},
  variant: %StorageEx.Variation{} | nil,
  service_name: atom() | nil
}
```

**Key Functions:**
- `new/2` - Create preview variant specification
- `process/1` - Generate preview, apply variant, cache result
- `download/1` - Download transformed data
- `url/2` - Generate signed URL
- `delete/1` - Remove from storage
- `processed?/1` - Check if cached
- `key/1` - Get storage key

### Storage Path

Preview variants are stored at:
```
variants/{preview_key}/{variant_hash}
```

Example:
```
variants/previews/video.mp4/abc123.../def456...
         ^                  ^         ^
         |                  |         variant hash
         |                  preview hash
         preview prefix
```

This allows:
- Same preview to have multiple variant sizes
- Independent caching per variant
- Efficient storage reuse

### Processing Flow

1. **Check if cached**: `variants/{preview_key}/{variant_hash}` exists?
2. **If not cached**:
   - Generate preview (or get from cache)
   - Download preview image data
   - Apply variant transformations
   - Upload result to storage
3. **Return**: Preview variant ready

### Caching Strategy

Three levels of caching:

1. **Preview cache**: `previews/{blob_key}/{preview_hash}`
   - Shared across all variants of same preview

2. **Variant cache**: `variants/{preview_key}/{variant_hash}`
   - Specific to each size/transformation

3. **Blob cache**: Original file in storage
   - Never re-downloaded if preview cached

## Usage Examples

### Basic Thumbnail

```elixir
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)

{:ok, pv} = StorageEx.PreviewVariant.process(pv)
url = StorageEx.PreviewVariant.url(pv)
```

### Multiple Sizes

```elixir
sizes = [
  [resize_to_limit: [100, 100]],
  [resize_to_limit: [300, 300]],
  [resize_to_limit: [800, 800]]
]

thumbnails =
  sizes
  |> Enum.map(fn variant_opts ->
    StorageEx.preview_variant("video.mp4",
      content_type: "video/mp4",
      variant: variant_opts
    )
  end)
  |> Enum.map(&StorageEx.PreviewVariant.process/1)
  |> Enum.map(fn {:ok, pv} -> StorageEx.PreviewVariant.url(pv) end)

# => ["url1", "url2", "url3"]
```

### With Preview Options

```elixir
# Frame at 5 seconds, resized
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  time: "00:00:05",
  variant: [resize_to_fill: [200, 200]]
)

# PDF page 1, as thumbnail
pv = StorageEx.preview_variant("document.pdf",
  content_type: "application/pdf",
  variant: [resize_to_limit: [300, 300]]
)

# Different formats
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  format: :jpg,                            # Preview as JPEG
  variant: [resize_to_limit: [100, 100], format: :webp]  # Variant as WebP
)
```

### Without Variant (Plain Preview)

```elixir
# If no variant specified, works like plain preview
pv = StorageEx.preview_variant("video.mp4", content_type: "video/mp4")
{:ok, pv} = StorageEx.PreviewVariant.process(pv)

# Equivalent to:
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)
```

## API Design Decisions

### 1. Combined Struct

We use a single struct that wraps both preview and variant:

```elixir
%PreviewVariant{
  preview: %Preview{},
  variant: %Variation{} | nil
}
```

**Benefits:**
- Clear ownership
- Single processing entry point
- Variant is optional (can be nil)

### 2. Storage Path

We store variants under the preview path:

```
variants/{preview_key}/{variant_hash}
```

**Benefits:**
- All variants of same preview are grouped
- Preview itself can be shared
- Clear hierarchy

### 3. Public API

Simple, Rails-like API:

```elixir
StorageEx.preview_variant(key, opts)
```

**Benefits:**
- Consistent with `preview/2` and `variant/3`
- All options in one place
- Easy to document

## Files Created

1. `lib/preview_variant.ex` - Main module (340 lines)
2. `test/preview_variant_test.exs` - Unit tests (270 lines)
3. `test/preview_variant_integration_test.exs` - Integration tests (380 lines)
4. Updated `lib/storage_ex.ex` - Added `preview_variant/2`
5. Updated documentation files

## Testing

### Unit Tests
- Preview variant creation
- Key generation
- Storage path logic
- Format handling
- Public API

### Integration Tests
- Real video processing
- Real PDF processing
- Multiple variant sizes
- Caching behavior
- Error handling

Run tests:
```bash
# Unit tests
mix test test/preview_variant_test.exs

# Integration tests (requires FFmpeg/Poppler)
mix test test/preview_variant_integration_test.exs --only integration

# All preview-related tests
mix test test/preview*.exs
```

## Performance

### Single Preview, Multiple Variants

```elixir
# First variant: ~1-2s (generates preview + variant)
pv1 = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)
{:ok, _} = StorageEx.PreviewVariant.process(pv1)  # ~1-2s

# Second variant: ~500ms (preview cached, only variant processing)
pv2 = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [300, 300]]
)
{:ok, _} = StorageEx.PreviewVariant.process(pv2)  # ~500ms

# Third call to same variant: ~50ms (fully cached)
{:ok, _} = StorageEx.PreviewVariant.process(pv1)  # ~50ms
```

### Benefits
- Preview generation happens once
- Subsequent variants reuse preview
- All results cached independently

## Comparison with Manual Approach

| Aspect | Manual (2 steps) | PreviewVariant |
|--------|------------------|----------------|
| **API Calls** | 4+ function calls | 2 function calls |
| **Code Clarity** | Medium | High |
| **Error Handling** | Multiple points | Single point |
| **Storage Keys** | Manual management | Automatic |
| **Caching** | Must track both | Single check |
| **Rails Similarity** | Low | High |

## Migration Path

Existing code using manual approach still works:

```elixir
# Old way - still works
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)
variant = StorageEx.variant(StorageEx.Preview.key(preview), resize_to_limit: [100, 100])
{:ok, variant} = StorageEx.Variant.process(variant)

# New way - recommended
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)
{:ok, pv} = StorageEx.PreviewVariant.process(pv)
```

Both approaches produce the same results, just different API convenience.

## Future Enhancements

Possible additions (separate PRs):

1. **Parallel Processing**
   ```elixir
   StorageEx.PreviewVariant.process_batch([pv1, pv2, pv3])
   ```

2. **Lazy URL Generation**
   ```elixir
   # URL that processes on-demand
   url = StorageEx.lazy_preview_variant_url(key, opts)
   ```

3. **Background Jobs**
   ```elixir
   StorageEx.PreviewVariant.process_async(pv)
   # Returns job ID, processes in background
   ```

## Conclusion

`StorageEx.PreviewVariant` provides a convenient, Rails-like API for generating thumbnails from videos and PDFs. It combines the best of both `Preview` and `Variant` modules while maintaining clean separation and efficient caching.
