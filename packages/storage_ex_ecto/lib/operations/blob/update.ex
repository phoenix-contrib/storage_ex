defmodule StorageExEcto.Operations.Blob.Update do
  @moduledoc """
  Updates the blob with the given attributes inside a transaction.
  This operation is doing several things:
  1. Touching related attachments so are fresh
  2. Update service metadata if :content_type or :metadata changed
  """
  import Ecto.Query, only: [from: 2]
  alias StorageExEcto.Models.BlobServiceMetadata
  alias StorageExEcto.Models.{Attachment, Blob}

  def call(repo, %Blob{} = blob, attrs) do
    repo.transaction(fn ->
      changeset = Blob.changeset(blob, attrs)

      with {:ok, blob} <- repo.update(changeset) do
        touch_attachments(repo, blob)

        if update_service_metadata?(changeset.changes) do
          StorageEx.update_metadata(
            key: blob.key,
            metadata: BlobServiceMetadata.from_blob(blob),
            service_name: blob.service_name
          )
        end

        {:ok, blob}
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp touch_attachments(repo, %Blob{id: blob_id}) do
    from(a in Attachment, where: a.blob_id == ^blob_id)
    |> repo.update_all(set: [updated_at: NaiveDateTime.utc_now()])
  end

  defp update_service_metadata?(changes) do
    Map.has_key?(changes, :content_type) or Map.has_key?(changes, :metadata)
  end
end
