defmodule StorageExEcto.Models.BlobMetadata do
  @moduledoc """
  Schema for storing blob metadata information including analysis and identification status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          analyzed: boolean(),
          identified: boolean(),
          composed: boolean(),
          custom: map()
        }

  @primary_key false
  embedded_schema do
    field :analyzed, :boolean, default: false
    field :identified, :boolean, default: false
    field :composed, :boolean, default: false
    field :custom, :map, default: %{}
  end

  def changeset(metadata, attrs) do
    cast(metadata, attrs, [:analyzed, :identified, :composed, :custom])
  end

  def put_custom_metadata(%__MODULE__{} = metadata, custom) do
    %{metadata | custom: custom}
  end

  def service_metadata(%__MODULE__{} = md, blob) do
    %{
      content_type: blob.content_type,
      custom_metadata: md.custom || %{}
    }
  end

  # TODO: Remove this dialyzer suppression once forcibly_serve_as_binary?/1 and
  # allowed_inline?/1 are fully implemented with real logic. Currently these stub
  # functions always return false/true, causing dialyzer to detect dead code branches.
  @dialyzer {:nowarn_function, service_metadata: 1}
  @spec service_metadata(StorageExEcto.Models.Blob.t()) :: map()
  def service_metadata(blob) when is_map(blob) do
    cond do
      forcibly_serve_as_binary?(blob) ->
        %{
          content_type: binary_content_type(),
          disposition: :attachment,
          filename: blob.filename,
          custom_metadata: blob.metadata.custom
        }

      not allowed_inline?(blob) ->
        %{
          content_type: blob.content_type,
          disposition: :attachment,
          filename: blob.filename,
          custom_metadata: blob.metadata.custom
        }

      true ->
        %{
          content_type: blob.content_type,
          custom_metadata: blob.metadata.custom
        }
    end
  end

  # FIXME: Implement actual logic based on your requirements
  @dialyzer {:nowarn_function, forcibly_serve_as_binary?: 1}
  @spec forcibly_serve_as_binary?(StorageExEcto.Models.Blob.t()) :: boolean()
  defp forcibly_serve_as_binary?(_blob), do: false

  @dialyzer {:nowarn_function, allowed_inline?: 1}
  @spec allowed_inline?(StorageExEcto.Models.Blob.t()) :: boolean()
  defp allowed_inline?(_blob), do: true

  @dialyzer {:nowarn_function, binary_content_type: 0}
  @spec binary_content_type() :: String.t()
  defp binary_content_type, do: "application/octet-stream"
end
