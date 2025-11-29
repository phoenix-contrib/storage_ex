# Rails ActiveStorage vs StorageEx: Analyzers

## Overview

Rails ActiveStorage provides analyzers to extract metadata from uploaded files (images, videos, audio, PDFs). This document tracks StorageEx's implementation progress toward full analyzer parity with Rails.

---

## Rails ActiveStorage Analyzers

### Base Analyzer Class (`lib/active_storage/analyzer.rb`)

**Purpose**: Abstract base class for all analyzers with common functionality.

**Key Methods**:
- `self.accept?(blob)` - Class method to determine if analyzer can handle the blob
- `self.analyze_later?` - Whether analysis should be queued (default: true)
- `initialize(blob)` - Initialize with blob reference
- `metadata` - Abstract method to return metadata hash
- `download_blob_to_tempfile(&block)` - Download blob for processing
- `instrument(analyzer, &block)` - Telemetry wrapper
- `logger` - Access to ActiveStorage logger
- `tmpdir` - Temporary directory for processing

### Built-in Analyzers

#### 1. ImageAnalyzer (`lib/active_storage/analyzer/image_analyzer.rb`)
- **Purpose**: Extract width/height from image files
- **Accepts**: `blob.image?` (image/* content types)
- **Metadata**: `{width: 4104, height: 2736}`
- **EXIF Handling**: Swaps dimensions for 90°/270° rotated images
- **Implementations**: Vips and ImageMagick subclasses

##### ImageAnalyzer::Vips (`lib/active_storage/analyzer/image_analyzer/vips.rb`)
- **Dependency**: `ruby-vips` gem + libvips system library
- **Condition**: Only when `ActiveStorage.variant_processor == :vips`
- **Error Handling**: Graceful fallback with warnings
- **EXIF**: Reads orientation from `exif-ifd0-Orientation`

##### ImageAnalyzer::ImageMagick (`lib/active_storage/analyzer/image_analyzer/image_magick.rb`)
- **Dependency**: `mini_magick` gem + ImageMagick system library  
- **Condition**: Only when `ActiveStorage.variant_processor == :mini_magick`
- **Error Handling**: Graceful fallback with warnings
- **EXIF**: Reads orientation via `image["%[orientation]"]`

#### 2. VideoAnalyzer (`lib/active_storage/analyzer/video_analyzer.rb`)
- **Purpose**: Extract video metadata using FFprobe
- **Accepts**: `blob.video?` (video/* content types)
- **Dependencies**: FFmpeg system library (`ffprobe` command)
- **Metadata**: 
  ```ruby
  {
    width: 640.0, height: 480.0, duration: 5.0, angle: 0,
    display_aspect_ratio: [4, 3], audio: true, video: true
  }
  ```
- **Rotation Handling**: Swaps width/height for 90°/270° angles
- **Error Handling**: Returns empty hash if FFprobe unavailable

#### 3. AudioAnalyzer (`lib/active_storage/analyzer/audio_analyzer.rb`)  
- **Purpose**: Extract audio metadata using FFprobe
- **Accepts**: `blob.audio?` (audio/* content types)
- **Dependencies**: FFmpeg system library (`ffprobe` command)
- **Metadata**:
  ```ruby
  {
    duration: 5.0, bit_rate: 320340, sample_rate: 44100,
    tags: { encoder: "Lavc57.64", ... }
  }
  ```

#### 4. NullAnalyzer (`lib/active_storage/analyzer/null_analyzer.rb`)
- **Purpose**: Fallback analyzer for unsupported files
- **Accepts**: Always `true` (accepts everything)
- **Analyze Later**: Always `false` (runs immediately)  
- **Metadata**: Always empty hash `{}`

### Analyzer Selection Logic

```ruby
# Rails automatically tries analyzers in order:
analyzers = [
  ActiveStorage::Analyzer::ImageAnalyzer::Vips,        # If vips available
  ActiveStorage::Analyzer::ImageAnalyzer::ImageMagick, # If mini_magick available  
  ActiveStorage::Analyzer::VideoAnalyzer,              # If ffprobe available
  ActiveStorage::Analyzer::AudioAnalyzer,              # If ffprobe available
  ActiveStorage::Analyzer::NullAnalyzer                # Always available
]

# First analyzer that returns `accept?(blob)` is used
```

---

## StorageEx Implementation Status

### ✅ Implemented (Current)

#### 1. Core Analyzer Behaviour (`lib/analyzer.ex`)
- ✅ **`@callback accept?/1`** - Content type acceptance check
- ✅ **`@callback analyze_later?/0`** - Async analysis flag  
- ✅ **`@callback metadata/2`** - Extract metadata from path + content_type
- ✅ **`@callback available?/0`** - Dependency availability check
- ✅ **`find_analyzer/1`** - Select analyzer for content type
- ✅ **`analyze/3`** - Main analysis function with service integration
- ✅ **Streaming Download** - Downloads files in chunks for analysis
- ✅ **Telemetry Integration** - Built-in telemetry events
- ✅ **Error Handling** - Proper `{:ok, metadata} | {:error, reason}`

#### 2. Image Analyzer (`lib/analyzers/image_analyzer.ex`)
- ✅ **Vips Integration** - Uses Image package (libvips wrapper)
- ✅ **Content Type Support** - Accepts all `image/*` types
- ✅ **Metadata Extraction** - Returns `%{width: w, height: h}` map
- ✅ **EXIF Rotation** - Handles rotated images properly
- ✅ **Availability Check** - Graceful fallback when Image unavailable
- ✅ **Comprehensive Tests** - Real image files with fixtures

#### 3. Video Analyzer (`lib/analyzers/video_analyzer.ex`)
- ✅ **FFprobe Integration** - Shell out to `ffprobe` command
- ✅ **Video Metadata** - Width, height, duration, rotation, streams
- ✅ **Content Type Support** - Accept `video/*` types
- ✅ **Error Handling** - Graceful fallback when FFmpeg unavailable
- ✅ **Rotation Handling** - Swaps width/height for 90°/270° angles
- ✅ **Stream Detection** - Identifies audio/video stream presence
- ✅ **Comprehensive Tests** - Real video files with fixtures

#### 4. Audio Analyzer (`lib/analyzers/audio_analyzer.ex`)  
- ✅ **FFprobe Integration** - Shell out to `ffprobe` command
- ✅ **Audio Metadata** - Duration, bit rate, sample rate, tags
- ✅ **Content Type Support** - Accept `audio/*` types
- ✅ **Error Handling** - Graceful fallback when FFmpeg unavailable
- ✅ **Tag Extraction** - Reads metadata tags from audio files
- ✅ **Comprehensive Tests** - Real audio files with fixtures

#### 5. Null Analyzer (`lib/analyzers/null_analyzer.ex`)
- ✅ **Universal Accept** - Accepts all content types
- ✅ **Immediate Processing** - `analyze_later?/0` returns `false`
- ✅ **Empty Metadata** - Returns `%{}` 
- ✅ **Always Available** - `available?/0` returns `true`

#### 6. Configuration (`lib/config.ex`)
- ✅ **`analyzers/0`** - Returns configured analyzer list
- ✅ **Default List** - `[ImageAnalyzer, VideoAnalyzer, AudioAnalyzer, NullAnalyzer]`
- ✅ **Custom Configuration** - Via `:analyzers` app config
- ✅ **Same Pattern** - Follows existing `previewers/0` approach

#### 7. Public API (`lib/storage_ex.ex`)
- ✅ **`analyze/3`** - Synchronous metadata extraction
- ✅ **Service Integration** - Works with configured services
- ✅ **Streaming Support** - Uses streaming download for large files
- ✅ **Telemetry Integration** - Automatic analysis event emission

### 🚧 Partially Implemented

#### 1. PDF Analyzer (Extension)
- ✅ **System Tool Integration** - Shell out to `pdfinfo` or `mutool`
- ✅ **PDF Metadata** - Page count, dimensions, document info
- ✅ **Content Type Support** - Accept `application/pdf`
- ✅ **Error Handling** - Graceful fallback when tools unavailable

### ❌ Not Yet Implemented

#### 2. Async Analysis (Job Integration)
- ❌ **`analyze_later/3`** - Queue analysis jobs
- ❌ **Job Adapter Integration** - Use configured job system
- ❌ **Background Processing** - Handle analysis in workers

---

## Comparison with Rails

| Feature | Rails | StorageEx Status |
|---------|-------|------------------|
| **Base Analyzer** | Abstract class | ✅ Behaviour |
| **Image Analysis** | Vips + ImageMagick | ✅ Vips only |
| **EXIF Rotation** | ✅ Both backends | ✅ Vips |
| **Video Analysis** | ✅ FFprobe | ✅ FFprobe |
| **Audio Analysis** | ✅ FFprobe | ✅ FFprobe |
| **Null Analyzer** | ✅ Fallback | ✅ Implemented |
| **Auto Selection** | ✅ First accepting | ✅ Implemented |
| **Dependency Checks** | ✅ LoadError rescue | ✅ `available?/0` |
| **Async Analysis** | ✅ Jobs | ❌ Not implemented |
| **Error Handling** | Exceptions | ✅ Result tuples |
| **Telemetry** | ✅ Notifications | ✅ Built-in telemetry |
| **Streaming Downloads** | ✅ Built-in | ✅ Chunk streaming |
| **Temp File Handling** | ✅ Built-in | ✅ Automatic cleanup |

---

## Key Design Decisions

### 1. **Behaviour over Inheritance**
- **Rails**: Uses class inheritance with abstract base
- **StorageEx**: Uses Elixir behaviours for contracts

### 2. **Vips Only for Images**  
- **Rails**: Supports both Vips and ImageMagick
- **StorageEx**: Only Vips via Image package (simpler dependencies)

### 3. **Content-Type Based**
- **Rails**: Analyzers receive blob objects
- **StorageEx**: Analyzers receive content_type + file_path

### 4. **Availability Checking**
- **Rails**: Catches LoadError at runtime
- **StorageEx**: Explicit `available?/0` callback

### 5. **Error Handling**
- **Rails**: Raises exceptions
- **StorageEx**: Returns `{:ok, result} | {:error, reason}` tuples

---

## Telemetry Integration

### Rails ActiveStorage Instrumentation

Rails uses `ActiveSupport::Notifications` for analyzer telemetry:

```ruby
# In Rails analyzers
def metadata
  instrument("video") do
    # Analysis work here
  end
end

# Emitted event: "analyze.active_storage" 
# Metadata: { analyzer: "video" }
```

### StorageEx Telemetry

StorageEx uses the existing telemetry system for analyzer operations, following the same pattern as other operations.

#### Analyzer Events

**Event Pattern**: `[:storage_ex, :analyze, event_type]`

- **`:start`** - Emitted when analysis begins
- **`:stop`** - Emitted when analysis completes successfully  
- **`:exception`** - Emitted when analysis fails

#### Event Metadata

All analyzer events include:

```elixir
%{
  analyzer: StorageEx.Analyzers.ImageAnalyzer,  # The analyzer module used
  content_type: "image/jpeg",                   # Content type being analyzed
  key: "photos/image.jpg",                      # Storage key
  service: StorageEx.Services.DiskService,      # Storage service
  args: [key, content_type, opts]               # Original function arguments
}
```

#### Usage Examples

**Basic Logging:**
```elixir
defmodule MyApp.AnalyzerTelemetry do
  require Logger

  def attach do
    events = [
      [:storage_ex, :analyze, :start],
      [:storage_ex, :analyze, :stop], 
      [:storage_ex, :analyze, :exception]
    ]

    :telemetry.attach_many(
      "analyzer-telemetry",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:storage_ex, :analyze, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    Logger.info("Analysis completed",
      analyzer: inspect(metadata.analyzer),
      content_type: metadata.content_type,
      key: metadata.key,
      duration_ms: duration_ms
    )
  end

  def handle_event([:storage_ex, :analyze, :exception], measurements, metadata, _config) do
    Logger.error("Analysis failed",
      analyzer: inspect(metadata.analyzer), 
      content_type: metadata.content_type,
      error: Exception.message(metadata.reason)
    )
  end
end
```

**Metrics Collection:**
```elixir
# In your telemetry metrics
def metrics do
  [
    # Track analysis counts by analyzer and content type
    counter("storage_ex.analyze.stop.count",
      tags: [:analyzer, :content_type]
    ),

    # Track analysis duration
    distribution("storage_ex.analyze.stop.duration", 
      unit: {:native, :millisecond},
      tags: [:analyzer, :content_type]
    ),

    # Track analysis errors
    counter("storage_ex.analyze.exception.count",
      tags: [:analyzer, :content_type, :error_type]
    )
  ]
end
```

**LiveDashboard Integration:**
```elixir
# View analyzer performance in Phoenix LiveDashboard
summary("storage_ex.analyze.stop.duration",
  unit: {:native, :millisecond},
  tags: [:analyzer],
  tag_values: &extract_analyzer_name/1
)

defp extract_analyzer_name(metadata) do
  analyzer_name = 
    metadata.analyzer
    |> Module.split()
    |> List.last()
    |> String.replace("Analyzer", "")
    |> String.downcase()
    
  %{analyzer: analyzer_name}
end
```

#### Comparison with Rails

| Feature | Rails | StorageEx |
|---------|-------|-----------|
| **Event System** | ActiveSupport::Notifications | :telemetry |  
| **Event Names** | `"analyze.active_storage"` | `[:storage_ex, :analyze, :stop]` |
| **Metadata** | `{analyzer: "video"}` | `%{analyzer: Module, content_type: String, ...}` |
| **Duration** | Automatic via `instrument` | Automatic via telemetry |
| **Error Events** | Exception propagation | `:exception` events |
| **Integration** | Rails ecosystem | Phoenix/Elixir ecosystem |

---

## Usage Examples

### Current (Sync Analysis)

```elixir
# Analyze uploaded image
{:ok, metadata} = StorageEx.analyze("photos/image.jpg", "image/jpeg")
# => {:ok, %{width: 1920, height: 1080}}

# Analyze video file
{:ok, metadata} = StorageEx.analyze("videos/movie.mp4", "video/mp4")
# => {:ok, %{width: 1920, height: 1080, duration: 125.5, angle: 0, 
#           display_aspect_ratio: [16, 9], audio: true, video: true}}

# Analyze audio file
{:ok, metadata} = StorageEx.analyze("music/song.mp3", "audio/mpeg")
# => {:ok, %{duration: 245.0, bit_rate: 320000, sample_rate: 44100,
#           tags: %{title: "Song Title", artist: "Artist Name"}}}

# Find analyzer for content type
{:ok, analyzer} = StorageEx.Analyzer.find_analyzer("image/png") 
# => {:ok, StorageEx.Analyzers.ImageAnalyzer}

# Check if content type has analyzer
case StorageEx.Analyzer.find_analyzer("video/mp4") do
  {:ok, analyzer} -> "Can analyze videos with FFprobe"
  {:error, :no_analyzer} -> "No analyzer available"
end
```

### Future (Async Analysis)

```elixir
# Queue analysis job (when implemented)
{:ok, job_id} = StorageEx.analyze_later("video.mp4", "video/mp4")

# PDF metadata (when implemented)
{:ok, metadata} = StorageEx.analyze("document.pdf", "application/pdf") 
# => {:ok, %{pages: 15, width: 595, height: 842}}
```

---

## Configuration

### Current Configuration

```elixir
config :storage_ex,
  analyzers: [
    StorageEx.Analyzers.ImageAnalyzer,
    StorageEx.Analyzers.VideoAnalyzer,
    StorageEx.Analyzers.AudioAnalyzer,
    StorageEx.Analyzers.NullAnalyzer  
  ]
```

### Future Configuration

```elixir  
config :storage_ex,
  analyzers: [
    MyApp.CustomAnalyzer,
    StorageEx.Analyzers.ImageAnalyzer,
    StorageEx.Analyzers.VideoAnalyzer,
    StorageEx.Analyzers.AudioAnalyzer, 
    StorageEx.Analyzers.PDFAnalyzer,
    StorageEx.Analyzers.NullAnalyzer
  ]
```

---

## Implementation Roadmap

### Phase 1: Foundation ✅
- [x] Core analyzer behaviour
- [x] Image analyzer with Vips
- [x] Null analyzer fallback
- [x] Configuration integration
- [x] Public API integration

### Phase 2: Media Analyzers ✅
- [x] Video analyzer with FFprobe
- [x] Audio analyzer with FFprobe  
- [x] Comprehensive error handling
- [x] System dependency detection
- [x] Streaming file downloads
- [x] Real media file testing

### Phase 3: Document Analyzers  
- [ ] PDF analyzer with system tools
- [ ] Advanced metadata extraction
- [ ] Multiple tool support (pdfinfo, mutool)

### Phase 4: Async Processing
- [ ] Job adapter integration
- [ ] `analyze_later/3` functions
- [ ] Background job processing
- [ ] Queue configuration

### Phase 5: Advanced Features
- [x] Telemetry integration (using existing StorageEx.Telemetry)
- [ ] Custom analyzer helpers
- [ ] Performance optimization
- [ ] Comprehensive testing

---

## Testing Strategy

### Current Tests
- ✅ **Unit tests** for each analyzer with sample content types
- ✅ **Integration tests** with StorageEx public API  
- ✅ **Availability testing** with missing dependencies
- ✅ **Error handling** for various failure scenarios
- ✅ **Media file testing** with real video/audio files from Rails fixtures
- ✅ **Streaming tests** with chunked file downloads
- ✅ **Telemetry testing** with proper event handling
- ✅ **File cleanup** verification for temporary files

### Future Tests  
- [ ] **PDF processing** with various document types
- [ ] **Performance testing** with very large files (GB+)
- [ ] **Job integration** testing with async processing

---

## Rails Compatibility Notes

StorageEx analyzers maintain conceptual compatibility with Rails:

- **Same metadata format** - Returns similar hash structures
- **Same selection logic** - First accepting analyzer wins
- **Same error handling** - Graceful degradation when tools unavailable
- **Same extensibility** - Custom analyzers can be added

Key differences are idiomatic Elixir patterns (behaviours, result tuples) rather than functional differences.