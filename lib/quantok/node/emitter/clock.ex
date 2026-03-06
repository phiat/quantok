defmodule Quantok.Node.Emitter.Clock do
  @moduledoc """
  Clock source for emitters. Returns the current formatted time.
  """

  @spec execute(binary()) :: {:ok, binary()}
  def execute(format \\ "%Y-%m-%d %H:%M:%S") do
    {:ok, Calendar.strftime(DateTime.utc_now(), format)}
  end
end
