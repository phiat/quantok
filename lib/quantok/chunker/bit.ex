defmodule Quantok.Chunker.Bit do
  @moduledoc false

  @behaviour Quantok.Chunker
  import Bitwise

  @impl true
  def encoding, do: :bit

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    for <<byte <- binary>>, bit <- 7..0//-1 do
      <<byte >>> bit &&& 1::1>>
    end
  end
end
