defmodule Quantok.Node.Emitter.Clock do
  @moduledoc """
  Clock source for emitters. Returns the current formatted time.
  """

  @default_format "%Y-%m-%d %H:%M:%S"

  @spec execute(binary()) :: {:ok, binary()}
  def execute(format \\ @default_format)
  def execute(""), do: execute(@default_format)

  def execute(format) when is_binary(format),
    do: {:ok, Calendar.strftime(DateTime.utc_now(), format)}
end
