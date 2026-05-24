defmodule Quantok.ChunkerTest do
  use ExUnit.Case, async: true

  alias Quantok.Chunker

  describe "Bit chunker" do
    test "splits into individual bits" do
      # "A" = 0x41 = 0b01000001
      chunks = Chunker.Bit.chunk("A")
      assert length(chunks) == 8
      assert Enum.map(chunks, &bit_size/1) |> Enum.all?(&(&1 == 1))
    end

    test "empty input" do
      assert Chunker.Bit.chunk("") == []
    end

    test "encoding is :bit" do
      assert Chunker.Bit.encoding() == :bit
    end
  end

  describe "Byte chunker" do
    test "splits into individual bytes" do
      assert Chunker.Byte.chunk("abc") == ["a", "b", "c"]
    end

    test "handles multi-byte unicode as raw bytes" do
      # euro sign is 3 bytes in UTF-8
      chunks = Chunker.Byte.chunk("\u20AC")
      assert length(chunks) == 3
    end

    test "empty input" do
      assert Chunker.Byte.chunk("") == []
    end

    test "encoding is :byte" do
      assert Chunker.Byte.encoding() == :byte
    end
  end

  describe "Rune chunker" do
    test "splits into grapheme clusters" do
      assert Chunker.Rune.chunk("hello") == ["h", "e", "l", "l", "o"]
    end

    test "keeps combined emoji as single chunk" do
      # Family emoji (ZWJ sequence)
      chunks = Chunker.Rune.chunk("\u{1F468}\u200D\u{1F469}\u200D\u{1F467}")
      assert length(chunks) == 1
    end

    test "handles accented characters" do
      # e + combining accent = one grapheme
      chunks = Chunker.Rune.chunk("e\u0301")
      assert length(chunks) == 1
    end

    test "empty input" do
      assert Chunker.Rune.chunk("") == []
    end

    test "encoding is :rune" do
      assert Chunker.Rune.encoding() == :rune
    end
  end

  describe "Word chunker" do
    test "splits on spaces by default" do
      assert Chunker.Word.chunk("hello world") == ["hello", "world"]
    end

    test "handles multiple spaces" do
      assert Chunker.Word.chunk("hello  world") == ["hello", "world"]
    end

    test "splits on tabs and newlines" do
      assert Chunker.Word.chunk("hello\tworld\nfoo") == ["hello", "world", "foo"]
    end

    test "custom delimiter" do
      assert Chunker.Word.chunk("a,b,c", ",") == ["a", "b", "c"]
    end

    test "empty input" do
      assert Chunker.Word.chunk("") == []
    end

    test "encoding is :word" do
      assert Chunker.Word.encoding() == :word
    end
  end

  describe "Ngram chunker" do
    test "splits into bigrams by default" do
      assert Chunker.Ngram.chunk("abcd") == ["ab", "bc", "cd"]
    end

    test "trigrams" do
      assert Chunker.Ngram.chunk("abcd", 3) == ["abc", "bcd"]
    end

    test "input shorter than n returns whole string" do
      assert Chunker.Ngram.chunk("ab", 5) == ["ab"]
    end

    test "empty input" do
      assert Chunker.Ngram.chunk("") == []
    end

    test "encoding is :ngram" do
      assert Chunker.Ngram.encoding() == :ngram
    end
  end

  describe "Sentence chunker" do
    test "splits on sentence boundaries" do
      input = "Hello world. How are you? I'm fine!"
      chunks = Chunker.Sentence.chunk(input)
      assert chunks == ["Hello world.", "How are you?", "I'm fine!"]
    end

    test "single sentence stays whole" do
      assert Chunker.Sentence.chunk("Hello world") == ["Hello world"]
    end

    test "empty input" do
      assert Chunker.Sentence.chunk("") == []
    end

    test "encoding is :sentence" do
      assert Chunker.Sentence.encoding() == :sentence
    end
  end

  describe "Phrase chunker" do
    test "splits on commas" do
      chunks = Chunker.Phrase.chunk("hello, world, foo")
      assert chunks == ["hello", "world", "foo"]
    end

    test "splits on semicolons" do
      chunks = Chunker.Phrase.chunk("a; b; c")
      assert chunks == ["a", "b", "c"]
    end

    test "splits on conjunctions" do
      assert Chunker.Phrase.chunk("rise and shine") == ["rise", "shine"]
      assert Chunker.Phrase.chunk("now or never") == ["now", "never"]
    end

    test "groups bare strings into phrase-sized chunks" do
      # Without punctuation or conjunctions, bare text gets grouped a few words
      # at a time so a long string still emits phrase-sized tokenes rather than
      # one sentence-sized blob.
      assert Chunker.Phrase.chunk("hello world") == ["hello world"]

      assert Chunker.Phrase.chunk("the quick brown fox jumps over the lazy dog") ==
               ["the quick brown", "fox jumps over", "the lazy dog"]
    end

    test "empty input" do
      assert Chunker.Phrase.chunk("") == []
    end

    test "encoding is :phrase" do
      assert Chunker.Phrase.encoding() == :phrase
    end
  end

  describe "all chunkers produce non-empty output for non-empty input" do
    @inputs ["hello", "Hello world. Goodbye!", "a,b;c", ""]

    for mod <- [
          Chunker.Bit,
          Chunker.Byte,
          Chunker.Rune,
          Chunker.Word,
          Chunker.Ngram,
          Chunker.Sentence,
          Chunker.Phrase
        ] do
      test "#{inspect(mod)} handles various inputs" do
        for input <- @inputs do
          chunks = unquote(mod).chunk(input)
          assert is_list(chunks)

          if input == "" do
            assert chunks == []
          else
            assert chunks != [], "#{inspect(unquote(mod))} returned empty for #{inspect(input)}"
          end
        end
      end
    end
  end
end
