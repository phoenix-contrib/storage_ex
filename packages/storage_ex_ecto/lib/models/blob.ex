defmodule StorageExEcto.Models.Blob do
  @moduledoc """
  A blob is a record that contains the metadata about a file and a key for where that file resides on the service.
  Blobs can be created in two ways:

  1. Ahead of the file being uploaded server-side to the service, via <tt>create_and_upload!</tt>. A rewindable
    <tt>io</tt> with the file contents must be available at the server for this operation.
  2. Ahead of the file being directly uploaded client-side to the service, via <tt>create_before_direct_upload!</tt>.

  The first option doesn't require any client-side JavaScript integration, and can be used by any other back-end
  service that deals with files. The second option is faster, since you're not using your own server as a staging
  point for uploads, and can work with deployments like Heroku that do not provide large amounts of disk space.

  Blobs are intended to be immutable in as-so-far as their reference to a specific file goes. You're allowed to
  update a blob's metadata on a subsequent pass, but you should not update the key or change the uploaded file.
  If you need to create a derivative or otherwise change the blob, simply create a new blob and purge the old one.
  """
  @minimum_token_length 28

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import StorageEx.Config, only: [default_service: 0]
  import StorageExEcto.Config, only: [repo: 0]
  alias StorageExEcto.Models.{Attachment, BlobMetadata, VariantRecord}
  alias StorageExEcto.Operations.Blob.Update, as: BlobUpdate

  @type t :: %__MODULE__{
          id: term(),
          key: String.t(),
          filename: String.t(),
          content_type: String.t(),
          service_name: String.t(),
          byte_size: integer(),
          checksum: String.t(),
          metadata: BlobMetadata.t()
        }

  schema "storage_blobs" do
    field(:key, :string)
    field(:filename, :string)
    field(:content_type, :string)
    field(:service_name, :string)
    field(:byte_size, :integer)
    field(:checksum, :string)

    embeds_one(
      :metadata,
      BlobMetadata,
      on_replace: :update
    )

    has_many(:attachments, Attachment, foreign_key: :blob_id)
    has_many(:variant_records, VariantRecord, foreign_key: :blob_id)

    timestamps()
  end

  def changeset(blob, attrs) do
    blob
    |> cast(attrs, [
      :key,
      :filename,
      :content_type,
      :service_name,
      :byte_size,
      :checksum
    ])
    |> put_metadata()
    |> validate_required([:key, :filename, :service_name, :byte_size])
    |> put_service_default()
    # Rails: validates checksum unless composed
    # |> validate_required([:checksum]) # TODO: conditional validation
    |> unique_constraint(:key)
  end

  def update(blob, attrs) do
    BlobUpdate.call(repo(), blob, attrs)
  end

  def unattached(query \\ __MODULE__) do
    from(b in query,
      left_join: a in assoc(b, :attachments),
      where: is_nil(a.id)
    )
  end

  @doc """
  Returns the key pointing to the file on the service that's associated with this blob.
  So it'll look like: xtapjjcjiudrlk3tmwyjgpuobabd.
  This key is not intended to be revealed directly to the user.
  Always refer to blobs using the signed_id or a verified form of the key.
  """
  def get_key(%__MODULE__{key: nil} = _blob), do: generate_unique_secure_token()
  def get_key(%__MODULE__{key: key}), do: key

  @doc """
  Returns true if the content_type of this blob is in the image range, like image/png.
  """
  def image?(%__MODULE__{content_type: ct}) when is_binary(ct),
    do: String.starts_with?(ct, "image")

  def image?(_), do: false

  @doc """
  Returns true if the content_type of this blob is in the audio range, like audio/mpeg.
  """
  def audio?(%__MODULE__{content_type: ct}) when is_binary(ct),
    do: String.starts_with?(ct, "audio")

  def audio?(_), do: false

  @doc """
  Returns true if the content_type of this blob is in the video range, like video/mp4.
  """
  def video?(%__MODULE__{content_type: ct}) when is_binary(ct),
    do: String.starts_with?(ct, "video")

  def video?(_), do: false

  @doc """
  Returns true if the content_type of this blob is in the text range, like text/plain.
  """
  def text?(%__MODULE__{content_type: ct}) when is_binary(ct), do: String.starts_with?(ct, "text")
  def text?(_), do: false

  # ============================
  # TODOs (Not yet implemented)
  # ============================

  # - Callbacks:
  #   after_initialize: set default service_name
  #   after_update: touch attachments
  #   after_update_commit: update_service_metadata
  #   before_destroy: raise if attachments exist
  #
  # - Signed IDs:
  #   find_signed / find_signed!
  #   signed_id()
  #
  # - Uploading / Downloading:
  #   create_and_upload! / create_before_direct_upload!
  #   unfurl(io), upload_without_unfurling(io), compose, etc.
  #
  # - Checksums:
  #   compute_checksum_in_chunks(io)
  #
  # - Purge and purge_later (jobs).
  #
  # - URL generation (service.url, service_url_for_direct_upload).

  @doc """
  To prevent problems with case-insensitive filesystems, especially in combination
  with databases which treat indices as case-sensitive, all blob keys generated are going
  to only contain the base-36 character alphabet and will therefore be lowercase. To maintain
  the same or higher amount of entropy as in the base-58 encoding used by +has_secure_token+
  the number of bytes used is increased to 28 from the standard 24
  """
  def generate_unique_secure_token(length \\ @minimum_token_length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode32(case: :lower, padding: false)
    |> binary_part(0, length)
  end

  defp put_service_default(changeset) do
    case get_field(changeset, :service_name) do
      nil -> put_change(changeset, :service_name, default_service())
      _ -> changeset
    end
  end

  defp put_metadata(changeset) do
    changeset
    |> cast_embed(:metadata, with: &BlobMetadata.changeset/2, required: false)
    |> ensure_metadata()
  end

  defp ensure_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil -> put_embed(changeset, :metadata, %BlobMetadata{})
      _ -> changeset
    end
  end
end
