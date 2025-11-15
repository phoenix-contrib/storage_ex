defmodule StorageExEcto.Models.VariantRecord do
  @moduledoc """
  Represents a variant of a blob, identified by a variation digest.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias StorageExEcto.Models.Blob

  @type t :: %__MODULE__{
          id: term(),
          blob_id: term(),
          variation_digest: String.t()
        }

  schema "storage_ex_variant_records" do
    field(:variation_digest, :string)

    belongs_to(:blob, Blob,
      foreign_key: :blob_id,
      type: :id,
      on_replace: :delete
    )

    # no timestamps in migration
  end

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:blob_id, :variation_digest])
    |> validate_required([:blob_id, :variation_digest])
  end
end
