defmodule Quantok.Chunker.Byte do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :byte

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    for <<byte <- binary>>, do: <<byte>>
  end
end
