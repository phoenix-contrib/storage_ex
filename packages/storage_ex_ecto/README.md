# StorageExEcto

Ecto integration for StorageEx - ActiveStorage-like file attachments for Phoenix applications.

## Installation

Add `storage_ex_ecto` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_contrib_storage_ex, "~> 0.1.0"},
    {:phoenix_contrib_storage_ex_ecto, "~> 0.1.0"}
  ]
end
```

## Usage

StorageExEcto provides Ecto integration for managing file attachments in your Phoenix application, similar to Rails ActiveStorage.

### Basic Setup

1. Run the installer to generate migrations:

```bash
mix storage_ex_ecto.install
```

2. Configure your repo:

```elixir
# config/runtime.exs
config :storage_ex_ecto,
  repo: MyApp.Repo
```

### Adding Attachments to Your Schema

```elixir
defmodule MyApp.Post do
  use Ecto.Schema
  import Ecto.Changeset
  
  schema "posts" do
    field :title, :string
    has_one :avatar_attachment, StorageExEcto.Models.Attachment
    has_many :images_attachments, StorageExEcto.Models.Attachment
    
    timestamps()
  end
end
```

## Documentation

Full documentation can be found at [https://hexdocs.pm/phoenix_contrib_storage_ex_ecto](https://hexdocs.pm/phoenix_contrib_storage_ex_ecto).

## License

MIT License. See [LICENSE](https://github.com/phoenix-contrib/storage_ex/blob/main/LICENSE) for details.
