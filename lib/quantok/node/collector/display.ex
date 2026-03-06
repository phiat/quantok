defmodule Quantok.Node.Collector.Display do
  @moduledoc """
  Display collector action. Returns the buffered text for display, no processing.
  """

  @spec process(binary(), binary()) :: binary()
  def process(_command, text), do: text
end
