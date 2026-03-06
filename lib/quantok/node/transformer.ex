defmodule Quantok.Node.Transformer do
  @moduledoc """
  Transformer nodes modify tokenes that enter their zone of effect.

  Config:
  - :effect - the transformation type
  - :radius - zone of effect radius
  - :strength - effect intensity (0.0-1.0)
  - :target_encoding - for :splitter/:retokenizer, the target encoding level
  - :pattern - for :filter, a regex pattern string
  """

  alias Quantok.Chunker
  alias Quantok.{Node, Tokene}

  @type effect ::
          :splitter
          | :crusher
          | :fuser
          | :heater
          | :cooler
          | :filter
          | :duplicator
          | :painter

  @doc """
  Creates a new transformer node.
  """
  @spec new(effect(), keyword()) :: Node.t()
  def new(effect, opts \\ []) do
    config = %{
      effect: effect,
      radius: Keyword.get(opts, :radius, 50.0),
      strength: Keyword.get(opts, :strength, 0.5),
      target_encoding: Keyword.get(opts, :target_encoding, nil),
      pattern: Keyword.get(opts, :pattern, nil),
      color: Keyword.get(opts, :color, nil)
    }

    Node.new(:transformer, %{
      label: Keyword.get(opts, :label, transformer_label(effect)),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Apply this transformer's effect to a tokene.
  Returns a list of resulting tokenes (may be 0, 1, or many).
  """
  @spec apply_effect(Node.t(), Tokene.t()) :: [Tokene.t()]
  def apply_effect(%Node{config: %{effect: :splitter}}, tokene) do
    if Tokene.splittable?(tokene) do
      child_enc = Tokene.child_encoding(tokene.encoding)
      chunker = chunker_for_encoding(child_enc)
      chunks = chunker.chunk(tokene.value)
      Enum.map(chunks, &Tokene.new(&1, child_enc, tokene.source_id))
    else
      [tokene]
    end
  end

  def apply_effect(%Node{config: %{effect: :crusher}}, tokene) do
    chunks = Chunker.Byte.chunk(tokene.value)
    Enum.map(chunks, &Tokene.new(&1, :byte, tokene.source_id))
  end

  def apply_effect(%Node{config: %{effect: :heater, strength: strength}}, tokene) do
    new_integrity = max(0.0, tokene.integrity - strength * 0.1)
    [%{tokene | integrity: new_integrity}]
  end

  def apply_effect(%Node{config: %{effect: :cooler, strength: strength}}, tokene) do
    new_integrity = min(1.0, tokene.integrity + strength * 0.1)
    [%{tokene | integrity: new_integrity}]
  end

  def apply_effect(%Node{config: %{effect: :filter, pattern: pattern}}, tokene) do
    if pattern && Regex.match?(Regex.compile!(pattern), tokene.value) do
      [tokene]
    else
      []
    end
  end

  def apply_effect(%Node{config: %{effect: :duplicator}}, tokene) do
    copy = Tokene.new(tokene.value, tokene.encoding, tokene.source_id)
    [tokene, copy]
  end

  def apply_effect(%Node{config: %{effect: :painter, color: color}}, tokene) do
    [%{tokene | metadata: Map.put(tokene.metadata, :color, color)}]
  end

  def apply_effect(_node, tokene), do: [tokene]

  defp chunker_for_encoding(:byte), do: Quantok.Chunker.Byte
  defp chunker_for_encoding(:rune), do: Quantok.Chunker.Rune
  defp chunker_for_encoding(:token), do: Quantok.Chunker.BPE
  defp chunker_for_encoding(:word), do: Quantok.Chunker.Word
  defp chunker_for_encoding(:phrase), do: Quantok.Chunker.Phrase
  defp chunker_for_encoding(:sentence), do: Quantok.Chunker.Sentence
  defp chunker_for_encoding(_), do: Quantok.Chunker.Byte

  defp transformer_label(:splitter), do: "Splitter"
  defp transformer_label(:crusher), do: "Crusher"
  defp transformer_label(:fuser), do: "Fuser"
  defp transformer_label(:heater), do: "Heater"
  defp transformer_label(:cooler), do: "Cooler"
  defp transformer_label(:filter), do: "Filter"
  defp transformer_label(:duplicator), do: "Duplicator"
  defp transformer_label(:painter), do: "Painter"
  defp transformer_label(effect), do: to_string(effect)
end
