defmodule Quantok.Chunker do
  @moduledoc """
  Behaviour for chunking binary data into pieces.

  Each chunker splits input into a list of binaries using a different strategy.
  The encoding atom identifies what kind of chunks are produced.
  """

  @type encoding :: Quantok.Tokene.encoding()

  @callback chunk(binary()) :: [binary()]
  @callback encoding() :: encoding()
end
