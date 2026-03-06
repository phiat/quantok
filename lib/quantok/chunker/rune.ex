defmodule Quantok.Chunker.Rune do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :rune

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    String.graphemes(binary)
  end
end
