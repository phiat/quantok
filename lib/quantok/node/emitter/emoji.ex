defmodule Quantok.Node.Emitter.Emoji do
  @moduledoc """
  Emoji source. The command is a string of one or more graphemes; each fire
  emits the grapheme at the current cursor and the world advances the cursor
  via `Emitter.after_fire/1`, so successive fires cycle through the list.
  """

  @spec execute(binary(), non_neg_integer()) :: {:ok, binary()}
  def execute(command, cursor \\ 0) when is_binary(command) do
    case String.graphemes(command) do
      [] -> {:ok, ""}
      runes -> {:ok, Enum.at(runes, rem(cursor, length(runes)))}
    end
  end

  @doc "Number of graphemes in the command — used to size the cursor modulus."
  @spec count(binary()) :: non_neg_integer()
  def count(command) when is_binary(command), do: length(String.graphemes(command))
end
