# Preview Usage Guide

StorageEx now supports generating preview images from non-image files (PDFs, videos) with full caching and URL generation, similar to Rails' ActiveStorage.

## Requirements

### For Video Previews
Install FFmpeg:
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
apt-get install ffmpeg

# Alpine Linux
apk add ffmpeg
```

### For PDF Previews
Install Poppler or MuPDF:
```bash
# macOS
brew install poppler
# or
brew install mupdf-tools

# Ubuntu/Debian
apt-get install poppler-utils
# or
apt-get install mupdf-tools

# Alpine Linux
apk add poppler-utils
# or
apk add mupdf-tools
```

## Basic Usage

### Video Previews

```elixir
# Upload a video
video_data = File.read!("my_video.mp4")
StorageEx.upload("videos/my_video.mp4", video_data, content_type: "video/mp4")

# Create and process preview (extracts first frame as PNG)
preview = StorageEx.preview("videos/my_video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Get URL for the preview
url = StorageEx.Preview.url(preview)

# Download preview data
{:ok, image_data} = StorageEx.Preview.download(preview)
```

### PDF Previews

```elixir
# Upload a PDF
pdf_data = File.read!("document.pdf")
StorageEx.upload("documents/report.pdf", pdf_data, content_type: "application/pdf")

# Create and process preview (renders first page)
preview = StorageEx.preview("documents/report.pdf", content_type: "application/pdf")
{:ok, preview} = StorageEx.Preview.process(preview)

# Get URL
url = StorageEx.Preview.url(preview)
```

## Advanced Options

### Different Output Formats

```elixir
# Generate JPEG instead of PNG
preview = StorageEx.preview("video.mp4",
  content_type: "video/mp4",
  format: :jpg
)
```

### Video: Extract Frame at Specific Time

```elixir
# Extract frame at 5 seconds
preview = StorageEx.preview("video.mp4",
  content_type: "video/mp4",
  time: "00:00:05"
)

# Extract frame at 1 minute 30 seconds
preview = StorageEx.preview("long_video.mp4",
  content_type: "video/mp4",
  time: "00:01:30"
)
```

### URL Options

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Generate URL with custom options
url = StorageEx.Preview.url(preview,
  expires_in: 3600,
  disposition: :inline,
  filename: "video_thumbnail.png"
)
```

## Caching

Previews are automatically cached in storage:

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")

# First call generates the preview
{:ok, preview} = StorageEx.Preview.process(preview)

# Check if preview is cached
StorageEx.Preview.processed?(preview) # => true

# Subsequent calls return immediately
{:ok, preview} = StorageEx.Preview.process(preview) # Instant, uses cache

# Different preview options create different cached previews
preview_5s = StorageEx.preview("video.mp4", content_type: "video/mp4", time: "00:00:05")
StorageEx.Preview.processed?(preview_5s) # => false (different configuration)
```

## Preview + Variant Combined (Recommended)

The easiest way to create thumbnails from previews is using `preview_variant`:

```elixir
# Single-step: preview + variant in one call
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)

{:ok, pv} = StorageEx.PreviewVariant.process(pv)
url = StorageEx.PreviewVariant.url(pv)

# Download thumbnail data
{:ok, thumbnail_data} = StorageEx.PreviewVariant.download(pv)
```

### Multiple Sizes

```elixir
# Create multiple thumbnail sizes
small = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [100, 100]]
)

medium = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [300, 300]]
)

large = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  variant: [resize_to_limit: [800, 800]]
)

# Process all (can be done in parallel with Task.async)
{:ok, small} = StorageEx.PreviewVariant.process(small)
{:ok, medium} = StorageEx.PreviewVariant.process(medium)
{:ok, large} = StorageEx.PreviewVariant.process(large)
```

### With Preview Options

```elixir
# Extract frame at 5 seconds and create thumbnail
pv = StorageEx.preview_variant("video.mp4",
  content_type: "video/mp4",
  time: "00:00:05",
  variant: [resize_to_fill: [200, 200], format: :webp]
)
```

## Preview + Variant Workflow (Manual)

Create thumbnails from preview images:

```elixir
# Generate preview from video
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Get the preview's storage key
preview_key = StorageEx.Preview.key(preview)

# Create thumbnail variant from the preview
thumbnail = StorageEx.variant(preview_key, resize_to_limit: [100, 100])
{:ok, thumbnail} = StorageEx.Variant.process(thumbnail)

# Get URL for thumbnail
thumbnail_url = StorageEx.Variant.url(thumbnail)
```

### Multiple Thumbnails from One Preview

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

preview_key = StorageEx.Preview.key(preview)

# Create multiple sizes
small = StorageEx.variant(preview_key, resize_to_limit: [100, 100])
medium = StorageEx.variant(preview_key, resize_to_limit: [300, 300])
large = StorageEx.variant(preview_key, resize_to_limit: [800, 800])

{:ok, small} = StorageEx.Variant.process(small)
{:ok, medium} = StorageEx.Variant.process(medium)
{:ok, large} = StorageEx.Variant.process(large)
```

## Storage Keys

Previews are stored at:
```
previews/{blob_key}/{hash}
```

The hash is generated from:
- Content type
- Output format
- Preview options (e.g., time position for videos)

This ensures different preview configurations are cached separately.

## Error Handling

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")

case StorageEx.Preview.process(preview) do
  {:ok, preview} ->
    # Success
    url = StorageEx.Preview.url(preview)

  {:error, :no_previewer} ->
    # No previewer available for this content type
    # Or required system tool (FFmpeg/Poppler) not installed

  {:error, reason} ->
    # Other error (file not found, processing failed, etc.)
    Logger.error("Preview failed: #{inspect(reason)}")
end
```

## Cleanup

Delete preview (but not original blob):

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
StorageEx.Preview.delete(preview)
```

## Configuration

Configure available previewers in your `config/config.exs`:

```elixir
config :storage_ex,
  previewers: [
    StorageEx.Previewers.PopplerPDFPreviewer,
    StorageEx.Previewers.MuPDFPreviewer,
    StorageEx.Previewers.VideoPreviewer
  ]
```

The first previewer that accepts the content type will be used.

## Supported Content Types

### Video (via FFmpeg)
- video/mp4
- video/webm
- video/quicktime
- video/x-msvideo
- And any format FFmpeg supports

### PDF (via Poppler or MuPDF)
- application/pdf
- application/x-pdf

## Phoenix Integration

In your Phoenix controller:

```elixir
def show(conn, %{"id" => id}) do
  # Assuming you have a blob record with key and content_type
  blob = MyApp.Blobs.get!(id)
  
  preview = StorageEx.preview(blob.key, content_type: blob.content_type)
  {:ok, preview} = StorageEx.Preview.process(preview)
  
  preview_url = StorageEx.Preview.url(preview)
  
  render(conn, "show.html", preview_url: preview_url)
end
```

In your template:

```heex
<img src={@preview_url} alt="Preview" />
```

## JSON API / Inertia.js

Previews can be serialized to JSON:

```elixir
preview = StorageEx.preview("video.mp4", content_type: "video/mp4")
{:ok, preview} = StorageEx.Preview.process(preview)

# Get URL for JSON response
preview_data = %{
  url: StorageEx.Preview.url(preview),
  key: StorageEx.Preview.key(preview),
  processed: StorageEx.Preview.processed?(preview)
}

Jason.encode!(preview_data)
```
