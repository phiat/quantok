defmodule Quantok.Node.EmitterSourcesTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Emitter.{Clock, File, Manual, Random, Sequence}

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
    test "reads existing file in safe directory" do
      safe_dir = Application.app_dir(:quantok, "priv/data")
      Elixir.File.mkdir_p!(safe_dir)
      filename = "quantok_test_#{:rand.uniform(100_000)}.txt"
      path = Path.join(safe_dir, filename)
      Elixir.File.write!(path, "test content")
      {:ok, result} = File.execute(filename)
      assert result == "test content"
      Elixir.File.rm!(path)
    end

    test "rejects path traversal" do
      {:error, :path_outside_safe_directory} = File.execute("../../etc/passwd")
    end

    test "returns error for missing file" do
      {:error, {:file_read, :enoent}} = File.execute("nonexistent.txt")
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

  describe "Random" do
    test "alnum default length is 32" do
      {:ok, result} = Random.execute()
      assert byte_size(result) == 32
      assert String.match?(result, ~r/^[A-Za-z0-9]{32}$/)
    end

    test "hex charset emits only hex chars" do
      {:ok, result} = Random.execute("hex:64")
      assert byte_size(result) == 64
      assert String.match?(result, ~r/^[0-9a-f]{64}$/)
    end

    test "alpha charset excludes digits" do
      {:ok, result} = Random.execute("alpha:128")
      assert String.match?(result, ~r/^[A-Za-z]{128}$/)
    end

    test "binary returns raw bytes of requested length" do
      {:ok, result} = Random.execute("binary:16")
      assert byte_size(result) == 16
    end

    test "rejects non-positive counts by falling back to default" do
      {:ok, result} = Random.execute("alnum:0")
      assert byte_size(result) == 32
    end

    test "caps absurd counts via fallback" do
      {:ok, result} = Random.execute("alnum:99999")
      assert byte_size(result) == 32
    end
  end
end
