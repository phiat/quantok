defmodule Quantok.Node.Emitter.Sequence do
  @moduledoc """
  Sequence source for emitters. Returns incrementing numbers or alphabet sequences.
  Useful for testing and demos.
  """

  @spec execute(binary()) :: {:ok, binary()}
  def execute("alpha"), do: {:ok, Enum.map_join(?A..?Z, " ", &<<&1>>)}
  def execute("digits"), do: {:ok, Enum.map_join(0..9, " ", &to_string/1)}

  def execute(n) when is_binary(n) do
    count = String.to_integer(n)
    {:ok, Enum.map_join(1..count, " ", &to_string/1)}
  rescue
    _ -> {:ok, "1 2 3 4 5"}
  end
end
