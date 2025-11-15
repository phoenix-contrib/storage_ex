defmodule StorageEx.Phoenix.RouterTest do
  use ExUnit.Case, async: true

  # Create a test router that uses our routes
  defmodule TestRouter do
    use Phoenix.Router
    use StorageEx.Phoenix.Router

    def config(:secret_key_base), do: String.duplicate("abcdef0123456789", 8)

    scope "/storage_ex" do
      storage_ex_routes()
    end
  end

  test "defines disk download route" do
    # Check that the route is defined by looking at route info
    route_info = TestRouter.__routes__()

    download_route =
      Enum.find(route_info, fn route ->
        route.path == "/storage_ex/disk/:encoded_key/*filename" and
          route.verb == :get
      end)

    assert download_route != nil
    assert download_route.plug == StorageEx.Phoenix.DiskController
    assert download_route.plug_opts == :show
  end

  test "defines disk upload route" do
    # Check that the route is defined by looking at route info
    route_info = TestRouter.__routes__()

    upload_route =
      Enum.find(route_info, fn route ->
        route.path == "/storage_ex/disk/:encoded_token" and
          route.verb == :put
      end)

    assert upload_route != nil
    assert upload_route.plug == StorageEx.Phoenix.DiskController
    assert upload_route.plug_opts == :update
  end
end
