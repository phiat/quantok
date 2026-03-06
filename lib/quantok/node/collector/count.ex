defmodule Quantok.Node.Collector.Count do
  @moduledoc """
  Count collector action. Returns the byte size and character count of buffered text.
  """

  @spec process(binary(), binary()) :: binary()
  def process(_command, text) do
    bytes = byte_size(text)
    chars = String.length(text)
    "#{chars} chars, #{bytes} bytes"
  end
end
