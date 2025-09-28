ExUnit.start()
ExUnit.configure(exclude: :pending)

config_file = Path.expand("../config/test.exs", __DIR__)
Application.put_all_env(Config.Reader.read!(config_file))
StorageEx.Config.reload!()

Enum.each(Path.wildcard("test/support/**/*.exs"), &Code.require_file/1)
