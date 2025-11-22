# Rails ActiveStorage vs StorageEx: Job System

## Overview

Rails ActiveStorage provides async job processing for heavy operations that shouldn't block web requests. This document outlines the job system design for StorageEx, with a pluggable adapter pattern that supports multiple job queue backends.

---

## Rails ActiveStorage Jobs

Rails provides these core async jobs:

### 1. AnalyzeJob

- **Purpose**: Async blob metadata extraction
- **When**: Called via `blob.analyze_later`
- **Queue**: `:analysis`
- **Retries**: 10 attempts with polynomial backoff for IntegrityError
- **Discards**: RecordNotFound

### 2. PurgeJob

- **Purpose**: Async blob deletion/cleanup
- **When**: Called via `blob.purge_later` or `attachment.purge_later`
- **Queue**: `:purge`
- **Retries**: 10 attempts with polynomial backoff for Deadlocks
- **Discards**: RecordNotFound

### 3. PreviewImageJob

- **Purpose**: Async preview generation + variants
- **When**: Called when accessing preview for first time
- **Queue**: `:preview_image`
- **Retries**: 10 attempts with polynomial backoff for IntegrityError
- **Discards**: RecordNotFound, UnrepresentableError

### 4. TransformJob

- **Purpose**: Async variant/representation processing
- **When**: Called when accessing variant for first time
- **Queue**: `:transform`
- **Retries**: 10 attempts with polynomial backoff for IntegrityError
- **Discards**: RecordNotFound, UnrepresentableError

### 5. MirrorJob

- **Purpose**: Async blob mirroring across services
- **When**: After direct upload to primary service
- **Queue**: `:mirror`
- **Retries**: 10 attempts with polynomial backoff for IntegrityError
- **Discards**: FileNotFoundError

---

## StorageEx Job Adapter Design

### Core Principle: Pluggable Architecture

StorageEx core provides the job operations, but delegates queue implementation to configurable adapters. This allows users to integrate with any job system (Oban, Broadway, Quantum, etc.) or run synchronously.

### Job Adapter Behaviour

```elixir
defmodule StorageEx.JobAdapter do
  @moduledoc """
  Behaviour for job queue adapters to handle StorageEx async operations.

  Adapters implement this behaviour to integrate StorageEx with job systems
  like Oban, Broadway, or custom solutions.
  """

  @doc """
  Enqueue blob analysis job.

  ## Parameters
  - `key`: Storage key of the blob
  - `content_type`: MIME type for analyzer selection
  - `opts`: Analysis options (service_name, analyzer options, etc.)

  ## Returns
  - `{:ok, job_id}` - Job successfully enqueued
  - `{:error, reason}` - Failed to enqueue
  """
  @callback enqueue_analyze(key :: String.t(), content_type :: String.t(), opts :: keyword()) ::
            {:ok, job_id :: term()} | {:error, term()}

  @doc """
  Enqueue blob purge/deletion job.

  ## Parameters
  - `key`: Storage key of the blob to delete
  - `service_name`: Service containing the blob
  - `opts`: Additional purge options
  """
  @callback enqueue_purge(key :: String.t(), service_name :: atom(), opts :: keyword()) ::
            {:ok, job_id :: term()} | {:error, term()}

  @doc """
  Enqueue preview generation job.

  ## Parameters
  - `key`: Storage key of the source blob
  - `preview_opts`: Preview generation options (content_type, format, etc.)
  """
  @callback enqueue_preview(key :: String.t(), preview_opts :: keyword()) ::
            {:ok, job_id :: term()} | {:error, term()}

  @doc """
  Enqueue variant transformation job.

  ## Parameters
  - `key`: Storage key of the source blob
  - `transformations`: Image transformation parameters
  - `opts`: Additional transform options (service_name, etc.)
  """
  @callback enqueue_transform(key :: String.t(), transformations :: keyword(), opts :: keyword()) ::
            {:ok, job_id :: term()} | {:error, term()}

  @doc """
  Enqueue blob mirroring job (for multi-service setups).

  ## Parameters
  - `source_key`: Key in the source service
  - `source_service`: Source service name
  - `dest_services`: List of destination service names
  - `opts`: Mirroring options
  """
  @callback enqueue_mirror(source_key :: String.t(), source_service :: atom(),
                          dest_services :: [atom()], opts :: keyword()) ::
            {:ok, job_id :: term()} | {:error, term()}
end
```

### Configuration

```elixir
# config/runtime.exs
config :storage_ex,
  # Optional: nil means sync-only mode
  job_adapter: StorageExOban,

  # Job-specific configuration
  job_queues: %{
    analyze: :storage_analysis,
    purge: :storage_cleanup,
    preview: :storage_preview,
    transform: :storage_transform,
    mirror: :storage_mirror
  },

  # Retry configuration
  job_retries: %{
    analyze: 10,
    purge: 5,
    preview: 10,
    transform: 10,
    mirror: 10
  }
```

### StorageEx Core Integration

```elixir
# In storage_ex core
defmodule StorageEx do

  # Sync versions (always available)
  def analyze(key, content_type, opts \\ [])
  def purge(key, opts \\ [])
  def preview(key, preview_opts)
  def transform(key, transformations, opts \\ [])

  # Async versions (require job adapter)
  def analyze_later(key, content_type, opts \\ []) do
    case StorageEx.Config.job_adapter() do
      nil -> {:error, :no_job_adapter}
      adapter -> adapter.enqueue_analyze(key, content_type, opts)
    end
  end

  def purge_later(key, opts \\ []) do
    service_name = get_service_name(opts)
    case StorageEx.Config.job_adapter() do
      nil -> {:error, :no_job_adapter}
      adapter -> adapter.enqueue_purge(key, service_name, opts)
    end
  end

  def preview_later(key, preview_opts) do
    case StorageEx.Config.job_adapter() do
      nil -> {:error, :no_job_adapter}
      adapter -> adapter.enqueue_preview(key, preview_opts)
    end
  end

  def transform_later(key, transformations, opts \\ []) do
    case StorageEx.Config.job_adapter() do
      nil -> {:error, :no_job_adapter}
      adapter -> adapter.enqueue_transform(key, transformations, opts)
    end
  end

  def mirror_later(source_key, source_service, dest_services, opts \\ []) do
    case StorageEx.Config.job_adapter() do
      nil -> {:error, :no_job_adapter}
      adapter -> adapter.enqueue_mirror(source_key, source_service, dest_services, opts)
    end
  end
end
```

---

## Oban Integration: StorageExOban Package

### Package Structure

```
storage_ex_oban/
├── lib/
│   ├── storage_ex_oban.ex          # Main adapter implementation
│   ├── storage_ex_oban/
│   │   ├── analyze_job.ex          # Analysis job worker
│   │   ├── purge_job.ex            # Purge job worker
│   │   ├── preview_job.ex          # Preview job worker
│   │   ├── transform_job.ex        # Transform job worker
│   │   ├── mirror_job.ex           # Mirror job worker
│   │   └── config.ex               # Oban configuration helpers
│   └── mix.exs
├── README.md
└── test/
```

### Main Adapter Implementation

```elixir
defmodule StorageExOban do
  @moduledoc """
  Oban adapter for StorageEx job processing.

  ## Setup

  1. Add to dependencies:
      {:storage_ex_oban, "~> 0.1.0"}

  2. Configure StorageEx:
      config :storage_ex, job_adapter: StorageExOban

  3. Add workers to Oban config:
      config :my_app, Oban,
        repo: MyApp.Repo,
        queues: [
          storage_analysis: 10,
          storage_cleanup: 5,
          storage_preview: 10,
          storage_transform: 20,
          storage_mirror: 5
        ]

  4. Add workers to supervision tree:
      # Usually automatic with Oban.Worker
  """

  @behaviour StorageEx.JobAdapter

  @impl true
  def enqueue_analyze(key, content_type, opts) do
    queue = StorageEx.Config.job_queue(:analyze, :storage_analysis)

    %{key: key, content_type: content_type, opts: opts}
    |> StorageExOban.AnalyzeJob.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job.id}
      error -> error
    end
  end

  @impl true
  def enqueue_purge(key, service_name, opts) do
    queue = StorageEx.Config.job_queue(:purge, :storage_cleanup)

    %{key: key, service_name: service_name, opts: opts}
    |> StorageExOban.PurgeJob.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job.id}
      error -> error
    end
  end

  @impl true
  def enqueue_preview(key, preview_opts) do
    queue = StorageEx.Config.job_queue(:preview, :storage_preview)

    %{key: key, preview_opts: preview_opts}
    |> StorageExOban.PreviewJob.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job.id}
      error -> error
    end
  end

  @impl true
  def enqueue_transform(key, transformations, opts) do
    queue = StorageEx.Config.job_queue(:transform, :storage_transform)

    %{key: key, transformations: transformations, opts: opts}
    |> StorageExOban.TransformJob.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job.id}
      error -> error
    end
  end

  @impl true
  def enqueue_mirror(source_key, source_service, dest_services, opts) do
    queue = StorageEx.Config.job_queue(:mirror, :storage_mirror)

    %{
      source_key: source_key,
      source_service: source_service,
      dest_services: dest_services,
      opts: opts
    }
    |> StorageExOban.MirrorJob.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job.id}
      error -> error
    end
  end
end
```

### Job Worker Example

```elixir
defmodule StorageExOban.AnalyzeJob do
  @moduledoc """
  Oban worker for analyzing blobs and extracting metadata.
  """

  use Oban.Worker,
    queue: :storage_analysis,
    max_attempts: 10

  @impl Oban.Worker
  def perform(%Oban.Job{
    args: %{
      "key" => key,
      "content_type" => content_type,
      "opts" => opts
    }
  }) do
    case StorageEx.analyze(key, content_type, opts) do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Configuration Helpers

```elixir
defmodule StorageExOban.Config do
  @moduledoc """
  Configuration helpers for StorageExOban.
  """

  @doc """
  Returns recommended Oban queue configuration for StorageEx.
  """
  def recommended_queues(opts \\ []) do
    base_queues = [
      storage_analysis: 10,   # CPU intensive, moderate concurrency
      storage_cleanup: 5,     # I/O intensive, low concurrency
      storage_preview: 10,    # CPU intensive, moderate concurrency
      storage_transform: 20,  # CPU intensive, higher concurrency
      storage_mirror: 5       # Network intensive, low concurrency
    ]

    Keyword.merge(base_queues, opts)
  end

  @doc """
  Adds StorageEx workers to your Oban configuration.
  """
  def add_workers(oban_config) do
    workers = [
      StorageExOban.AnalyzeJob,
      StorageExOban.PurgeJob,
      StorageExOban.PreviewJob,
      StorageExOban.TransformJob,
      StorageExOban.MirrorJob
    ]

    # Oban automatically discovers workers, but this can be used
    # for explicit configuration if needed
    oban_config
  end
end
```

---

## How Oban Works & Integration Strategy

### Oban Fundamentals

**How Oban Works:**

1. **Workers are modules** that implement `Oban.Worker` behaviour
2. **Jobs are structs** with args that get serialized to the database
3. **Queues are configured** in the Oban config with concurrency limits
4. **Workers are auto-discovered** by Oban (no explicit registration needed)
5. **Jobs persist** in PostgreSQL tables for reliability

**Key Oban Features:**

- Automatic worker discovery (no manual registration)
- Built-in retry logic with backoff strategies
- Queue-based job processing with configurable concurrency
- Web dashboard for monitoring
- Cron-like scheduled jobs
- Job uniqueness and deduplication

### Making Integration Super Easy

The StorageExOban package is designed for **zero-friction integration**:

#### What Users Need to Do (Minimal):

```elixir
# 1. Add dependency to mix.exs
{:storage_ex_oban, "~> 0.1.0"}

# 2. Configure StorageEx job adapter
config :storage_ex, job_adapter: StorageExOban

# 3. Add StorageEx queues to existing Oban config
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: StorageExOban.Config.recommended_queues()
```

#### What StorageExOban Handles Automatically:

- ✅ **All job workers** - Pre-built and auto-discovered
- ✅ **Job enqueueing** - Proper error handling and serialization
- ✅ **Sensible defaults** - Queue names, concurrency, retry policies
- ✅ **Error handling** - Appropriate retry/discard strategies
- ✅ **Integration** - Works with existing Oban setups

#### Mix Task for Even Easier Setup:

```bash
mix storage_ex_oban.install
```

This helper would:

1. Add dependency to `mix.exs`
2. Update Oban configuration with recommended queues
3. Show configuration examples and next steps
4. Run `mix deps.get` automatically

#### Advanced Configuration (Optional):

```elixir
# Custom queue mapping
config :storage_ex,
  job_queues: %{
    analyze: :high_priority_analysis,    # Custom queue names
    transform: :image_processing,
    purge: :cleanup,
    preview: :media_processing,
    mirror: :replication
  }

# Custom Oban queues with priorities
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    # High priority
    high_priority_analysis: 20,
    image_processing: 30,

    # Normal priority
    media_processing: 10,
    cleanup: 5,

    # Low priority background
    replication: 2
  ]
```

### Benefits for Users

1. **No Worker Registration** - Oban automatically discovers StorageEx workers
2. **No Queue Setup Complexity** - We provide sensible defaults
3. **No Job Serialization Concerns** - StorageExOban handles data flow
4. **Works with Existing Oban** - Just adds queues, doesn't interfere with existing jobs
5. **Gradual Adoption** - Can use sync mode first, add async jobs later
6. **Monitoring Included** - StorageEx jobs appear in Oban dashboard
7. **Production Ready** - Built-in retry policies and error handling

---

## User Integration Guide

### 1. Basic Setup (3 Steps)

```elixir
# Step 1: Add to mix.exs dependencies
def deps do
  [
    {:storage_ex, "~> 0.1.0"},
    {:storage_ex_oban, "~> 0.1.0"},  # <-- Add this line
    {:oban, "~> 2.15"}
  ]
end

# Step 2: Configure StorageEx job adapter
config :storage_ex,
  job_adapter: StorageExOban  # <-- Add this line

# Step 3: Add StorageEx queues to existing Oban config
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: StorageExOban.Config.recommended_queues()  # <-- Add this line
```

### 2. Usage Examples

```elixir
# Sync processing (no jobs required)
{:ok, metadata} = StorageEx.analyze("image.jpg", "image/jpeg")

# Async processing (automatically uses Oban)
{:ok, job_id} = StorageEx.analyze_later("large_video.mp4", "video/mp4")

# Check job status using Oban
job = Oban.Job.get(job_id)
# Monitor in Oban dashboard at /oban
```

### 3. Custom Queue Configuration

```elixir
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    # High priority queues
    storage_analysis_priority: 20,
    storage_transform_priority: 30,

    # Normal queues
    storage_analysis: 10,
    storage_transform: 20,
    storage_cleanup: 5,

    # Low priority background tasks
    storage_mirror: 2
  ]

# Map StorageEx operations to custom queues
config :storage_ex,
  job_queues: %{
    analyze: :storage_analysis_priority,  # High priority analysis
    transform: :storage_transform_priority,
    purge: :storage_cleanup,
    preview: :storage_analysis,
    mirror: :storage_mirror
  }
```

---

## Benefits of This Design

### 1. **Zero Coupling**: StorageEx core has no job system dependencies

### 2. **Pluggable**: Easy to create adapters for other job systems

### 3. **Optional**: Works in sync mode without any job system

### 4. **Configurable**: Users control queue names, priorities, retry policies

### 5. **Rails Compatible**: Same job types and patterns as ActiveStorage

### 6. **Easy Integration**: StorageExOban package handles all Oban complexity

---

## Future Job Adapters

The same pattern can be used for other job systems:

- **StorageExBroadway** - For Broadway/GenStage workflows
- **StorageExQuantum** - For Quantum cron job integration
- **StorageExSwoosh** - For email-based async processing
- **StorageExCustom** - For custom job queue implementations

---

## Implementation Phases

### Phase 1: Foundation (Current)

- Core job adapter behaviour
- Configuration integration
- Sync operation support

### Phase 2: Oban Integration

- StorageExOban package
- Complete job implementations
- Documentation and testing

### Phase 3: Additional Adapters

- Community-driven adapters for other job systems
- Advanced features (job chaining, priorities, etc.)
