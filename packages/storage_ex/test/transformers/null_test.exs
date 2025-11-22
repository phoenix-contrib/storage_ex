defmodule StorageEx.Transformers.NullTest do
  use ExUnit.Case, async: true
  use StorageEx.Support.DiskCleanup

  alias StorageEx.Transformers.Null

  describe "available?/0" do
    test "is always available" do
      assert Null.available?()
    end
  end

  describe "transform/4" do
    test "copies file without transformation" do
      # Use System.tmp_dir! for transformer tests (not storage)
      input_path =
        Path.join(System.tmp_dir!(), "storage_ex_test_input_#{:erlang.unique_integer()}.txt")

      output_path =
        Path.join(System.tmp_dir!(), "storage_ex_test_output_#{:erlang.unique_integer()}.txt")

      File.write!(input_path, "test content")

      assert {:ok, ^output_path} =
               Null.transform(
                 input_path,
                 output_path,
                 [resize_to_limit: [100, 100]],
                 :png
               )

      assert File.read!(output_path) == "test content"

      # Cleanup
      File.rm(input_path)
      File.rm(output_path)
    end

    test "returns error if input file doesn't exist" do
      input_path = Path.join(System.tmp_dir!(), "nonexistent_#{:erlang.unique_integer()}.txt")
      output_path = Path.join(System.tmp_dir!(), "output_#{:erlang.unique_integer()}.txt")

      assert {:error, :enoent} =
               Null.transform(
                 input_path,
                 output_path,
                 [],
                 :png
               )
    end
  end
end
