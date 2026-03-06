defmodule Quantok.Chunker.Ngram do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :ngram

  @impl true
  def chunk(binary) when is_binary(binary) do
    chunk(binary, 2)
  end

  @doc """
  Chunk into character n-grams of size n (sliding window).
  """
  @spec chunk(binary(), pos_integer()) :: [binary()]
  def chunk(<<>>, _n), do: []

  def chunk(binary, n) when is_binary(binary) and is_integer(n) and n > 0 do
    graphemes = String.graphemes(binary)

    if length(graphemes) < n do
      [binary]
    else
      graphemes
      |> Enum.chunk_every(n, 1, :discard)
      |> Enum.map(&Enum.join/1)
    end
  end
end
