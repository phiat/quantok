defmodule Quantok.Node.Collector.Reverse do
  @moduledoc """
  Reverse collector action. Reverses the buffered text.
  """

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, text, _buffer), do: String.reverse(text)
end
