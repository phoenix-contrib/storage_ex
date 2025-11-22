defmodule StorageEx.ServiceMetadata do
  @moduledoc """
  Struct for holding service-specific metadata for stored files.
  """
  defstruct [:content_type, :disposition, :filename, custom_metadata: %{}]

  @type t :: %__MODULE__{
          content_type: String.t() | nil,
          disposition: String.t() | nil,
          filename: String.t() | nil,
          custom_metadata: map()
        }
end
