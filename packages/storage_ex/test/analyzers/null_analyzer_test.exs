defmodule StorageEx.Analyzers.NullAnalyzerTest do
  use ExUnit.Case, async: true

  alias StorageEx.Analyzers.NullAnalyzer

  describe "accept?/1" do
    test "accepts all content types" do
      assert NullAnalyzer.accept?("image/jpeg")
      assert NullAnalyzer.accept?("video/mp4")
      assert NullAnalyzer.accept?("audio/mp3")
      assert NullAnalyzer.accept?("application/pdf")
      assert NullAnalyzer.accept?("text/plain")
      assert NullAnalyzer.accept?("application/octet-stream")
      assert NullAnalyzer.accept?("unknown/type")
    end
  end

  describe "analyze_later?/0" do
    test "returns false for immediate processing" do
      refute NullAnalyzer.analyze_later?()
    end
  end

  describe "available?/0" do
    test "is always available" do
      assert NullAnalyzer.available?()
    end
  end

  describe "metadata/2" do
    test "always returns empty metadata" do
      assert {:ok, %{}} = NullAnalyzer.metadata("/any/path", "any/content-type")
      assert {:ok, %{}} = NullAnalyzer.metadata("/non/existent/file", "image/jpeg")
      assert {:ok, %{}} = NullAnalyzer.metadata("", "")
    end
  end
end
