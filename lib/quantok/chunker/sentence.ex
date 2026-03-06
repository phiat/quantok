defmodule Quantok.Chunker.Sentence do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :sentence

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    # Split on sentence-ending punctuation followed by whitespace or end of string
    Regex.split(~r/(?<=[.!?])\s+/, binary)
    |> Enum.reject(&(&1 == ""))
  end
end
