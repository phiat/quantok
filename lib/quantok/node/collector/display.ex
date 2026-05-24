defmodule Quantok.Node.Collector.Display do
  @moduledoc """
  Display collector action. Returns the buffered text for display, no processing.
  """

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, text, _buffer), do: text
end
