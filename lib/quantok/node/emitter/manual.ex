defmodule Quantok.Node.Emitter.Manual do
  @moduledoc """
  Manual source for emitters. Returns the command string directly as output.
  Useful for testing and user text input.
  """

  @spec execute(binary()) :: {:ok, binary()}
  def execute(text) when is_binary(text), do: {:ok, text}
end
