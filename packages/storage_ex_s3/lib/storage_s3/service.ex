defmodule StorageExS3.Service do
  @moduledoc false

  @behaviour StorageEx.Service

  alias ExAws.S3.Upload
  alias StorageEx.Config
  alias StorageExS3.Provider

  defstruct [:provider_config, :ex_aws_config, :provider]

  @type t :: %__MODULE__{
          provider_config: Provider.t(),
          ex_aws_config: keyword(),
          provider: atom()
        }

  @spec new(map()) :: t() | {:error, String.t()}
  def new(config) when is_map(config) do
    with {:ok, bucket} <- Config.fetch_required_option(config, :bucket),
         {:ok, access_key_id} <- Config.fetch_required_option(config, :access_key_id),
         {:ok, secret_access_key} <- Config.fetch_required_option(config, :secret_access_key) do
      provider = Map.get(config, :provider, :aws)

      # ask provider module to build its config (host + any special checks)
      case Provider.build(provider, Map.put(config, :bucket, bucket)) do
        {:ok, provider_config} ->
          ex_aws_config =
            [
              access_key_id: access_key_id,
              secret_access_key: secret_access_key,
              region: Map.get(config, :region, "us-east-1")
            ] ++ Provider.to_opts(provider_config)

          %__MODULE__{
            provider_config: provider_config,
            ex_aws_config: ex_aws_config,
            provider: provider
          }

        {:error, reason} ->
          {:error, "Invalid provider config: #{inspect(reason)}"}
      end
    else
      {:error, field} ->
        {:error, "Missing required configuration field: #{field}"}
    end
  end

  @typedoc """
  Options for uploading objects to S3.

  Supported keys:
    * `:acl` — canned ACL string ("private", "public-read", etc.)
    * `:content_type` — MIME type of the object
    * `:metadata` — map of user-defined metadata
    * `:cache_control` — cache control header
    * `:content_disposition` — content disposition header
    * `:expires` — expiry header

  Other keys are passed through to ExAws.S3.
  """
  @type upload_opts ::
          [
            {:acl, String.t()}
            | {:content_type, String.t()}
            | {:metadata, %{String.t() => String.t()}}
            | {:cache_control, String.t()}
            | {:content_disposition, String.t()}
            | {:expires, String.t()}
          ]
  @impl true
  @spec upload(t(), String.t(), iodata() | Enumerable.t() | Path.t(), upload_opts) ::
          {:ok, String.t()} | {:error, term()}
  def upload(%__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws}, key, data, opts) do
    request = build_upload_request(bucket, key, data, opts)
    handle_upload_response(ExAws.request(request, aws), key)
  end

  defp build_upload_request(bucket, key, data, opts) do
    cond do
      is_binary(data) ->
        ExAws.S3.put_object(bucket, key, data, opts)

      match?(%Stream{}, data) ->
        ExAws.S3.upload(data, bucket, key, opts)

      is_binary(data) and File.regular?(data) ->
        data
        |> Upload.stream_file()
        |> ExAws.S3.upload(bucket, key, opts)

      true ->
        raise ArgumentError,
              "Unsupported upload data type: #{inspect(data)}. " <>
                "Expected binary, stream, or file path."
    end
  end

  defp handle_upload_response(response, key) do
    case response do
      {:ok, %{status_code: 200}} -> {:ok, key}
      # multipart upload success
      {:ok, :done} -> {:ok, key}
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_metadata(
        %__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws},
        key,
        metadata
      ) do
    req = ExAws.S3.put_object_copy(bucket, key, bucket, key, metadata: metadata.custom || %{})

    case ExAws.request(req, aws) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Download ---

  @impl true
  def download(%__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws}, key) do
    case ExAws.S3.get_object(bucket, key) |> ExAws.request(aws) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :enoent}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def download_chunk(
        %__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws},
        key,
        range
      ) do
    range_header = "bytes=#{range.first}-#{range.last}"

    case ExAws.S3.get_object(bucket, key, range: range_header) |> ExAws.request(aws) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- File management ---

  @impl true
  def compose(
        %__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws} = service,
        source_keys,
        dest_key,
        _opts
      ) do
    results =
      Enum.map(source_keys, fn key ->
        ExAws.S3.get_object(bucket, key) |> ExAws.request(aws)
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      body =
        results
        |> Enum.map(fn {:ok, %{body: b}} -> b end)
        |> IO.iodata_to_binary()

      upload(service, dest_key, body, [])
    else
      {:error, :compose_failed}
    end
  end

  @impl true
  def delete(%__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws}, key) do
    case ExAws.S3.delete_object(bucket, key) |> ExAws.request(aws) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_prefixed(%__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws}, prefix) do
    # S3 requires listing and then deleting objects
    objects =
      case ExAws.S3.list_objects(bucket, prefix: prefix) |> ExAws.request(aws) do
        {:ok, %{body: %{contents: list}}} ->
          Enum.map(list, & &1.key)

        _ ->
          []
      end

    if objects == [] do
      :ok
    else
      case ExAws.S3.delete_multiple_objects(bucket, objects) |> ExAws.request(aws) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def exists?(%__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws}, key) do
    case ExAws.S3.head_object(bucket, key) |> ExAws.request(aws) do
      {:ok, _} -> true
      {:error, {:http_error, 404, _}} -> false
      {:error, _} -> false
    end
  end

  # --- URL helpers ---

  @impl true
  def url(%__MODULE__{provider_config: provider}, key, _opts) do
    Provider.url(provider, key)
  end

  @impl true
  def url_for_direct_upload(
        %__MODULE__{provider_config: %{bucket: bucket}, ex_aws_config: aws},
        key,
        opts
      ) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    case ExAws.S3.presigned_url(aws, :put, bucket, key, expires_in: expires_in) do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def headers_for_direct_upload(_service, _key, opts) do
    %{
      "content-type" => Keyword.get(opts, :content_type, "application/octet-stream"),
      "content-length" => Keyword.get(opts, :content_length, 0),
      "content-md5" => Keyword.get(opts, :checksum, "")
    }
  end

  @impl true
  def download_stream(%__MODULE__{}, _key) do
    {:error, :not_implemented}
  end
end
