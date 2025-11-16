# Rails ActiveStorage vs StorageEx: Image Analysis & Metadata

## Overview

Rails ActiveStorage provides image analysis capabilities to extract metadata from image files without downloading the entire file. This document outlines the Rails implementation and proposes an Elixir equivalent for StorageEx.

---

## Rails Implementation

### ActiveStorage::Analyzer

Rails uses the Analyzer pattern to extract metadata from blobs:

**Base Class: `ActiveStorage::Analyzer`**

```ruby
class ActiveStorage::Analyzer
  def self.accept?(blob)
    # Subclass determines if it can analyze this blob
  end

  def metadata
    # Subclass returns hash of metadata
  end
end
```

**Built-in Analyzers:**

1. **ImageAnalyzer** - Uses ImageMagick or libvips
   - Dimensions (width, height)
   - Format (jpg, png, webp, etc.)
   - File size
   - Color space
   - Orientation (EXIF)

2. **VideoAnalyzer** - Uses FFprobe (part of FFmpeg)
   - Duration
   - Dimensions
   - Frame rate
   - Codec
   - Bitrate
   - Audio tracks

3. **AudioAnalyzer** - Uses FFprobe
   - Duration
   - Bitrate
   - Sample rate
   - Channels
   - Codec

### Usage in Rails

```ruby
# Analyze on attach
blob.analyze

# Access metadata
blob.metadata
# => {
#   "identified" => true,
#   "width" => 1920,
#   "height" => 1080,
#   "analyzed" => true
# }

# In views
image_tag blob.representation(resize_to_limit: [100, 100])
# Automatically uses metadata for srcset generation
```

### Automatic Analysis

Rails can analyze automatically on attachment:

```ruby
# config/application.rb
config.active_storage.analyze_after_upload = true

# When file is attached, analyzer runs in background
user.avatar.attach(file)
# -> Enqueues ActiveStorage::AnalyzeJob
```

---

## StorageEx Implementation Plan

### Phase 1: Core Analyzer Behavior

```elixir
defmodule StorageEx.Analyzer do
  @moduledoc """
  Behaviour for metadata extraction from blobs.
  """

  @type metadata :: %{
    width: integer() | nil,
    height: integer() | nil,
    format: String.t() | nil,
    size: integer() | nil,
    duration: float() | nil,
    analyzed: boolean()
  }

  @callback accept?(content_type :: String.t()) :: boolean()
  @callback analyze(input_path :: String.t()) :: {:ok, metadata()} | {:error, term()}
  @callback available?() :: boolean()
end
```

### Phase 2: Image Analyzer

```elixir
defmodule StorageEx.Analyzers.ImageAnalyzer do
  @behaviour StorageEx.Analyzer

  # Uses Image package (libvips)
  def accept?(content_type) do
    content_type in [
      "image/png",
      "image/jpeg",
      "image/gif",
      "image/webp",
      "image/tiff",
      "image/bmp"
    ]
  end

  def analyze(input_path) do
    with {:ok, image} <- Image.open(input_path) do
      {:ok, %{
        width: Image.width(image),
        height: Image.height(image),
        format: determine_format(image),
        size: File.stat!(input_path).size,
        analyzed: true
      }}
    end
  end

  def available?() do
    Code.ensure_loaded?(Image)
  end
end
```

### Phase 3: Video Analyzer

```elixir
defmodule StorageEx.Analyzers.VideoAnalyzer do
  @behaviour StorageEx.Analyzer

  # Uses FFprobe (part of FFmpeg)
  def accept?(content_type) do
    String.starts_with?(content_type, "video/")
  end

  def analyze(input_path) do
    # Run ffprobe to get JSON output
    case System.cmd("ffprobe", [
      "-v", "quiet",
      "-print_format", "json",
      "-show_format",
      "-show_streams",
      input_path
    ]) do
      {output, 0} ->
        parse_ffprobe_output(output)

      {error, _} ->
        {:error, "FFprobe failed: #{error}"}
    end
  end

  defp parse_ffprobe_output(json) do
    data = Jason.decode!(json)
    video_stream = find_video_stream(data["streams"])

    {:ok, %{
      width: video_stream["width"],
      height: video_stream["height"],
      duration: parse_duration(data["format"]["duration"]),
      format: data["format"]["format_name"],
      codec: video_stream["codec_name"],
      frame_rate: parse_frame_rate(video_stream["r_frame_rate"]),
      bitrate: String.to_integer(data["format"]["bit_rate"]),
      analyzed: true
    }}
  end

  def available?() do
    System.find_executable("ffprobe") != nil
  end
end
```

### Phase 4: Public API

```elixir
defmodule StorageEx do
  @doc """
  Analyze a blob and return metadata.

  ## Examples

      {:ok, metadata} = StorageEx.analyze("photo.jpg")
      # => %{width: 1920, height: 1080, format: "jpeg", size: 245678}

      {:ok, metadata} = StorageEx.analyze("video.mp4", content_type: "video/mp4")
      # => %{width: 1920, height: 1080, duration: 30.5, format: "mp4"}
  """
  def analyze(key, opts \\ []) do
    content_type = Keyword.fetch!(opts, :content_type)
    service_name = Keyword.get(opts, :service_name)

    with {:ok, analyzer} <- StorageEx.Analyzer.find_analyzer(content_type),
         {:ok, data} <- StorageEx.download(key, service_name: service_name),
         {:ok, metadata} <- analyze_data(analyzer, data) do
      {:ok, metadata}
    end
  end

  defp analyze_data(analyzer, data) do
    # Write to temp file
    # Analyze
    # Cleanup
    # Return metadata
  end
end
```

### Phase 5: Metadata Caching (Optional - Requires Storage)

```elixir
# Store metadata alongside blob
metadata_key = "#{blob_key}.metadata.json"

# Cache metadata
StorageEx.upload(metadata_key, Jason.encode!(metadata))

# Retrieve cached metadata
{:ok, cached} = StorageEx.download(metadata_key)
Jason.decode!(cached)
```

---

## Use Cases

### 1. Responsive Images

Generate srcset based on original dimensions:

```elixir
{:ok, metadata} = StorageEx.analyze("photo.jpg", content_type: "image/jpeg")

# Generate variants only up to original size
max_width = metadata.width

variants = [100, 300, 600, 1200]
  |> Enum.filter(&(&1 <= max_width))
  |> Enum.map(&[resize_to_limit: [&1, nil]])
```

### 2. Video Thumbnails

Extract thumbnail at specific percentage of duration:

```elixir
{:ok, metadata} = StorageEx.analyze("video.mp4", content_type: "video/mp4")

# Get thumbnail at 25% through video
time_position = metadata.duration * 0.25
time_string = format_time(time_position)

preview = StorageEx.preview("video.mp4",
  content_type: "video/mp4",
  time: time_string
)
```

### 3. Upload Validation

Validate dimensions before processing:

```elixir
{:ok, metadata} = StorageEx.analyze("photo.jpg", content_type: "image/jpeg")

cond do
  metadata.width < 800 ->
    {:error, "Image too small (minimum 800px width)"}

  metadata.width > 5000 ->
    {:error, "Image too large (maximum 5000px width)"}

  true ->
    {:ok, metadata}
end
```

### 4. UI Display

Show information to users:

```elixir
{:ok, metadata} = StorageEx.analyze("photo.jpg", content_type: "image/jpeg")

# In template
"#{metadata.width}×#{metadata.height} • #{format_size(metadata.size)}"
# => "1920×1080 • 245 KB"
```

### 5. Smart Cropping

Determine orientation for cropping:

```elixir
{:ok, metadata} = StorageEx.analyze("photo.jpg", content_type: "image/jpeg")

transformations = if metadata.width > metadata.height do
  # Landscape
  [resize_to_fill: [800, 600]]
else
  # Portrait
  [resize_to_fill: [600, 800]]
end

variant = StorageEx.variant("photo.jpg", transformations)
```

---

## Implementation Checklist

### Without Ecto (This PR or Future)

- [ ] Define `StorageEx.Analyzer` behavior
- [ ] Implement `StorageEx.Analyzers.ImageAnalyzer` (using Image package)
- [ ] Implement `StorageEx.Analyzers.VideoAnalyzer` (using FFprobe)
- [ ] Implement `StorageEx.Analyzer.find_analyzer/1`
- [ ] Add `StorageEx.analyze/2` public API
- [ ] Add configuration for available analyzers
- [ ] Write unit tests
- [ ] Write integration tests with real files
- [ ] Document in README

### With Ecto (Future - storage_ex_ecto)

- [ ] Add `metadata` JSONB field to blob schema
- [ ] Auto-analyze on attachment (optional, configurable)
- [ ] Background job for analysis (via Oban)
- [ ] Helper methods on attachment: `blob.metadata.width`
- [ ] Cache invalidation on blob update

---

## Configuration

```elixir
config :storage_ex,
  analyzers: [
    StorageEx.Analyzers.ImageAnalyzer,
    StorageEx.Analyzers.VideoAnalyzer,
    StorageEx.Analyzers.AudioAnalyzer
  ],
  # Analyze automatically (requires Ecto + background jobs)
  analyze_on_attach: false
```

---

## Comparison with Rails

| Feature              | Rails               | StorageEx (Proposed)           |
| -------------------- | ------------------- | ------------------------------ |
| **Image Analysis**   | ImageMagick/libvips | Image package (libvips)        |
| **Video Analysis**   | FFprobe             | FFprobe                        |
| **Analyzer Pattern** | Class inheritance   | Behavior (@behaviour)          |
| **Auto Analysis**    | Background job      | Manual (or background job)     |
| **Metadata Storage** | Database (JSONB)    | Storage (JSON files) or DB     |
| **API**              | `blob.analyze`      | `StorageEx.analyze(key, opts)` |
| **Caching**          | Database field      | Storage or database            |
| **Content Type**     | From blob record    | Passed as option               |

---

## Dependencies

### Required

- None (part of core StorageEx)

### Optional (for analyzers)

- `image ~> 0.37` - Image analysis (recommended)
- FFmpeg/FFprobe - Video/audio analysis
- `jason` - JSON parsing (already a dependency)

---

## Performance Considerations

1. **Analysis Cost**
   - Image: ~50-200ms (fast with libvips)
   - Video: ~500ms-2s (depends on file size)
   - Audio: ~100-500ms

2. **Caching**
   - Store metadata in storage or database
   - Invalidate on blob update
   - TTL optional for frequently changing content

3. **Background Processing**
   - Don't block requests
   - Use Oban or similar
   - Retry on failure

4. **Partial Downloads**
   - For cloud storage, download only headers if possible
   - Use byte range requests for large files
   - Some formats support metadata-only reads

---

## Example Implementation Timeline

### PR 1 (Foundation)

- Analyzer behavior
- ImageAnalyzer implementation
- Public API
- Tests

### PR 2 (Video Support)

- VideoAnalyzer implementation
- FFprobe integration
- Additional tests

### PR 3 (Caching)

- Metadata caching in storage
- Cache invalidation
- Performance optimization

### PR 4 (Ecto Integration)

- Add to storage_ex_ecto package
- Database metadata storage
- Background jobs
- Automatic analysis

---

## Notes

- Analysis should be **optional** and not block normal operations
- Users should be able to choose when to analyze (on upload, on demand, etc.)
- Metadata should be **cached** to avoid repeated analysis
- Different analyzers for different file types
- Graceful degradation when analyzer tools unavailable
