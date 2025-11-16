defmodule StorageEx.Config do
  @moduledoc """
  Central configuration for StorageEx.

  ## Setup

  In your `runtime.exs`:

      config :storage_ex,
        service: :local,
        endpoint: MyAppWeb.Endpoint,
        services: %{
          local: %{
            service: StorageEx.Services.DiskService,
            configuration: %{root: "priv/storage"}
          }
        }

  For S3/cloud storage:

      config :storage_ex,
        service: :my_public_bucket,
        endpoint: MyAppWeb.Endpoint,
        services: %{
          my_public_bucket: %{
            service: StorageExS3.Service,
            configuration: %{
              provider: :cloudflare_r2,
              account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID"),
              bucket: System.fetch_env!("R2_BUCKET"),
              access_key_id: System.fetch_env!("R2_ACCESS_KEY_ID"),
              secret_access_key: System.fetch_env!("R2_SECRET_ACCESS_KEY")
            }
          }
        }

  If no services are configured, a local service will be added automatically:

      filesystem_disk: %{
        service: StorageEx.Services.DiskService,
        configuration: %{root: "priv/storage"}
      }

  ## Configuration Options

    * `:service` - Default service name to use
    * `:endpoint` - Phoenix endpoint module for URL generation (required for disk service URLs)
    * `:services` - Map of service configurations
    * `:token_salt` - Salt for signing tokens (default: "storage_ex_disk_service")
    * `:variant_processor` - Transformer for image variants (default: :vips)

  ## Variant Processing

  Configure the image transformer for variants:

      # Use Vips (default, recommended)
      config :storage_ex, variant_processor: :vips

      # Use custom transformer
      config :storage_ex, variant_processor: MyApp.CustomTransformer

      # Disable variants completely
      config :storage_ex, variant_processor: :disabled
  """

  @key {:storage_ex, :config}
  @default_local_service StorageEx.Services.DiskService

  # -- Public API -------------------------------------------------------------

  def default_service, do: get_config().service
  def services, do: get_config().services
  def endpoint, do: get_config()[:endpoint]

  @doc """
  Returns the configured variant transformer module.

  Checks if the transformer is available and falls back to NullTransformer
  if dependencies are missing.

  ## Examples

      # Returns StorageEx.Transformers.Vips if configured and available
      StorageEx.Config.variant_transformer()

      # Returns StorageEx.Transformers.Null if disabled or unavailable
      StorageEx.Config.variant_transformer()
  """
  def variant_transformer do
    case Application.get_env(:storage_ex, :variant_processor, :vips) do
      :disabled ->
        StorageEx.Transformers.Null

      :vips ->
        check_transformer(StorageEx.Transformers.Vips, """
        Using Vips to process variants requires the Image package (which uses libvips).

        To install:
        1. Add to mix.exs: {:image, "~> 0.37"}
        2. (Optional) Install libvips for full format support:
           - macOS: brew install vips
           - Ubuntu: apt-get install libvips-dev
           - Alpine: apk add vips-dev

        Note: The Image package comes with pre-compiled binaries that work great
        for development. For production with full format support, install libvips
        and set VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS.

        Or set config :storage_ex, variant_processor: :disabled
        """)

      module when is_atom(module) ->
        check_transformer(module, "Custom transformer #{inspect(module)} is not available")
    end
  end

  @doc """
  Returns the list of configured previewers.

  Previewers are tried in order until one accepts the content type.
  Default previewers are:
    - StorageEx.Previewers.PopplerPDFPreviewer
    - StorageEx.Previewers.MuPDFPreviewer
    - StorageEx.Previewers.VideoPreviewer

  ## Configuration

      config :storage_ex,
        previewers: [
          MyApp.CustomPreviewer,
          StorageEx.Previewers.PopplerPDFPreviewer,
          StorageEx.Previewers.VideoPreviewer
        ]
  """
  def previewers do
    Application.get_env(:storage_ex, :previewers, default_previewers())
  end

  defp default_previewers do
    [
      StorageEx.Previewers.PopplerPDFPreviewer,
      StorageEx.Previewers.MuPDFPreviewer,
      StorageEx.Previewers.VideoPreviewer
    ]
  end

  def get_service!(nil), do: get_service!(default_service())

  def get_service!(name) do
    atom =
      cond do
        is_atom(name) ->
          name

        is_binary(name) ->
          try do
            String.to_existing_atom(name)
          rescue
            ArgumentError -> raise ArgumentError, "Unknown storage service #{inspect(name)}"
          end

        true ->
          raise ArgumentError, "Service name must be atom or string, got: #{inspect(name)}"
      end

    case services()[atom] do
      nil -> raise ArgumentError, "Unknown service #{inspect(name)}"
      service -> service
    end
  end

  def reload! do
    :persistent_term.erase(@key)
    :ok
  end

  # -- Internal helpers -------------------------------------------------------

  defp get_config do
    case :persistent_term.get(@key, :not_set) do
      :not_set ->
        cfg =
          Application.get_all_env(:storage_ex)
          |> normalize_config()
          |> build_services()

        :persistent_term.put(@key, cfg)
        cfg

      cfg ->
        cfg
    end
  end

  def fetch_required_option(config, key) do
    case Map.fetch(config, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _} -> {:error, key}
      :error -> {:error, key}
    end
  end

  # Handle both keyword lists (from Application.get_all_env/1) and maps
  defp normalize_config(opts) when is_list(opts) do
    opts |> Enum.into(%{}) |> normalize_config()
  end

  defp normalize_config(opts) when is_map(opts) do
    services = Map.get(opts, :services, %{})

    services =
      if map_size(services) > 0 do
        services
      else
        %{
          filesystem_disk: %{
            service: @default_local_service,
            configuration: %{root: "priv/storage"}
          }
        }
      end

    %{
      services: services,
      service: Map.get(opts, :service, :local),
      endpoint: Map.get(opts, :endpoint)
    }
  end

  defp build_services(%{services: configs} = cfg) do
    services =
      configs
      |> Enum.map(fn {name, %{service: mod, configuration: config}} ->
        case mod.new(config) do
          %^mod{} = service ->
            validate_behaviour!(mod)
            {name, service}

          {:error, reason} ->
            IO.warn("Skipping misconfigured service #{name}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    %{cfg | services: services}
  end

  # --- Behaviour Validation --------------------------------------------------

  defp validate_behaviour!(mod) do
    behaviours = mod.module_info(:attributes)[:behaviour] || []

    unless StorageEx.Service in behaviours do
      IO.warn("""
      Warning: #{inspect(mod)} does not declare @behaviour StorageEx.Service.
      Ensure the module implements all required callbacks.
      """)
    end

    :ok
  end

  # --- Transformer Selection -------------------------------------------------

  require Logger

  defp check_transformer(transformer, warning_message) do
    if Code.ensure_loaded?(transformer) and transformer.available?() do
      transformer
    else
      Logger.warning("""
      StorageEx Transformer Unavailable

      #{warning_message}

      Falling back to NullTransformer (variants disabled).
      """)

      StorageEx.Transformers.Null
    end
  end
end
