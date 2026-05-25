defmodule Quantok.Node.Transformer do
  @moduledoc """
  Transformer nodes modify tokenes that enter their zone of effect.

  Config:
  - :effect - the transformation type
  - :radius - zone of effect radius
  - :strength - effect intensity (0.0-1.0 for integrity ops, px/s² for :magnet)
  - :target_encoding - for :splitter/:retokenizer/:magnet, the target encoding level
  - :pattern - for :filter/:magnet, a regex pattern string
  - :polarity - for :magnet, :attract (pulls toward center) or :repel (pushes away)
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
          | :tiktoken
          | :magnet

  @type polarity :: :attract | :repel

  @doc """
  Creates a new transformer node.
  """
  @spec new(effect(), keyword()) :: Node.t()
  def new(effect, opts \\ []) do
    pattern = Keyword.get(opts, :pattern, nil)

    config = %{
      effect: effect,
      radius: Keyword.get(opts, :radius, default_radius(effect)),
      strength: Keyword.get(opts, :strength, default_strength(effect)),
      target_encoding: Keyword.get(opts, :target_encoding, nil),
      pattern: pattern,
      compiled_pattern: compile_pattern(pattern),
      polarity: Keyword.get(opts, :polarity, :attract),
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

  # Already-encoded token ids are a fixed point — encoding again would
  # re-tokenize the digit string into more ids and cascade exponentially.
  def apply_effect(%Node{config: %{effect: :tiktoken}}, %Tokene{encoding: :token_id} = tokene),
    do: [tokene]

  def apply_effect(%Node{config: %{effect: :tiktoken}}, tokene) do
    tokene.value
    |> Tiktokenex.encode()
    |> Enum.map(&Tokene.new(Integer.to_string(&1), :token_id, tokene.source_id))
  rescue
    _ -> [tokene]
  end

  def apply_effect(%Node{config: %{effect: :heater, strength: strength}}, tokene) do
    new_integrity = max(0.0, tokene.integrity - strength * 0.1)
    [%{tokene | integrity: new_integrity}]
  end

  def apply_effect(%Node{config: %{effect: :cooler, strength: strength}}, tokene) do
    new_integrity = min(1.0, tokene.integrity + strength * 0.1)
    [%{tokene | integrity: new_integrity}]
  end

  def apply_effect(%Node{config: %{effect: :filter, compiled_pattern: %Regex{} = regex}}, tokene) do
    if Regex.match?(regex, tokene.value), do: [tokene], else: []
  end

  def apply_effect(%Node{config: %{effect: :filter}}, tokene), do: [tokene]

  def apply_effect(%Node{config: %{effect: :duplicator}}, tokene) do
    copy = Tokene.new(tokene.value, tokene.encoding, tokene.source_id)
    [tokene, copy]
  end

  def apply_effect(%Node{config: %{effect: :painter, color: color}}, tokene) do
    [%{tokene | metadata: Map.put(tokene.metadata, :color, color)}]
  end

  # Magnet: no-op on the server. The visual zone, regex match, and continuous
  # radial force are all computed client-side per frame (see world_hook.js).
  def apply_effect(%Node{config: %{effect: :magnet}}, tokene), do: [tokene]

  def apply_effect(_node, tokene), do: [tokene]

  defp chunker_for_encoding(:byte), do: Quantok.Chunker.Byte
  defp chunker_for_encoding(:rune), do: Quantok.Chunker.Rune
  defp chunker_for_encoding(:token), do: Quantok.Chunker.BPE
  defp chunker_for_encoding(:word), do: Quantok.Chunker.Word
  defp chunker_for_encoding(:phrase), do: Quantok.Chunker.Phrase
  defp chunker_for_encoding(:sentence), do: Quantok.Chunker.Sentence
  defp chunker_for_encoding(_), do: Quantok.Chunker.Byte

  defp compile_pattern(nil), do: nil

  defp compile_pattern(pattern) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> regex
      {:error, _} -> nil
    end
  end

  defp transformer_label(:splitter), do: "Splitter"
  defp transformer_label(:crusher), do: "Crusher"
  defp transformer_label(:fuser), do: "Fuser"
  defp transformer_label(:heater), do: "Heater"
  defp transformer_label(:cooler), do: "Cooler"
  defp transformer_label(:filter), do: "Filter"
  defp transformer_label(:duplicator), do: "Duplicator"
  defp transformer_label(:painter), do: "Painter"
  defp transformer_label(:magnet), do: "Magnet"
  defp transformer_label(effect), do: to_string(effect)

  # Magnets reach further (positional force) and use much higher "strength"
  # values since they're px/s² accelerations rather than 0..1 integrity deltas.
  # Default strength is ~4× gravity (150 px/s²) so the pull is clearly visible
  # against a falling tokene even at half-radius (where falloff = 0.5).
  defp default_radius(:magnet), do: 150.0
  defp default_radius(_), do: 50.0

  defp default_strength(:magnet), do: 600.0
  defp default_strength(_), do: 0.5
end
