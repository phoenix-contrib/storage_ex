defmodule StorageEx.Phoenix.URL do
  @moduledoc """
  URL generation helpers for StorageEx.

  Generates signed URLs for disk service file access and direct uploads,
  similar to Rails ActiveStorage URL signing.
  """

  @doc """
  Generates a signed URL for downloading a file from disk service.

  ## Options

    * `:endpoint` - Phoenix endpoint module (optional if configured globally)
    * `:service_name` - The service name (default: uses default service)
    * `:expires_in` - Expiration time in seconds (default: 300)
    * `:content_type` - Content type of the file
    * `:disposition` - `:inline` or `:attachment` (default: `:inline`)
    * `:filename` - Original filename for the Content-Disposition header

  The endpoint can be configured globally:

      config :storage_ex, endpoint: MyAppWeb.Endpoint

  Or passed as an option (which takes precedence):

      StorageEx.Phoenix.URL.signed_url("avatar.png",
        endpoint: MyAppWeb.Endpoint,
        filename: "avatar.png"
      )

  ## Examples

      # Using configured endpoint
      StorageEx.Phoenix.URL.signed_url("avatar.png",
        filename: "avatar.png",
        disposition: :attachment
      )

      # Overriding endpoint
      StorageEx.Phoenix.URL.signed_url("avatar.png",
        endpoint: MyAppWeb.Endpoint,
        filename: "avatar.png",
        disposition: :attachment
      )
  """
  def signed_url(key, opts) do
    endpoint =
      Keyword.get(opts, :endpoint) || StorageEx.Config.endpoint() ||
        raise ArgumentError,
              "endpoint is required. Pass as option or configure with `config :storage_ex, endpoint: MyAppWeb.Endpoint`"

    service_name = Keyword.get(opts, :service_name) || StorageEx.Config.default_service()
    expires_in = Keyword.get(opts, :expires_in, 300)
    content_type = Keyword.get(opts, :content_type)
    disposition = Keyword.get(opts, :disposition, :inline)
    filename = Keyword.get(opts, :filename, key)

    token_data = %{
      key: key,
      service_name: service_name,
      content_type: content_type,
      disposition: disposition
    }

    salt = get_token_salt()
    encoded_key = Phoenix.Token.sign(endpoint, salt, token_data, max_age: expires_in)

    # Generate the URL path
    path = "/storage_ex/disk/#{encoded_key}/#{filename}"

    # Return full URL with endpoint's URL configuration
    url_config = endpoint.config(:url) || []
    scheme = Keyword.get(url_config, :scheme, "http")
    host = Keyword.get(url_config, :host, "localhost")
    port = Keyword.get(url_config, :port, 4000)

    port_string = if port in [80, 443], do: "", else: ":#{port}"
    "#{scheme}://#{host}#{port_string}#{path}"
  end

  @doc """
  Generates a signed URL for direct file upload to disk service.

  ## Options

    * `:endpoint` - Phoenix endpoint module (optional if configured globally)
    * `:service_name` - The service name (default: uses default service)
    * `:expires_in` - Expiration time in seconds (default: 300)
    * `:content_type` - Expected content type
    * `:content_length` - Expected content length in bytes
    * `:checksum` - Expected MD5 checksum (Base64 encoded)

  The endpoint can be configured globally:

      config :storage_ex, endpoint: MyAppWeb.Endpoint

  ## Examples

      # Using configured endpoint
      StorageEx.Phoenix.URL.signed_upload_url("avatar.png",
        content_type: "image/png",
        content_length: 1024
      )

      # Overriding endpoint
      StorageEx.Phoenix.URL.signed_upload_url("avatar.png",
        endpoint: MyAppWeb.Endpoint,
        content_type: "image/png",
        content_length: 1024,
        checksum: checksum
      )
  """
  def signed_upload_url(key, opts) do
    endpoint =
      Keyword.get(opts, :endpoint) || StorageEx.Config.endpoint() ||
        raise ArgumentError,
              "endpoint is required. Pass as option or configure with `config :storage_ex, endpoint: MyAppWeb.Endpoint`"

    service_name = Keyword.get(opts, :service_name) || StorageEx.Config.default_service()
    expires_in = Keyword.get(opts, :expires_in, 300)
    content_type = Keyword.get(opts, :content_type)
    content_length = Keyword.get(opts, :content_length)
    checksum = Keyword.get(opts, :checksum)

    token_data = %{
      key: key,
      service_name: service_name,
      content_type: content_type,
      content_length: content_length,
      checksum: checksum
    }

    salt = get_token_salt()
    encoded_token = Phoenix.Token.sign(endpoint, salt, token_data, max_age: expires_in)

    # Generate the URL path
    path = "/storage_ex/disk/#{encoded_token}"

    # Return full URL with endpoint's URL configuration
    url_config = endpoint.config(:url) || []
    scheme = Keyword.get(url_config, :scheme, "http")
    host = Keyword.get(url_config, :host, "localhost")
    port = Keyword.get(url_config, :port, 4000)

    port_string = if port in [80, 443], do: "", else: ":#{port}"
    {:ok, "#{scheme}://#{host}#{port_string}#{path}"}
  end

  defp get_token_salt do
    Application.get_env(:storage_ex, :token_salt, "storage_ex_disk_service")
  end
end
