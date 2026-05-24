defmodule Quantok.Node.Collector.Count do
  @moduledoc """
  Count collector action. Returns the byte size and character count of buffered text.
  """

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, text, _buffer) do
    bytes = byte_size(text)
    chars = String.length(text)
    "#{chars} chars, #{bytes} bytes"
  end
end
