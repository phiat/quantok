defmodule Quantok.Node.CollectorActionsTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Collector.{Count, Display, Reverse, Upcase}

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
end
