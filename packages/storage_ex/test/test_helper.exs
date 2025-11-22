ExUnit.start()
ExUnit.configure(exclude: [:pending, :unavailable_tools])

config_file = Path.expand("../config/test.exs", __DIR__)
Application.put_all_env(Config.Reader.read!(config_file))
StorageEx.Config.reload!()

Enum.each(Path.wildcard("test/support/**/*.exs"), &Code.require_file/1)

# Clean up all test storage directories after the entire suite
ExUnit.after_suite(fn _results ->
  for service <- [:test_disk, :alternative_disk, :streaming_test] do
    config = Application.get_env(:storage_ex, :services, %{})[service]

    if config do
      root = config[:configuration][:root]
      if root, do: File.rm_rf(root)
    end
  end
end)
