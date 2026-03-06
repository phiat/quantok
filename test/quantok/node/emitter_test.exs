defmodule Quantok.Node.EmitterTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Emitter

  describe "new/1" do
    test "creates an emitter node with defaults" do
      node = Emitter.new()
      assert node.type == :emitter
      assert node.config.chunker == Quantok.Chunker.Word
      assert node.config.command == "echo hello"
    end

    test "accepts custom options" do
      node = Emitter.new(command: "date", chunker: Quantok.Chunker.Byte, label: "Date")
      assert node.config.command == "date"
      assert node.config.chunker == Quantok.Chunker.Byte
      assert node.label == "Date"
    end
  end

  describe "fire/1" do
    test "shell emitter produces tokenes from command output" do
      node = Emitter.new(command: "echo hello world", chunker: Quantok.Chunker.Word)
      {:ok, tokenes} = Emitter.fire(node)

      assert length(tokenes) == 2
      assert Enum.map(tokenes, & &1.value) == ["hello", "world"]
      assert Enum.all?(tokenes, &(&1.encoding == :word))
      assert Enum.all?(tokenes, &(&1.source_id == node.id))
    end

    test "manual emitter uses command text as output" do
      node =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "test input",
          chunker: Quantok.Chunker.Byte
        )

      {:ok, tokenes} = Emitter.fire(node)

      assert length(tokenes) == 10
      assert Enum.map_join(tokenes, & &1.value) == "test input"
    end

    test "tokenes have sequential index in metadata" do
      node = Emitter.new(command: "echo a b c", chunker: Quantok.Chunker.Word)
      {:ok, tokenes} = Emitter.fire(node)

      indices = Enum.map(tokenes, & &1.metadata.index)
      assert indices == [0, 1, 2]
    end

    test "byte chunker splits to individual bytes" do
      node = Emitter.new(command: "echo hi", chunker: Quantok.Chunker.Byte)
      {:ok, tokenes} = Emitter.fire(node)

      assert length(tokenes) == 2
      assert Enum.all?(tokenes, &(&1.encoding == :byte))
    end

    test "rune chunker handles unicode" do
      node =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "cafe\u0301",
          chunker: Quantok.Chunker.Rune
        )

      {:ok, tokenes} = Emitter.fire(node)
      # "cafe\u0301" = 4 graphemes: c, a, f, e-with-accent
      assert length(tokenes) == 4
    end

    test "sentence chunker splits on sentence boundaries" do
      node =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "Hello world. Goodbye world!",
          chunker: Quantok.Chunker.Sentence
        )

      {:ok, tokenes} = Emitter.fire(node)
      assert length(tokenes) == 2
    end

    test "returns error for failed command" do
      node = Emitter.new(command: "exit 1")
      assert {:error, {1, _}} = Emitter.fire(node)
    end
  end
end
