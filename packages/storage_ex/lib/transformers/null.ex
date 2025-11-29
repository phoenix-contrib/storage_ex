defmodule StorageEx.Transformers.Null do
  @moduledoc """
  No-op transformer that performs no transformations.

  Used when variants are disabled or no transformation library is available.
  Simply copies the input file to the output path.
  """

  @behaviour StorageEx.Transformer

  @impl true
  def available?, do: true

  @impl true
  def transform(input_path, output_path, _transformations, _format) do
    case File.copy(input_path, output_path) do
      {:ok, _bytes} -> {:ok, output_path}
      {:error, reason} -> {:error, reason}
    end
  end
end
