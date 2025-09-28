defmodule StorageExEcto.Models.BlobServiceMetadata do
  alias StorageEx.ServiceMetadata
  alias StorageExEcto.Models.Blob

  # TODO: Remove this dialyzer suppression once forcibly_serve_as_binary?/1 and 
  # allowed_inline?/1 are fully implemented with real logic. Currently these stub 
  # functions always return false/true, causing dialyzer to detect dead code branches.
  @dialyzer {:nowarn_function, from_blob: 1}
  @spec from_blob(Blob.t()) :: ServiceMetadata.t()
  def from_blob(%Blob{} = blob) do
    cond do
      forcibly_serve_as_binary?(blob) ->
        %ServiceMetadata{
          content_type: binary_content_type(),
          disposition: "attachment",
          filename: blob.filename,
          custom_metadata: blob.metadata.custom
        }

      not allowed_inline?(blob) ->
        %ServiceMetadata{
          content_type: blob.content_type,
          disposition: "attachment",
          filename: blob.filename,
          custom_metadata: blob.metadata.custom
        }

      true ->
        %ServiceMetadata{
          content_type: blob.content_type,
          custom_metadata: blob.metadata.custom
        }
    end
  end

  # FIXME: Implement actual logic based on your requirements
  @dialyzer {:nowarn_function, forcibly_serve_as_binary?: 1}
  @spec forcibly_serve_as_binary?(Blob.t()) :: boolean()
  defp forcibly_serve_as_binary?(_blob), do: false

  @dialyzer {:nowarn_function, allowed_inline?: 1}
  @spec allowed_inline?(Blob.t()) :: boolean()
  defp allowed_inline?(_blob), do: true

  @dialyzer {:nowarn_function, binary_content_type: 0}
  @spec binary_content_type() :: String.t()
  defp binary_content_type, do: "application/octet-stream"
end
