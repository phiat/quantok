defmodule Quantok.Node.Collector do
  @moduledoc """
  Collector nodes absorb tokenes into a buffer and trigger actions when conditions are met.

  Config:
  - :capacity - max buffer slots
  - :trigger_mode - :on_full | :manual | :timed
  - :tick_interval - physics ticks between auto-triggers (if :timed)
  - :action - module that processes buffer contents on trigger
  - :command - command string passed to action
  - :emit - whether to re-emit processed output as new tokenes (boolean)
  - :output_chunker - chunker for re-emitting output as tokenes (when emit is true)
  - :emit_rate - ms between tokene emissions (when emit is true)
  """

  alias Quantok.{Node, Tokene}

  @type trigger_mode :: :on_full | :manual | :timed

  @doc """
  Creates a new collector node.
  """
  @spec new(keyword()) :: Node.t()
  def new(opts \\ []) do
    config = %{
      capacity: Keyword.get(opts, :capacity, 8),
      trigger_mode: Keyword.get(opts, :trigger_mode, :on_full),
      tick_interval: Keyword.get(opts, :tick_interval, 120),
      action: Keyword.get(opts, :action, __MODULE__.Echo),
      command: Keyword.get(opts, :command, "echo"),
      emit: Keyword.get(opts, :emit, false),
      output_chunker: Keyword.get(opts, :output_chunker, nil),
      emit_rate: Keyword.get(opts, :emit_rate, 250),
      buffer: [],
      ticks_since_trigger: 0
    }

    Node.new(:collector, %{
      label: Keyword.get(opts, :label, "Collector"),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Absorb a tokene into the buffer. Returns updated node and whether the buffer is now full.
  """
  @spec absorb(Node.t(), Tokene.t()) :: {:ok, Node.t()} | {:full, Node.t()}
  def absorb(%Node{type: :collector, config: config} = node, tokene) do
    buffer = config.buffer ++ [tokene]

    updated =
      %{node | config: %{config | buffer: buffer}}

    if length(buffer) >= config.capacity do
      {:full, updated}
    else
      {:ok, updated}
    end
  end

  @doc """
  Returns the current buffer contents as a concatenated string.
  """
  @spec buffer_text(Node.t()) :: binary()
  def buffer_text(%Node{type: :collector, config: %{buffer: buffer}}) do
    # display_value/1 renders bits as "0"/"1" and sub-UTF-8 byte chunks as
    # hex, so the action layer always receives a regular binary instead of
    # an unprintable bitstring or invalid UTF-8.
    Enum.map_join(buffer, &Tokene.display_value/1)
  end

  @doc """
  Returns the number of occupied buffer slots.
  """
  @spec buffer_count(Node.t()) :: non_neg_integer()
  def buffer_count(%Node{type: :collector, config: %{buffer: buffer}}) do
    length(buffer)
  end

  @doc """
  Trigger the collector: process buffer contents and clear the buffer.
  Returns `{:ok, output, cleared_node}` when emit is false,
  or `{:ok, output, cleared_node, tokenes}` when emit is true.
  """
  @spec trigger(Node.t(), map()) ::
          {:ok, binary(), Node.t()}
          | {:ok, binary(), Node.t(), [Tokene.t()]}
  def trigger(node, world_decay \\ %{})

  def trigger(%Node{type: :collector, config: config} = node, world_decay) do
    text = buffer_text(node)
    output = config.action.process(config.command, text, config.buffer)
    cleared = %{node | config: %{config | buffer: [], ticks_since_trigger: 0}}

    if config.emit and config.output_chunker != nil do
      chunks = config.output_chunker.chunk(output)
      encoding = config.output_chunker.encoding()

      tokenes =
        Enum.map(chunks, &Tokene.new(&1, encoding, source_id: node.id, decay: world_decay))

      {:ok, output, cleared, tokenes}
    else
      {:ok, output, cleared}
    end
  end

  @doc """
  Clear the buffer without triggering.
  """
  @spec clear(Node.t()) :: Node.t()
  def clear(%Node{type: :collector, config: config} = node) do
    %{node | config: %{config | buffer: []}}
  end

  @doc """
  Returns true if the buffer is full.
  """
  @spec full?(Node.t()) :: boolean()
  def full?(%Node{type: :collector, config: config}) do
    length(config.buffer) >= config.capacity
  end

  @doc """
  Advance the tick counter. Returns `{:trigger, updated_node}` if a timed
  trigger is due (buffer non-empty and tick threshold reached), otherwise
  `{:ok, updated_node}`.

  The counter only advances while the buffer is non-empty: the interval is
  "time since data first arrived," not a free-running heartbeat. Without this,
  a long idle period would pre-charge the counter and cause the first absorbed
  tokene to trigger almost immediately.
  """
  @spec tick(Node.t()) :: {:ok, Node.t()} | {:trigger, Node.t()}
  def tick(%Node{type: :collector, config: %{trigger_mode: :timed, buffer: []}} = node) do
    {:ok, node}
  end

  def tick(%Node{type: :collector, config: %{trigger_mode: :timed} = config} = node) do
    ticks = config.ticks_since_trigger + 1

    if ticks >= config.tick_interval do
      {:trigger, %{node | config: %{config | ticks_since_trigger: ticks}}}
    else
      {:ok, %{node | config: %{config | ticks_since_trigger: ticks}}}
    end
  end

  def tick(%Node{type: :collector} = node), do: {:ok, node}
end
