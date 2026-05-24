defmodule Quantok.Chunker.Phrase do
  @moduledoc false

  @behaviour Quantok.Chunker

  # When no punctuation gives us natural phrase breaks, group words this many
  # at a time so a long bare string still produces phrase-sized chunks rather
  # than one sentence-sized chunk.
  @words_per_phrase 3

  @impl true
  def encoding, do: :phrase

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    ~r/\s*[,;:\-\(\)]\s*|\s+(?:and|or|but|so|yet|nor|for)\s+/i
    |> Regex.split(binary)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&split_long/1)
  end

  defp split_long(chunk) do
    words = String.split(chunk, ~r/\s+/, trim: true)

    if length(words) <= @words_per_phrase do
      [chunk]
    else
      words
      |> Enum.chunk_every(@words_per_phrase)
      |> Enum.map(&Enum.join(&1, " "))
    end
  end
end
