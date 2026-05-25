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
  - :decay - decay config for emitted tokenes (%{enabled, rate, shatter})
  """

  alias Quantok.{Node, Tokene}

  @type config :: %{
          optional(:source) => module(),
          optional(:command) => binary(),
          optional(:chunker) => module(),
          optional(:chunker_opts) => map(),
          optional(:emit_rate) => non_neg_integer(),
          optional(:auto_repeat) => boolean(),
          optional(:repeat_interval) => non_neg_integer(),
          optional(:decay) => map()
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
      repeat_interval: Keyword.get(opts, :repeat_interval, 3_000),
      decay: Keyword.get(opts, :decay, %{})
    }

    Node.new(:emitter, %{
      label: Keyword.get(opts, :label, "Emitter"),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Fires the emitter: executes the source, chunks the output, returns tokenes.
  Accepts optional world_decay config to merge with emitter decay config.
  """
  @spec fire(Node.t(), map()) :: {:ok, [Tokene.t()]} | {:error, term()}
  def fire(node, world_decay \\ %{})

  def fire(%Node{type: :emitter, config: config} = node, world_decay) do
    with {:ok, output} <- execute_source(config),
         chunks <- chunk_output(output, config) do
      decay_opts = resolve_decay(config, world_decay)

      tokenes =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, index} ->
          encoding = config.chunker.encoding()

          tokene = Tokene.new(chunk, encoding, source_id: node.id, decay: decay_opts)
          %{tokene | metadata: Map.put(tokene.metadata, :index, index)}
        end)

      {:ok, tokenes}
    end
  end

  # Merge world decay defaults with emitter-level overrides.
  # Emitter config takes precedence over world config.
  defp resolve_decay(emitter_config, world_decay) do
    emitter_decay = Map.get(emitter_config, :decay, %{})

    base = %{
      enabled: Map.get(world_decay, :enabled, false),
      rate: Map.get(world_decay, :rate, 1.0),
      shatter: Map.get(world_decay, :shatter, :split)
    }

    # Emitter overrides world defaults
    Map.merge(base, emitter_decay)
  end

  defp execute_source(%{source: __MODULE__.Emoji, command: command} = config) do
    __MODULE__.Emoji.execute(command, Map.get(config, :emoji_cursor, 0))
  end

  defp execute_source(%{source: source, command: command}) do
    source.execute(command)
  end

  defp chunk_output(output, %{chunker: chunker}) do
    chunker.chunk(output)
  end

  @doc """
  Post-fire hook: advances stateful cursors (currently just emoji source).
  Returns an updated node so the world genserver can swap it into state.
  """
  @spec after_fire(Node.t()) :: Node.t()
  def after_fire(%Node{type: :emitter, config: %{source: __MODULE__.Emoji, command: cmd} = config} = node) do
    case __MODULE__.Emoji.count(cmd) do
      0 ->
        node

      n ->
        cursor = Map.get(config, :emoji_cursor, 0)
        %{node | config: Map.put(config, :emoji_cursor, rem(cursor + 1, n))}
    end
  end

  def after_fire(node), do: node
end
