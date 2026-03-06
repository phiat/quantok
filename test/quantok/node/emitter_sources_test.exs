defmodule Quantok.Node.EmitterSourcesTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Emitter.{Clock, File, Manual, Sequence}

  describe "Clock" do
    test "returns formatted time" do
      {:ok, result} = Clock.execute("%H:%M")
      assert String.match?(result, ~r/\d{2}:\d{2}/)
    end

    test "uses default format" do
      {:ok, result} = Clock.execute()
      assert String.length(result) > 10
    end
  end

  describe "File" do
    test "reads existing file" do
      path = Path.join(System.tmp_dir!(), "quantok_test_#{:rand.uniform(100_000)}.txt")
      Elixir.File.write!(path, "test content")
      {:ok, result} = File.execute(path)
      assert result == "test content"
      Elixir.File.rm!(path)
    end

    test "returns error for missing file" do
      {:error, {:file_read, :enoent}} = File.execute("/nonexistent/path")
    end
  end

  describe "Manual" do
    test "returns text directly" do
      {:ok, result} = Manual.execute("hello world")
      assert result == "hello world"
    end
  end

  describe "Sequence" do
    test "alpha returns A-Z" do
      {:ok, result} = Sequence.execute("alpha")
      assert String.starts_with?(result, "A B C")
      assert String.ends_with?(result, "X Y Z")
    end

    test "digits returns 0-9" do
      {:ok, result} = Sequence.execute("digits")
      assert result == "0 1 2 3 4 5 6 7 8 9"
    end

    test "numeric count" do
      {:ok, result} = Sequence.execute("3")
      assert result == "1 2 3"
    end
  end
end
