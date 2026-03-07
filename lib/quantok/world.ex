defmodule Quantok.World do
  @moduledoc """
  Central world state manager. Maintains nodes, active tokenes, and environment
  config. All state changes are recorded as events — the world state is a
  projection (fold) over its event log. Dispatches events to connected clients
  via PubSub.
  """

  use GenServer

  alias Quantok.Node
  alias Quantok.Node.{Collector, Emitter, Transformer}
  alias Quantok.Tokene
  alias Quantok.World.Event

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t(),
          nodes: %{binary() => Node.t()},
          tokenes: %{binary() => Tokene.t()},
          environment: map(),
          tick_count: non_neg_integer(),
          paused: boolean()
        }

  defstruct [
    :id,
    name: "Untitled World",
    nodes: %{},
    tokenes: %{},
    environment: %{
      gravity: {0.0, 9.81},
      tick_rate: 30,
      decay: %{enabled: false, rate: 1.0, shatter: :split}
    },
    tick_count: 0,
    paused: false
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get_state(server), do: GenServer.call(server, :get_state)
  def get_events(server), do: GenServer.call(server, :get_events)
  def get_events(server, opts), do: GenServer.call(server, {:get_events, opts})

  def add_node(server, node), do: GenServer.call(server, {:add_node, node})
  def remove_node(server, node_id), do: GenServer.call(server, {:remove_node, node_id})

  def update_node(server, node_id, updates),
    do: GenServer.call(server, {:update_node, node_id, updates})

  def fire_emitter(server, emitter_id),
    do: GenServer.call(server, {:fire_emitter, emitter_id})

  def absorb_tokene(server, collector_id, tokene_id),
    do: GenServer.call(server, {:absorb_tokene, collector_id, tokene_id})

  def apply_transformer(server, transformer_id, tokene_id),
    do: GenServer.call(server, {:apply_transformer, transformer_id, tokene_id})

  def trigger_collector(server, collector_id),
    do: GenServer.call(server, {:trigger_collector, collector_id})

  def remove_tokene(server, tokene_id),
    do: GenServer.call(server, {:remove_tokene, tokene_id})

  def update_node_position(server, node_id, position),
    do: GenServer.call(server, {:update_node_position, node_id, position})

  def clear_collector(server, collector_id),
    do: GenServer.call(server, {:clear_collector, collector_id})

  def rotate_passive(server, node_id),
    do: GenServer.call(server, {:rotate_passive, node_id})

  def pause(server), do: GenServer.cast(server, :pause)
  def resume(server), do: GenServer.cast(server, :resume)

  def set_gravity(server, gravity),
    do: GenServer.cast(server, {:set_gravity, gravity})

  def set_decay(server, decay_config),
    do: GenServer.cast(server, {:set_decay, decay_config})

  def tick(server), do: GenServer.cast(server, :tick)

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    world = %__MODULE__{
      id: generate_id(),
      name: Keyword.get(opts, :world_name, "Untitled World")
    }

    {:ok, {world, []}}
  end

  @impl true
  def handle_call(:get_state, _from, {world, _events} = state) do
    {:reply, world, state}
  end

  def handle_call(:get_events, _from, {_world, events} = state) do
    {:reply, Enum.reverse(events), state}
  end

  def handle_call({:get_events, opts}, _from, {_world, events} = state) do
    result = filter_events(Enum.reverse(events), opts)
    {:reply, result, state}
  end

  def handle_call({:add_node, node}, _from, {world, events}) do
    event = {:node_added, node, now()}
    world = Event.apply(world, event)
    broadcast(world, {:node_added, node})
    {:reply, {:ok, node}, {world, [event | events]}}
  end

  def handle_call({:remove_node, node_id}, _from, {world, events}) do
    removed = Map.get(world.nodes, node_id)
    event = {:node_removed, node_id, now()}
    world = Event.apply(world, event)

    if removed, do: broadcast(world, {:node_removed, node_id})
    {:reply, {:ok, removed}, {world, [event | events]}}
  end

  def handle_call({:update_node, node_id, updates}, _from, {world, events}) do
    case Map.get(world.nodes, node_id) do
      nil ->
        {:reply, {:error, :not_found}, {world, events}}

      node ->
        updated = struct(node, updates)
        event = {:node_updated, updated, now()}
        world = Event.apply(world, event)
        broadcast(world, {:node_updated, updated})
        {:reply, {:ok, updated}, {world, [event | events]}}
    end
  end

  def handle_call({:fire_emitter, emitter_id}, _from, {world, events}) do
    with %Node{type: :emitter} = node <- Map.get(world.nodes, emitter_id),
         {:ok, tokenes} <- Emitter.fire(node, Map.get(world.environment, :decay, %{})) do
      event = {:emitted, emitter_id, tokenes, now()}
      world = Event.apply(world, event)
      broadcast(world, {:emit, emitter_id, tokenes})
      {:reply, {:ok, tokenes}, {world, [event | events]}}
    else
      nil -> {:reply, {:error, :not_found}, {world, events}}
      {:error, reason} -> {:reply, {:error, reason}, {world, events}}
    end
  end

  def handle_call({:absorb_tokene, collector_id, tokene_id}, _from, {world, events}) do
    with %Node{type: :collector} = collector <- Map.get(world.nodes, collector_id),
         false <- Collector.full?(collector),
         %Tokene{} = tokene <- Map.get(world.tokenes, tokene_id) do
      {status, updated_collector} = Collector.absorb(collector, tokene)

      event = {:absorbed, collector_id, tokene_id, updated_collector, now()}
      world = Event.apply(world, event)
      events = [event | events]

      {world, events} = maybe_auto_trigger(world, events, status, updated_collector, collector_id)
      broadcast(world, {:absorb, collector_id, tokene_id})
      {:reply, {:ok, status}, {world, events}}
    else
      true -> {:reply, {:error, :full}, {world, events}}
      _ -> {:reply, {:error, :not_found}, {world, events}}
    end
  end

  def handle_call({:apply_transformer, transformer_id, tokene_id}, _from, {world, events}) do
    with %Node{type: :transformer} = transformer <- Map.get(world.nodes, transformer_id),
         %Tokene{} = tokene <- Map.get(world.tokenes, tokene_id) do
      result_tokenes = Transformer.apply_effect(transformer, tokene)

      event = {:transformed, transformer_id, tokene_id, result_tokenes, now()}
      world = Event.apply(world, event)
      broadcast(world, {:transform, transformer_id, tokene_id, result_tokenes})
      {:reply, {:ok, result_tokenes}, {world, [event | events]}}
    else
      _ -> {:reply, {:error, :not_found}, {world, events}}
    end
  end

  def handle_call({:trigger_collector, collector_id}, _from, {world, events}) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        {world, events, output} = do_trigger(world, events, collector_id, collector)
        {:reply, {:ok, output}, {world, events}}

      _ ->
        {:reply, {:error, :not_found}, {world, events}}
    end
  end

  def handle_call({:update_node_position, node_id, position}, _from, {world, events}) do
    case Map.get(world.nodes, node_id) do
      nil ->
        {:reply, {:error, :not_found}, {world, events}}

      _node ->
        event = {:node_moved, node_id, position, now()}
        world = Event.apply(world, event)
        {:reply, :ok, {world, [event | events]}}
    end
  end

  def handle_call({:clear_collector, collector_id}, _from, {world, events}) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        cleared = Collector.clear(collector)
        event = {:collector_cleared, collector_id, cleared, now()}
        world = Event.apply(world, event)
        {:reply, :ok, {world, [event | events]}}

      _ ->
        {:reply, {:error, :not_found}, {world, events}}
    end
  end

  def handle_call({:rotate_passive, node_id}, _from, {world, events}) do
    case Map.get(world.nodes, node_id) do
      %Node{type: :passive, config: config} = node ->
        current = Map.get(config, :angle, 0.0)
        next = rotate_angle(current)
        updated = %{node | config: Map.put(config, :angle, next)}
        event = {:passive_rotated, node_id, updated, now()}
        world = Event.apply(world, event)
        broadcast(world, {:node_updated, updated})
        {:reply, {:ok, next}, {world, [event | events]}}

      _ ->
        {:reply, {:error, :not_found}, {world, events}}
    end
  end

  def handle_call({:remove_tokene, tokene_id}, _from, {world, events}) do
    event = {:tokene_removed, tokene_id, now()}
    world = Event.apply(world, event)
    {:reply, :ok, {world, [event | events]}}
  end

  @impl true
  def handle_cast(:pause, {world, events}) do
    event = {:paused, now()}
    world = Event.apply(world, event)
    {:noreply, {world, [event | events]}}
  end

  def handle_cast(:resume, {world, events}) do
    event = {:resumed, now()}
    world = Event.apply(world, event)
    {:noreply, {world, [event | events]}}
  end

  def handle_cast({:set_gravity, gravity}, {world, events}) do
    event = {:gravity_changed, gravity, now()}
    world = Event.apply(world, event)
    {:noreply, {world, [event | events]}}
  end

  def handle_cast({:set_decay, decay_config}, {world, events}) do
    event = {:decay_changed, decay_config, now()}
    world = Event.apply(world, event)
    {:noreply, {world, [event | events]}}
  end

  def handle_cast(:tick, {%{paused: true} = world, events}) do
    {:noreply, {world, events}}
  end

  def handle_cast(:tick, {world, events}) do
    world = %{world | tick_count: world.tick_count + 1}

    # Check all timed collectors
    {world, events} =
      world.nodes
      |> Map.values()
      |> Enum.filter(&(&1.type == :collector))
      |> Enum.reduce({world, events}, fn collector, {w, evts} ->
        case Collector.tick(collector) do
          {:trigger, updated} ->
            w = %{w | nodes: Map.put(w.nodes, updated.id, updated)}
            {w, evts, _output} = do_trigger(w, evts, updated.id, Map.get(w.nodes, updated.id))
            {w, evts}

          {:ok, updated} ->
            {%{w | nodes: Map.put(w.nodes, updated.id, updated)}, evts}
        end
      end)

    {:noreply, {world, events}}
  end

  # --- Private ---

  defp maybe_auto_trigger(world, events, :full, %{config: %{trigger_mode: :on_full}}, collector_id) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        {world, events, _output} = do_trigger(world, events, collector_id, collector)
        {world, events}

      _ ->
        {world, events}
    end
  end

  defp maybe_auto_trigger(world, events, _status, _collector, _collector_id), do: {world, events}

  # Shared trigger logic: handles both :discard and :emit output modes
  defp do_trigger(world, events, collector_id, collector) do
    case Collector.trigger(collector) do
      {:ok, output, cleared, emitted_tokenes} ->
        # :emit mode — trigger + emit new tokenes
        event = {:triggered, collector_id, output, cleared, now()}
        world = Event.apply(world, event)
        emit_event = {:emitted, collector_id, emitted_tokenes, now()}
        world = Event.apply(world, emit_event)
        broadcast(world, {:trigger, collector_id, output})
        broadcast(world, {:emit, collector_id, emitted_tokenes})
        {world, [emit_event, event | events], output}

      {:ok, output, cleared} ->
        # :discard mode — trigger only
        event = {:triggered, collector_id, output, cleared, now()}
        world = Event.apply(world, event)
        broadcast(world, {:trigger, collector_id, output})
        {world, [event | events], output}
    end
  end

  @rotation_steps [0.0, 0.2618, 0.5236, 0.7854, -0.7854, -0.5236, -0.2618]
  defp rotate_angle(current) do
    idx = Enum.find_index(@rotation_steps, &(abs(&1 - current) < 0.01)) || 0
    Enum.at(@rotation_steps, rem(idx + 1, length(@rotation_steps)))
  end

  defp filter_events(events, opts) do
    since = Keyword.get(opts, :since)
    types = Keyword.get(opts, :types)

    events
    |> then(fn evts ->
      if since, do: Enum.filter(evts, &(Event.timestamp(&1) >= since)), else: evts
    end)
    |> then(fn evts ->
      if types, do: Enum.filter(evts, &(elem(&1, 0) in types)), else: evts
    end)
  end

  defp broadcast(%__MODULE__{id: world_id}, event) do
    Phoenix.PubSub.broadcast(Quantok.PubSub, "world:#{world_id}", event)
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
