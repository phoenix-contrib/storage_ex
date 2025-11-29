defmodule StorageExS3Test do
  use ExUnit.Case
  doctest StorageExS3.Service

  test "S3 service module exists" do
    # TODO: Add actual S3 service tests when credentials are available
    assert Code.ensure_loaded?(StorageExS3.Service)
  end
end
