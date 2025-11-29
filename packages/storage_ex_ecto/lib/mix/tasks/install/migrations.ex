defmodule Mix.Tasks.Install.Migrations do
  @moduledoc """
  Igniter helper for generating StorageEx migrations, used by the
  `mix igniter.install phoenix_contrib_storage_ex` task.
  """

  alias Igniter.Libs.Ecto

  def add_storage_migration(igniter) do
    base = "create_storage_ex_ecto_tables"

    repo_module =
      Igniter.Project.Module.module_name(
        igniter,
        "Repo"
      )

    if migration_exists?(base) do
      igniter
      |> Igniter.Scribe.section(
        "Migrations",
        "StorageEx migration already exists, skipping creation.",
        fn igniter -> igniter end
      )
    else
      igniter
      |> Ecto.gen_migration(
        repo_module,
        base,
        body: migration_body(repo_module)
      )
      |> Igniter.Scribe.section(
        "Migrations",
        "✅ Created migration: #{base}.exs",
        fn igniter -> igniter end
      )
    end
  end

  defp migration_exists?(base) do
    Path.wildcard("priv/repo/migrations/*_#{base}*.exs") != []
  end

  defp migration_body(repo_module) do
    """
    def change do
      {pk, fk} = primary_and_foreign_key_types()

      # === Blobs ===
      create table(:storage_ex_blobs, primary_key: false) do
        add :id, pk, primary_key: true
        add :key, :string, null: false
        add :filename, :string, null: false
        add :content_type, :string
        add :metadata, :map
        add :service_name, :string, null: false
        add :byte_size, :bigint, null: false
        add :checksum, :string

        timestamps()
      end

      create unique_index(:storage_ex_blobs, [:key])

      # === Attachments ===
      create table(:storage_ex_attachments, primary_key: false) do
        add :id, pk, primary_key: true
        add :name, :string, null: false
        add :record_type, :string, null: false
        add :record_id, fk, null: false
        add :blob_id, references(:storage_ex_blobs, type: fk, on_delete: :delete_all), null: false

        timestamps()
      end

      create unique_index(
               :storage_ex_attachments,
               [:record_type, :record_id, :name, :blob_id],
               name: :index_storage_ex_attachments_uniqueness
             )

      # === Variant Records ===
      create table(:storage_ex_variant_records, primary_key: false) do
        add :id, pk, primary_key: true
        add :blob_id, references(:storage_ex_blobs, type: fk, on_delete: :delete_all), null: false
        add :variation_digest, :string, null: false
      end

      create unique_index(
               :storage_ex_variant_records,
               [:blob_id, :variation_digest],
               name: :index_storage_ex_variant_records_uniqueness
             )
    end

    defp primary_and_foreign_key_types(repo \\\\ #{inspect(repo_module)}) do
      otp_app = Mix.Project.config()[:app]
      config  = Application.fetch_env!(otp_app, repo)

      pk_opts = Keyword.get(config, :migration_primary_key, [])
      fk_opts = Keyword.get(config, :migration_foreign_key, [])

      pk = Keyword.get(pk_opts, :type, :bigserial)
      fk = Keyword.get(fk_opts, :type, :bigint)

      {pk, fk}
    end
    """
  end
end
