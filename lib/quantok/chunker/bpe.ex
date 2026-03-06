defmodule Quantok.Chunker.BPE do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :token

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    Tiktokenex.encode_to_chunks(binary)
  end
end
