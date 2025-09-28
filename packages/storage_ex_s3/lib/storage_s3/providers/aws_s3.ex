defmodule StorageExS3.Providers.AWSS3 do
  @moduledoc false
  alias StorageExS3.Provider

  @doc """
  Build an AWS S3 provider config.
  Requires :bucket and :region.
  """
  @spec build(map()) :: {:ok, Provider.t()} | {:error, term()}
  def build(config) do
    Provider.build_common(provider: :aws_s3, host: "s3.amazonaws.com", config: config)
  end

  @spec url(Provider.t(), String.t()) :: String.t()
  def url(%{assets_domain: domain, bucket: _bucket}, key) when is_binary(domain) do
    "#{domain}/#{key}"
  end

  def url(%{bucket: bucket, region: region}, key) do
    "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
  end
end
