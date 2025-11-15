defmodule StorageEx.Service do
  @moduledoc """
  Behaviour for all StorageEx services (local, S3, GCS, etc.).

  This mirrors the public surface of Rails' ActiveStorage::Service.

  Each adapter (e.g. `StorageEx.Services.DiskService`, `StorageExS3.Service`)
  must implement this behaviour.
  """

  alias StorageEx.ServiceMetadata

  # --- Common types ---

  @type t :: term()
  @type key :: String.t()
  @type binary_data :: binary()
  @type update_metadata_result :: :ok | {:error, term()}

  @type upload_opts :: keyword()

  @type url_opts ::
          [
            {:disposition, :inline | :attachment}
            | {:filename, String.t()}
            | {:content_type, String.t()}
            | {:expires_in, pos_integer()}
          ]

  @type direct_upload_opts ::
          [
            {:expires_in, pos_integer()}
            | {:content_type, String.t()}
            | {:content_length, non_neg_integer()}
            | {:checksum, String.t()}
            | {:custom_metadata, map()}
          ]

  # --- Upload & metadata ---

  @callback upload(t(), key(), binary_data(), upload_opts()) ::
              {:ok, key()} | {:error, term()}

  @callback update_metadata(t(), key(), ServiceMetadata.t()) ::
              update_metadata_result()

  # --- Download ---

  @callback download(t(), key()) ::
              {:ok, binary_data()} | {:error, term()}

  @callback download_chunk(t(), key(), Range.t()) ::
              {:ok, binary_data()} | {:error, term()}

  @callback download_stream(t(), key()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  # --- File management ---

  @callback compose(t(), [key()], key(), keyword()) ::
              :ok | {:error, term()}

  @callback delete(t(), key()) ::
              :ok | {:error, term()}

  @callback delete_prefixed(t(), String.t()) ::
              :ok | {:error, term()}

  @callback exists?(t(), key()) :: boolean()

  # --- URL helpers ---

  @callback url(t(), key(), url_opts()) :: String.t()

  @callback url_for_direct_upload(t(), key(), direct_upload_opts()) ::
              {:ok, String.t()} | {:error, term()}

  @callback headers_for_direct_upload(t(), key(), direct_upload_opts()) ::
              map()
end
