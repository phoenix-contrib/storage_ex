defmodule StorageExS3.Providers.CloudflareR2 do
  @moduledoc false
  alias StorageEx.Config
  alias StorageExS3.Provider

  @doc """
  Build a Cloudflare R2 provider config.
  Requires `:bucket` and `:account_id`.

  By default, URLs are path-based (`https://<host>/<bucket>/<key>`).
  If `assets_domain` is set, bucket remains in the path.
  """
  @spec build(map()) :: {:ok, Provider.t()} | {:error, term()}
  def build(config) do
    with {:ok, account_id} <- Config.fetch_required_option(config, :account_id) do
      Provider.build_common(
        provider: :cloudflare_r2,
        host: "#{account_id}.r2.cloudflarestorage.com",
        config: config
      )
    end
  end

  @doc """
  Generate a public URL for a key in Cloudflare R2.

  - If `assets_domain` is set, bucket is still included in the path:
    `https://assets.example.com/<bucket>/<key>`.
  - Otherwise falls back to R2 default endpoint.
  """
  @spec url(Provider.t(), String.t()) :: String.t()
  def url(%{assets_domain: domain, bucket: bucket}, key) when is_binary(domain) do
    "#{domain}/#{bucket}/#{key}"
  end

  def url(%{scheme: scheme, host: host, port: port, bucket: bucket}, key) do
    "#{scheme}#{host}:#{port}/#{bucket}/#{key}"
  end
end
