defmodule Quantok.Node.Emitter do
  @moduledoc """
  Emitter nodes produce tokenes by executing a source and chunking the output.

  Config:
  - :source - the source module (e.g., Quantok.Node.Emitter.Shell)
  - :command - the command or data to produce output from
  - :chunker - the chunker module to split output into tokenes
  - :chunker_opts - options for the chunker (e.g., delimiter for Word)
  - :emit_rate - milliseconds between tokene emissions (for staggered output)
  - :auto_repeat - whether to re-fire automatically on a timer
  - :repeat_interval - ms between auto-fires (if auto_repeat is true)
  """

  alias Quantok.{Node, Tokene}

  @type config :: %{
          optional(:source) => module(),
          optional(:command) => binary(),
          optional(:chunker) => module(),
          optional(:chunker_opts) => map(),
          optional(:emit_rate) => non_neg_integer(),
          optional(:auto_repeat) => boolean(),
          optional(:repeat_interval) => non_neg_integer()
        }

  @doc """
  Creates a new emitter node.
  """
  @spec new(keyword()) :: Node.t()
  def new(opts \\ []) do
    config = %{
      source: Keyword.get(opts, :source, __MODULE__.Shell),
      command: Keyword.get(opts, :command, "echo hello"),
      chunker: Keyword.get(opts, :chunker, Quantok.Chunker.Word),
      chunker_opts: Keyword.get(opts, :chunker_opts, %{}),
      emit_rate: Keyword.get(opts, :emit_rate, 250),
      auto_repeat: Keyword.get(opts, :auto_repeat, false),
      repeat_interval: Keyword.get(opts, :repeat_interval, 5000)
    }

    Node.new(:emitter, %{
      label: Keyword.get(opts, :label, "Emitter"),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Fires the emitter: executes the source, chunks the output, returns tokenes.
  """
  @spec fire(Node.t()) :: {:ok, [Tokene.t()]} | {:error, term()}
  def fire(%Node{type: :emitter, config: config} = node) do
    with {:ok, output} <- execute_source(config),
         chunks <- chunk_output(output, config) do
      tokenes =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, index} ->
          encoding = config.chunker.encoding()

          tokene = Tokene.new(chunk, encoding, node.id)
          %{tokene | metadata: Map.put(tokene.metadata, :index, index)}
        end)

      {:ok, tokenes}
    end
  end

  defp execute_source(%{source: source, command: command}) do
    source.execute(command)
  end

  defp chunk_output(output, %{chunker: chunker}) do
    chunker.chunk(output)
  end
end
