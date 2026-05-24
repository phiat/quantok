defmodule Quantok.Node.CollectorActionsTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Collector.{Count, Display, Hash, Max, Min, Reverse, Sum, Upcase}
  alias Quantok.Tokene

  describe "Display" do
    test "returns text unchanged" do
      assert Display.process("", "hello world", []) == "hello world"
    end
  end

  describe "Reverse" do
    test "reverses text" do
      assert Reverse.process("", "hello", []) == "olleh"
    end

    test "handles unicode" do
      assert Reverse.process("", "héllo", []) == "olléh"
    end
  end

  describe "Count" do
    test "counts chars and bytes" do
      assert Count.process("", "hello", []) == "5 chars, 5 bytes"
    end

    test "handles multibyte chars" do
      assert Count.process("", "\u{1F525}", []) == "1 chars, 4 bytes"
    end
  end

  describe "Upcase" do
    test "uppercases text" do
      assert Upcase.process("", "hello world", []) == "HELLO WORLD"
    end
  end

  describe "Hash" do
    test "sha256 default" do
      assert Hash.process("", "hello", []) ==
               "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    end

    test "md5" do
      assert Hash.process("md5", "hello", []) == "5d41402abc4b2a76b9719d911017c592"
    end

    test "sha1" do
      assert Hash.process("sha1", "hello", []) == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"
    end

    test "unknown algo falls back to sha256" do
      assert Hash.process("not-an-algo", "hello", []) == Hash.process("sha256", "hello", [])
    end
  end

  describe "Sum / Min / Max" do
    setup do
      %{buffer: [num("3"), num("7.5"), num("not a number"), num("-2"), num("12")]}
    end

    test "sum adds numeric values, skipping garbage", %{buffer: buffer} do
      assert Sum.process("", "", buffer) == "20.5000"
    end

    test "min picks smallest", %{buffer: buffer} do
      assert Min.process("", "", buffer) == "-2"
    end

    test "max picks largest", %{buffer: buffer} do
      assert Max.process("", "", buffer) == "12"
    end

    test "min/max emit empty when no numbers parse" do
      buf = [num("hello"), num("world")]
      assert Min.process("", "", buf) == ""
      assert Max.process("", "", buf) == ""
    end

    test "sum on empty buffer is 0" do
      assert Sum.process("", "", []) == "0"
    end

    test "sum overflow returns sentinel instead of crashing" do
      buf = [num("1.0e308"), num("1.0e308")]
      assert Sum.process("", "", buf) == "overflow"
    end

    defp num(v), do: Tokene.new(v, :word, "test")
  end
end
