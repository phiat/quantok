defmodule Quantok.Node.TransformerTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Transformer
  alias Quantok.Tokene

  describe "splitter" do
    test "splits a sentence into phrases" do
      node = Transformer.new(:splitter)
      tokene = Tokene.new("hello, world; goodbye", :sentence)

      result = Transformer.apply_effect(node, tokene)
      assert length(result) == 3
      assert Enum.all?(result, &(&1.encoding == :phrase))
    end

    test "splits a phrase into words" do
      node = Transformer.new(:splitter)
      tokene = Tokene.new("hello world", :phrase)

      result = Transformer.apply_effect(node, tokene)
      assert length(result) == 2
      assert Enum.all?(result, &(&1.encoding == :word))
    end

    test "does not split a bit" do
      node = Transformer.new(:splitter)
      tokene = Tokene.new(<<1::1>>, :bit)

      result = Transformer.apply_effect(node, tokene)
      assert length(result) == 1
    end
  end

  describe "crusher" do
    test "breaks tokene into individual bytes" do
      node = Transformer.new(:crusher)
      tokene = Tokene.new("hello", :word)

      result = Transformer.apply_effect(node, tokene)
      assert length(result) == 5
      assert Enum.all?(result, &(&1.encoding == :byte))
    end
  end

  describe "heater" do
    test "reduces integrity" do
      node = Transformer.new(:heater, strength: 1.0)
      tokene = Tokene.new("hello", :word)
      original_integrity = tokene.integrity

      [heated] = Transformer.apply_effect(node, tokene)
      assert heated.integrity < original_integrity
    end
  end

  describe "cooler" do
    test "increases integrity" do
      node = Transformer.new(:cooler, strength: 1.0)
      tokene = Tokene.new("hello", :word)
      original_integrity = tokene.integrity

      [cooled] = Transformer.apply_effect(node, tokene)
      assert cooled.integrity > original_integrity
    end

    test "caps at 1.0" do
      node = Transformer.new(:cooler, strength: 1.0)
      tokene = %{Tokene.new("x", :byte) | integrity: 0.99}

      [cooled] = Transformer.apply_effect(node, tokene)
      assert cooled.integrity <= 1.0
    end
  end

  describe "filter" do
    test "passes matching tokenes" do
      node = Transformer.new(:filter, pattern: "^h")
      tokene = Tokene.new("hello", :word)

      assert [^tokene] = Transformer.apply_effect(node, tokene)
    end

    test "blocks non-matching tokenes" do
      node = Transformer.new(:filter, pattern: "^h")
      tokene = Tokene.new("world", :word)

      assert [] = Transformer.apply_effect(node, tokene)
    end

    test "invalid regex pattern passes all tokenes through" do
      node = Transformer.new(:filter, pattern: "[invalid")
      tokene = Tokene.new("hello", :word)

      assert [^tokene] = Transformer.apply_effect(node, tokene)
    end

    test "compiled regex is stored in config" do
      node = Transformer.new(:filter, pattern: "^h")
      assert %Regex{} = node.config.compiled_pattern
    end
  end

  describe "duplicator" do
    test "produces two tokenes" do
      node = Transformer.new(:duplicator)
      tokene = Tokene.new("hello", :word)

      result = Transformer.apply_effect(node, tokene)
      assert length(result) == 2
      assert Enum.all?(result, &(&1.value == "hello"))
    end

    test "copy has different id" do
      node = Transformer.new(:duplicator)
      tokene = Tokene.new("hello", :word)

      [original, copy] = Transformer.apply_effect(node, tokene)
      assert original.id != copy.id
    end
  end

  describe "painter" do
    test "adds color to metadata" do
      node = Transformer.new(:painter, color: "red")
      tokene = Tokene.new("hello", :word)

      [painted] = Transformer.apply_effect(node, tokene)
      assert painted.metadata.color == "red"
    end
  end
end
