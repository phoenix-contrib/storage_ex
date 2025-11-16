# Rails ActiveStorage vs StorageEx: Preview & Transformer System

## Overview

Rails ActiveStorage provides a sophisticated system for:
1. **Previews** - Generate preview images from non-image files (PDFs, videos)
2. **Variants** - Transform images (resize, crop, format conversion)
3. **Transformers** - Apply transformations using libvips or ImageMagick via the `image_processing` gem

This document analyzes the Rails implementation and describes the Elixir equivalent for StorageEx.

---

## Image Processing Abstraction

### Rails: `image_processing` gem

Rails uses the [`image_processing`](https://github.com/janko/image_processing) gem which provides:
- Unified API for MiniMagick and ruby-vips
- Chainable operations
- Auto format detection
- Macro operations like `resize_to_limit`, `resize_to_fill`, etc.

### Elixir: `image` package

StorageEx uses the [`image`](https://hex.pm/packages/image) package which provides:
- Built on top of Vix (libvips bindings)
- High-level abstraction similar to `image_processing`
- Chainable operations via pipelines
- Format detection and conversion
- Same macro operations (thumbnail with fit options)
- **Pre-compiled binaries** for easy development

This makes `image` the **direct equivalent** of Ruby's `image_processing` gem!

---

## Core Concepts

### 1. Previewer (Abstract Base)

**Purpose**: Extract preview images from non-image blobs (PDFs, videos).

**Key Methods**:
- `accept?(blob)` - Class method to determine if previewer can handle the blob
- `preview(**options)` - Generate preview image, yields attachable hash
- `download_blob_to_tempfile(&block)` - Download blob for processing
- `draw(*argv)` - Execute system command to generate preview

**Built-in Previewers**:
- `VideoPreviewer` - Uses FFmpeg to extract first frame
- `PopplerPDFPreviewer` - Uses poppler's pdftoppm for PDF preview
- `MuPDFPreviewer` - Uses muPDF's mutool for PDF preview

### 2. Transformer (Abstract Base)

**Purpose**: Apply transformations to images (resize, crop, format).

**Key Methods**:
- `initialize(transformations)` - Hash of transformation operations
- `transform(file, format:)` - Apply transformations, yield result
- `process(file, format:)` - Private method implemented by subclasses

### Built-in Transformers**:
- `ImageProcessingTransformer` - Base class using `image_processing` gem
- `Vips` - libvips implementation via `image_processing` (faster, less memory)
- `ImageMagick` - ImageMagick/MiniMagick implementation via `image_processing`
- `NullTransformer` - No-op for disabled transformations

### 3. Variation

**Purpose**: Encapsulates a set of transformations to apply to a blob.

**Key Features**:
- Stores transformation parameters (e.g., `resize_to_limit: [100, 100]`)
- Generates signed keys for URL routing
- Determines output format and content type
- Delegates to configured transformer for processing

### 4. Variant

**Purpose**: Represents a transformed version of a blob.

**Key Features**:
- Created from blob + variation
- Lazy processing (only generates when needed)
- Caches result in storage service
- Generates derivative key: `variants/{blob.key}/{variation.digest}`

### 5. Preview

**Purpose**: Represents a previewable non-image blob with optional transformations.

**Key Features**:
- Extracts preview image using appropriate Previewer
- Attaches preview image to blob
- Can apply Variant transformations to the preview
- Lazy processing with cached results

---

## Rails Implementation Details

**Key Points**:
- Graceful degradation with warnings
- Configuration-driven transformer selection
- Catches LoadError when dependencies missing
- Fallback to NullTransformer if needed

---

## Comparison with Rails

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| **Base Abstraction** | Class inheritance | Behavior (@behaviour) |
| **High-level API** | `image_processing` gem | `image` package ✅ |
| **Transformer Selection** | Config + LoadError rescue | Config + availability check |
| **Default Processor** | :mini_magick (old), :vips (new) | :vips |
| **Vips Library** | `image_processing` + `ruby-vips` | `image` package (Vix) ✅ |
| **Pre-compiled Binaries** | No | ✅ Yes (via `image` package) |
| **Error Handling** | Exceptions | {:ok, _} / {:error, _} tuples |
| **Resize Operations** | `resize_to_limit`, etc. | ✅ Same via `Image.thumbnail` |
| **Variant Key** | SHA256 of variation key | SHA256 of transformations |
| **Storage Path** | `variants/{key}/{digest}` | ✅ Same |
| **Lazy Processing** | ✅ Yes | ✅ Yes |
| **Caching** | ✅ Check service.exist? | ✅ Same |
| **Configuration** | `config.active_storage.variant_processor` | `config :storage_ex, variant_processor:` |
| **Null Transformer** | ✅ Yes (for :disabled) | ✅ Yes |
| **Dependency Check** | At initialization | ✅ At initialization |
| **Graceful Degradation** | ✅ Warnings + fallback | ✅ Warnings + fallback |
| **Variant URL Helper** | `variant.url(options)` | ✅ `Variant.url(variant, options)` |
| **URL Options** | expires_in, disposition, filename | ✅ Same |
| **Auto Filename** | ✅ From blob + extension | ✅ Same |

---

## Implementation Status

### ✅ Implemented

1. **Core Transformer Behavior**
   - `StorageEx.Transformer` behavior definition
   - `StorageEx.Transformers.Vips` - libvips implementation using `image` package
   - `StorageEx.Transformers.Null` - No-op transformer

2. **Variation & Variant**
   - `StorageEx.Variation` - Transformation specification
   - `StorageEx.Variant` - Processed variant with caching
   - Key generation using SHA256 hashes
   - Integration with existing services

3. **Configuration & Dependency Checking**
   - `StorageEx.Config.variant_transformer/0` - Transformer selection
   - Availability checking via `Code.ensure_loaded?/1`
   - Graceful fallback to NullTransformer
   - Warning messages when dependencies missing

4. **Public API for Variants**
   - `StorageEx.variant/3` - Create variant specification
   - `StorageEx.Variant.process/1` - Process variant
   - `StorageEx.Variant.download/1` - Download variant data
   - `StorageEx.Variant.url/2` - ✅ Generate URL for variant
   - `StorageEx.Variant.delete/1` - Delete variant

5. **URL Helpers** ✅
   - `StorageEx.Variant.url/2` - Generate URLs for variants (like Rails)
   - Supports all URL options: `:expires_in`, `:disposition`, `:filename`, `:endpoint`
   - Automatic filename generation with correct extension
   - Processes variant if not already processed

6. **Previewer Behavior & Implementations** ✅
   - `StorageEx.Previewer` behavior definition
   - `StorageEx.Previewer.find_previewer/1` - Auto-discovery based on content type
   - `StorageEx.Previewers.VideoPreviewer` - FFmpeg-based video preview extraction
   - `StorageEx.Previewers.PopplerPDFPreviewer` - Poppler-based PDF rendering
   - `StorageEx.Previewers.MuPDFPreviewer` - MuPDF-based PDF rendering
   - Configuration system: `config :storage_ex, previewers: [...]`
   - Helper functions for command execution and availability checking
   - Comprehensive tests for all previewers

7. **Preview Module (High-Level Orchestration)** ✅
   - `StorageEx.Preview` module - Wraps blob key and manages preview lifecycle
   - Preview caching/storage logic (checks if preview exists before regenerating)
   - Storage key convention: `previews/{blob_key}/{preview_digest}`
   - Lazy preview processing (similar to variants)
   - Hash-based key generation from content_type + format + options
   - Support for format options (`:png`, `:jpg`)
   - Support for previewer-specific options (e.g., `:time` for videos)

8. **Public API for Previews** ✅
   - `StorageEx.preview/2` - Create preview specification (blob key + opts)
   - `StorageEx.Preview.process/1` - Generate preview if not cached
   - `StorageEx.Preview.download/1` - Download preview data
   - `StorageEx.Preview.url/2` - Generate URL for preview
   - `StorageEx.Preview.delete/1` - Delete preview from storage
   - `StorageEx.Preview.processed?/1` - Check if preview exists
   - `StorageEx.Preview.key/1` - Get storage key for preview

9. **Comprehensive Tests** ✅
   - Unit tests for Preview module (`test/preview_test.exs`)
   - Integration tests with real files (`test/preview_integration_test.exs`)
   - Tests for video previews (FFmpeg)
   - Tests for PDF previews (Poppler/MuPDF)
   - Tests for error handling and edge cases

10. **PreviewVariant Module** ✅
   - `StorageEx.PreviewVariant` - Combined preview + variant processing
   - `StorageEx.preview_variant/2` - Public API
   - Single-step operation: preview generation + variant transformation
   - All Preview and Variant options supported
   - Storage path: `variants/{preview_key}/{variant_hash}`
   - Independent caching per variant size
   - Functions: `new/2`, `process/1`, `download/1`, `url/2`, `delete/1`, `processed?/1`, `key/1`

11. **PreviewVariant Tests** ✅
   - Unit tests (`test/preview_variant_test.exs`)
   - Integration tests with real files (`test/preview_variant_integration_test.exs`)
   - Multiple variant sizes from same preview
   - Format handling and conversions

### ❌ Missing (Compared to Rails)

1. **Ecto Integration** (Out of Scope - Requires Database)
   - Auto-attach preview image to original blob record
   - `Blob.preview()` method on Ecto schemas
   - Automatic cleanup when parent blob is deleted
   - Preview metadata persistence in database

### 🔜 Future Work

1. **Additional Transformers**
   - ImageMagick transformer (via Mogrify)
   - Custom transformer examples

---

## Files Created

### Transformer & Variant System
1. `lib/transformer.ex` - Behavior definition
2. `lib/transformers/vips.ex` - Vips implementation
3. `lib/transformers/null.ex` - Null implementation
4. `lib/variation.ex` - Transformation specification
5. `lib/variant.ex` - Variant processing
6. Updated `lib/config.ex` - Transformer configuration
7. Updated `lib/storage_ex.ex` - Public API

### Previewer System (Implementation Layer Only)
8. `lib/previewer.ex` - Behavior definition with helper functions
9. `lib/previewers/video_previewer.ex` - FFmpeg-based video previews
10. `lib/previewers/poppler_pdf_previewer.ex` - Poppler PDF previews
11. `lib/previewers/mupdf_previewer.ex` - MuPDF PDF previews
12. `test/previewers_test.exs` - Unit tests for previewers
13. `test/previewers_integration_test.exs` - Integration tests

### Preview System (Orchestration Layer) ✅
14. `lib/preview.ex` - High-level Preview module
15. Updated `lib/storage_ex.ex` - Public API with `preview/2` function
16. `test/preview_test.exs` - Unit tests for Preview module
17. `test/preview_integration_test.exs` - Integration tests with real files

### PreviewVariant System (Combined Preview + Variant) ✅
18. `lib/preview_variant.ex` - Combined preview and variant processing
19. Updated `lib/storage_ex.ex` - Added `preview_variant/2` function
20. `test/preview_variant_test.exs` - Unit tests
21. `test/preview_variant_integration_test.exs` - Integration tests

---

## Dependencies

### Required
- `phoenix` - For URL generation
- `plug` - For web integration

### Optional (for variants)
- `image ~> 0.37` - High-level image processing (recommended, includes pre-compiled libvips)
- libvips 8.6+ system library (optional, for production with full format support)

### Optional (for previews)
- FFmpeg - For video previews (`brew install ffmpeg`, `apt-get install ffmpeg`)
- Poppler - For PDF previews (`brew install poppler`, `apt-get install poppler-utils`)
- MuPDF - Alternative PDF previews (`brew install mupdf-tools`, `apt-get install mupdf-tools`)

---

## Summary

### ✅ Fully Implemented (Storage-Only, No Ecto)

1. **Variant/Transformer System** - Complete with URL helpers
2. **Previewer Implementations** - Video (FFmpeg), PDF (Poppler/MuPDF)
3. **Preview Orchestration Module** - Full lifecycle management
4. **Public APIs** - Both `variant/3` and `preview/2`
5. **Comprehensive Testing** - Unit and integration tests for all features

### ❌ Not Implemented (Would Require Ecto)

1. **Preview + Variant Direct Chaining** - Can be added without Ecto if desired
2. **Ecto Integration** - Requires database tables and schemas

## Next Steps

**For immediate use (without Ecto):**

The storage-only implementation is complete! You can:
- Generate variants from images
- Generate previews from videos and PDFs
- Create variants from previews (manual two-step process)
- All results are cached in storage with proper key hashing

**Example Usage:**

```elixir
# Preview from video
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)
url = StorageEx.Preview.url(preview)

# Variant from preview
preview_key = StorageEx.Preview.key(preview)
variant = StorageEx.variant(preview_key, resize_to_limit: [100, 100])
{:ok, variant} = StorageEx.Variant.process(variant)
variant_url = StorageEx.Variant.url(variant)
```

**Future enhancements:**

### 1. Preview + Variant Helper ✅ (Implemented)
Combined preview and variant in one operation:

```elixir
# Instead of manual two-step
preview_variant = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)
{:ok, pv} = StorageEx.PreviewVariant.process(preview_variant)
url = StorageEx.PreviewVariant.url(pv)
```

Benefits:
- Single function call
- Atomic operation
- Cleaner API
- Matches Rails behavior more closely
- Caches at variant level (same preview, multiple variants)

### 2. Lazy URL Generation (Rails-style)
Generate signed URLs that process on-demand:

```elixir
# Controller - instant, no blocking
url = StorageEx.lazy_preview_variant_url("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)
# Returns: "/rails/active_storage/representations/preview/..."

# Processing happens when browser requests the URL
# Phoenix endpoint checks cache, processes if needed, redirects
```

Implementation needs:
- Phoenix controller endpoint (`StorageExWeb.RepresentationsController`)
- Signed token generation/verification
- URL routing conventions
- Redirect to cached/processed asset

Benefits:
- Fast page loads
- Processing only when needed
- Better UX (page renders immediately)
- Background processing possible

### 3. Additional Transformers
ImageMagick transformer via Mogrify:

```elixir
# config.exs
config :storage_ex, variant_processor: :imagemagick

# lib/transformers/image_magick.ex
defmodule StorageEx.Transformers.ImageMagick do
  @behaviour StorageEx.Transformer
  # Use Mogrify package for ImageMagick operations
end
```

Benefits:
- More transformation options
- Fallback when libvips unavailable
- GIF animation support

### 4. Batch Processing
Process multiple variants simultaneously:

```elixir
variants = [
  [resize_to_limit: [100, 100]],
  [resize_to_limit: [300, 300]],
  [resize_to_limit: [800, 800]]
]

{:ok, processed} = StorageEx.Variant.process_batch("photo.jpg", variants)
# Processes in parallel using Task.async_stream
```

Benefits:
- Performance optimization
- Single download of source
- Parallel processing
- Common use case (responsive images)

### 5. Composite/Overlay Operations
Advanced image composition:

```elixir
# Add watermark
variant = StorageEx.variant("photo.jpg",
  composite: [
    overlay: "watermark.png",
    gravity: :south_east,
    offset: [10, 10],
    opacity: 0.5
  ]
)

# Combine images
variant = StorageEx.variant("background.jpg",
  composite: [
    overlay: "foreground.png",
    blend_mode: :multiply
  ]
)
```

Use cases:
- Watermarking
- Logo overlay
- Image frames/borders
- Collages

### 6. Direct Upload Helpers
JavaScript helpers for browser → storage uploads:

```javascript
// app.js
import { DirectUpload } from "storage_ex"

const upload = new DirectUpload(file, "/storage/uploads", {
  directUploadUrl: "/api/storage/direct_uploads",
  onProgress: (progress) => {
    console.log(`${progress}% uploaded`)
  }
})

upload.create((error, blob) => {
  if (error) {
    console.error(error)
  } else {
    // Use blob.signed_id in your form
    document.querySelector("#blob_id").value = blob.signed_id
  }
})
```

Server-side:

```elixir
# In controller
def create_direct_upload(conn, %{"filename" => filename, "content_type" => content_type}) do
  {:ok, url} = StorageEx.url_for_direct_upload(generate_key(filename),
    content_type: content_type,
    expires_in: 600
  )
  
  json(conn, %{url: url, headers: StorageEx.headers_for_direct_upload(...)})
end
```

Benefits:
- No server upload processing
- Progress indicators
- Large file support
- Reduced server load

### 7. Mirror Service
Upload to multiple services simultaneously:

```elixir
config :storage_ex,
  service: :primary,
  services: %{
    primary: %{
      service: StorageEx.Services.Mirror,
      primary: :s3_primary,
      mirrors: [:s3_backup, :local_cache]
    },
    s3_primary: %{service: StorageExS3.Service, ...},
    s3_backup: %{service: StorageExS3.Service, ...},
    local_cache: %{service: StorageEx.Services.DiskService, ...}
  }
```

Implementation:

```elixir
defmodule StorageEx.Services.Mirror do
  # Upload to primary first
  # Then upload to mirrors in background
  # Read from primary only
  # Handle mirror failures gracefully
end
```

Benefits:
- Redundancy
- Geographic distribution
- Backup strategy
- Local caching

### 8. Phoenix LiveView Components
Pre-built components for common patterns:

```elixir
# Upload component
<.live_file_input upload={@uploads.avatar} />

# Image with variants
<.storage_image blob={@avatar} variant={[resize_to_limit: [100, 100]]} />

# Video preview
<.storage_video_preview blob={@video} time="00:00:05" />

# Direct upload with progress
<.storage_upload_form upload={@uploads.document} on_complete={&handle_upload/1} />
```

### 9. Ecto Integration Package
`storage_ex_ecto` - separate package for database integration:

```elixir
# In schema
schema "posts" do
  field :title, :string
  has_one_attached :cover_image  # Single attachment
  has_many_attached :photos      # Multiple attachments
end

# Usage
post.cover_image.variant(resize_to_limit: [100, 100]).url()
post.photos.each(&(&1.preview.url()))
```

Features:
- Attachment associations
- Automatic cleanup
- Metadata persistence
- Blob identification

