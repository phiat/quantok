defmodule Quantok.Node.Emitter.Random do
  @moduledoc """
  Random source for emitters. Emits N bytes drawn from a configurable charset.

  Command format: `<charset>:<count>` (e.g. `"alnum:64"`, `"hex:32"`).
  Charsets: `alpha`, `alnum`, `printable`, `hex`, `binary`.
  Defaults to `"alnum:32"`.
  """

  @alpha ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @alnum @alpha ++ ~c"0123456789"
  @printable Enum.to_list(?!..?~)
  @hex ~c"0123456789abcdef"

  @spec execute(binary()) :: {:ok, binary()}
  def execute(command \\ "alnum:32") when is_binary(command) do
    {charset, count} = parse(command)
    {:ok, generate(charset, max(count, 0))}
  end

  defp parse(command) do
    case String.split(command, ":", parts: 2) do
      [charset, count_str] -> {charset, parse_count(count_str)}
      [charset] -> {charset, 32}
    end
  end

  defp parse_count(s) do
    case Integer.parse(s) do
      {n, _} when n > 0 and n <= 4096 -> n
      _ -> 32
    end
  end

  defp generate("binary", n), do: :crypto.strong_rand_bytes(n)
  defp generate("hex", n), do: random_from(@hex, n)
  defp generate("printable", n), do: random_from(@printable, n)
  defp generate("alpha", n), do: random_from(@alpha, n)
  defp generate(_, n), do: random_from(@alnum, n)

  defp random_from(charset, n) do
    size = length(charset)
    charset_tuple = List.to_tuple(charset)

    bytes = :crypto.strong_rand_bytes(n)

    bytes
    |> :binary.bin_to_list()
    |> Enum.map_join(fn b -> <<elem(charset_tuple, rem(b, size))>> end)
  end
end
