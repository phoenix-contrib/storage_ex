defmodule StorageExEcto.Config do
  @moduledoc """
  Central configuration for StorageExEcto.

  ## Setup

  In your `runtime.exs`:
    config :storage_ex_ecto, repo: MyApp.Repo,
  """

  @key {:storage_ex_ecto, :config}

  def repo, do: get_config().repo

  def reload! do
    :persistent_term.erase(@key)
    :ok
  end

  defp get_config do
    case :persistent_term.get(@key, :not_set) do
      :not_set ->
        cfg =
          Application.get_env(:storage_ex_ecto, :phoenix_contrib_storage_ex_ecto, [])
          |> normalize_config()

        :persistent_term.put(@key, cfg)
        cfg

      cfg ->
        cfg
    end
  end

  defp normalize_config(opts) do
    %{repo: Keyword.fetch!(opts, :repo)}
  end
end
