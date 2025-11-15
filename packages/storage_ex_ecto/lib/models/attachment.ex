defmodule StorageExEcto.Models.Attachment do
  @moduledoc """
  Represents an attachment record that links a blob to a specific record
  (identified by `record_type` and `record_id`).
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias StorageExEcto.Models.Blob

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          record_type: String.t(),
          record_id: term(),
          blob_id: term()
        }

  schema "storage_ex_attachments" do
    field(:name, :string)
    field(:record_type, :string)
    field(:record_id, :integer)

    belongs_to(:blob, Blob,
      foreign_key: :blob_id,
      type: :id,
      on_replace: :delete
    )

    timestamps()
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:name, :record_type, :record_id, :blob_id])
    |> validate_required([:name, :record_type, :record_id, :blob_id])
  end
end
