# IEx configuration for StorageEx playground

# Enable IEx history
IEx.configure(
  history_size: 1000,
  inspect: [limit: :infinity]
)

# Check if shell history is enabled
case :application.get_env(:kernel, :shell_history) do
  {:ok, :enabled} ->
    # Shell history is enabled, ensure directory exists
    history_dir = Path.expand("~/.cache/erlang-history")
    File.mkdir_p!(history_dir)
    IO.puts("✅ Persistent shell history enabled")

  _ ->
    IO.puts("⚠�  Shell history not enabled. Run: export ERL_AFLAGS=\"-kernel shell_history enabled\"")
end

# Configure StorageEx to use disk storage in ~/Desktop/storage_ex_playground
playground_dir = Path.expand("~/Desktop/storage_ex_playground")

Application.put_env(:storage_ex, :service, :playground_disk)

Application.put_env(:storage_ex, :services, %{
  playground_disk: %{
    service: StorageEx.Services.DiskService,
    configuration: %{
      root: playground_dir
    }
  }
})

# Reload the config
StorageEx.Config.reload!()
