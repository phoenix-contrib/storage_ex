defmodule StorageEx.Phoenix.Router do
  @moduledoc """
  Provides routing macros for StorageEx disk service endpoints.

  ## Usage

  In your Phoenix router:

      use StorageEx.Phoenix.Router

      scope "/storage_ex" do
        storage_ex_routes()
      end

  This will mount the following routes:

    * GET  /storage_ex/disk/:encoded_key/*filename - Download files
    * PUT  /storage_ex/disk/:encoded_token - Upload files (direct upload)

  The routes use signed tokens for security, similar to Rails ActiveStorage.
  """

  @doc """
  Generates StorageEx routes for disk service.

  ## Options

    * `:prefix` - Path prefix for routes (default: "/storage_ex")

  ## Examples

      # Default prefix
      scope "/storage_ex" do
        storage_ex_routes()
      end

      # Custom prefix
      scope "/files" do
        storage_ex_routes()
      end
  """
  defmacro storage_ex_routes(_opts \\ []) do
    quote do
      get "/disk/:encoded_key/*filename", StorageEx.Phoenix.DiskController, :show,
        as: :storage_ex_disk_service

      put "/disk/:encoded_token", StorageEx.Phoenix.DiskController, :update,
        as: :update_storage_ex_disk_service
    end
  end

  defmacro __using__(_opts) do
    quote do
      import StorageEx.Phoenix.Router, only: [storage_ex_routes: 0, storage_ex_routes: 1]
    end
  end
end
