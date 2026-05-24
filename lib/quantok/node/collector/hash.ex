defmodule Quantok.Node.Collector.Hash do
  @moduledoc """
  Hash collector action. Computes a digest of the buffered text and outputs
  the hex string.

  Command field selects the algorithm: `md5`, `sha1`, `sha256`, `sha512`,
  `blake2b`. Defaults to `sha256`. With `emit: true` the collector becomes a
  data condenser — N tokenes in, one fixed-size hex tokene out.
  """

  @spec process(binary(), binary()) :: binary()
  def process(command, text) do
    algo = algo_for(command)

    algo
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp algo_for("md5"), do: :md5
  defp algo_for("sha1"), do: :sha
  defp algo_for("sha256"), do: :sha256
  defp algo_for("sha512"), do: :sha512
  defp algo_for("blake2b"), do: :blake2b
  defp algo_for(_), do: :sha256
end
