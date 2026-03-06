defmodule Quantok.TokeneTest do
  use ExUnit.Case, async: true

  alias Quantok.Tokene

  describe "new/3" do
    test "creates a tokene with correct defaults" do
      t = Tokene.new("hello", :word, "emitter-1")

      assert t.value == "hello"
      assert t.encoding == :word
      assert t.byte_size == 5
      assert t.integrity == 0.4
      assert t.source_id == "emitter-1"
      assert is_binary(t.id)
    end

    test "sets integrity based on encoding" do
      assert Tokene.new("x", :bit).integrity == 1.0
      assert Tokene.new("x", :byte).integrity == 0.95
      assert Tokene.new("x", :rune).integrity == 0.8
      assert Tokene.new("x", :token).integrity == 0.6
      assert Tokene.new("x", :word).integrity == 0.4
      assert Tokene.new("x", :phrase).integrity == 0.2
      assert Tokene.new("x", :sentence).integrity == 0.1
    end

    test "computes byte_size from value" do
      assert Tokene.new("", :byte).byte_size == 0
      assert Tokene.new("a", :byte).byte_size == 1
      assert Tokene.new("hello", :word).byte_size == 5
      # Multi-byte unicode (fire emoji = 4 bytes UTF-8)
      assert Tokene.new("\u{1F525}", :rune).byte_size == 4
    end
  end

  describe "child_encoding/1" do
    test "returns next level down" do
      assert Tokene.child_encoding(:sentence) == :phrase
      assert Tokene.child_encoding(:phrase) == :word
      assert Tokene.child_encoding(:word) == :token
      assert Tokene.child_encoding(:token) == :rune
      assert Tokene.child_encoding(:rune) == :byte
      assert Tokene.child_encoding(:byte) == :bit
    end

    test "returns nil for atomic level" do
      assert Tokene.child_encoding(:bit) == nil
    end
  end

  describe "parent_encoding/1" do
    test "returns next level up" do
      assert Tokene.parent_encoding(:bit) == :byte
      assert Tokene.parent_encoding(:byte) == :rune
      assert Tokene.parent_encoding(:word) == :phrase
    end

    test "returns nil for top level" do
      assert Tokene.parent_encoding(:sentence) == nil
    end
  end

  describe "mass/1" do
    test "larger tokenes have more mass" do
      small = Tokene.new("a", :byte)
      large = Tokene.new("hello world this is a sentence", :sentence)

      assert Tokene.mass(large) > Tokene.mass(small)
    end

    test "mass is always positive" do
      empty = Tokene.new("", :byte)
      assert Tokene.mass(empty) > 0
    end
  end

  describe "dimensions/1" do
    test "larger tokenes have bigger dimensions" do
      small = Tokene.new("a", :byte)
      large = Tokene.new("hello world", :word)

      {sw, _sh} = Tokene.dimensions(small)
      {lw, _lh} = Tokene.dimensions(large)

      assert lw > sw
    end

    test "dimensions have minimum sizes" do
      tiny = Tokene.new("", :bit)
      {w, h} = Tokene.dimensions(tiny)

      assert w >= 14.0
      assert h >= 12.0
    end
  end

  describe "splittable?/1" do
    test "bits cannot be split" do
      refute Tokene.splittable?(Tokene.new("x", :bit))
    end

    test "single bytes cannot be split" do
      refute Tokene.splittable?(Tokene.new("x", :byte))
    end

    test "multi-byte bytes can be split" do
      assert Tokene.splittable?(Tokene.new("hello", :byte))
    end

    test "words can be split" do
      assert Tokene.splittable?(Tokene.new("hello", :word))
    end
  end

  describe "unique IDs" do
    test "each tokene gets a unique id" do
      ids = for _ <- 1..100, do: Tokene.new("x", :byte).id
      assert length(Enum.uniq(ids)) == 100
    end
  end
end
