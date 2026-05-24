defmodule Quantok.Node.CollectorActionsTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Collector.{Count, Display, Hash, Reverse, Upcase}

  describe "Display" do
    test "returns text unchanged" do
      assert Display.process("", "hello world") == "hello world"
    end
  end

  describe "Reverse" do
    test "reverses text" do
      assert Reverse.process("", "hello") == "olleh"
    end

    test "handles unicode" do
      assert Reverse.process("", "héllo") == "olléh"
    end
  end

  describe "Count" do
    test "counts chars and bytes" do
      result = Count.process("", "hello")
      assert result == "5 chars, 5 bytes"
    end

    test "handles multibyte chars" do
      result = Count.process("", "\u{1F525}")
      assert result == "1 chars, 4 bytes"
    end
  end

  describe "Upcase" do
    test "uppercases text" do
      assert Upcase.process("", "hello world") == "HELLO WORLD"
    end
  end

  describe "Hash" do
    test "sha256 default" do
      assert Hash.process("", "hello") ==
               "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    end

    test "md5" do
      assert Hash.process("md5", "hello") == "5d41402abc4b2a76b9719d911017c592"
    end

    test "sha1" do
      assert Hash.process("sha1", "hello") == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"
    end

    test "unknown algo falls back to sha256" do
      assert Hash.process("not-an-algo", "hello") == Hash.process("sha256", "hello")
    end
  end
end
