defmodule Quantok.Node.Collector.Reverse do
  @moduledoc """
  Reverse collector action. Reverses the buffered text.
  """

  @spec process(binary(), binary()) :: binary()
  def process(_command, text), do: String.reverse(text)
end
