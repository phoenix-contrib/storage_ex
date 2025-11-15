defmodule StorageExS3.Provider do
  @moduledoc false

  alias StorageEx.Config

  @enforce_keys [:bucket, :host, :provider]
  defstruct [:bucket, :host, :scheme, :port, :region, :assets_domain, :provider]

  @providers %{
    aws_s3: StorageExS3.Providers.AWSS3,
    cloudflare_r2: StorageExS3.Providers.CloudflareR2
  }
  @doc "Supported provider names"
  @type provider_name ::
          unquote(Enum.reduce(Map.keys(@providers), fn k, acc -> {:|, [], [k, acc]} end))

  @type t :: %__MODULE__{
          bucket: String.t(),
          host: String.t(),
          scheme: String.t(),
          port: pos_integer(),
          region: String.t() | nil,
          assets_domain: String.t() | nil,
          provider: provider_name()
        }

  def build(provider, config) do
    case Map.fetch(@providers, provider) do
      {:ok, mod} -> mod.build(config)
      :error -> {:error, {:unknown_provider, provider}}
    end
  end

  @spec build_common(provider: provider_name(), host: String.t(), config: map()) ::
          {:ok, t()} | {:error, term()}
  def build_common(opts) do
    provider = Keyword.fetch!(opts, :provider)
    host = Keyword.fetch!(opts, :host)
    config = Keyword.fetch!(opts, :config)

    with {:ok, bucket} <- Config.fetch_required_option(config, :bucket) do
      {:ok,
       %__MODULE__{
         bucket: bucket,
         host: host,
         scheme: Map.get(config, :scheme, "https://"),
         port: Map.get(config, :port, 443),
         region: Map.get(config, :region),
         assets_domain: Map.get(config, :assets_domain),
         provider: provider
       }}
    end
  end

  @doc "Convert to ExAws options."
  def to_opts(%__MODULE__{scheme: scheme, host: host, port: port}) do
    [scheme: scheme, host: host, port: port]
  end

  @doc "Delegate URL generation to provider implementation."
  def url(%__MODULE__{provider: provider} = cfg, key) do
    mod = Map.fetch!(@providers, provider)
    mod.url(cfg, key)
  end
end
