defmodule Quantok.World do
  @moduledoc """
  Central world state manager. Maintains nodes, active tokenes, and environment
  config. Dispatches events to connected clients via PubSub.
  """

  use GenServer

  alias Quantok.Node
  alias Quantok.Node.{Collector, Emitter, Transformer}
  alias Quantok.Tokene

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
    environment: %{gravity: {0.0, 9.81}, tick_rate: 30},
    tick_count: 0,
    paused: false
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get_state(server), do: GenServer.call(server, :get_state)

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

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    world = %__MODULE__{
      id: generate_id(),
      name: Keyword.get(opts, :world_name, "Untitled World")
    }

    {:ok, world}
  end

  @impl true
  def handle_call(:get_state, _from, world) do
    {:reply, world, world}
  end

  def handle_call({:add_node, node}, _from, world) do
    world = %{world | nodes: Map.put(world.nodes, node.id, node)}
    broadcast(world, {:node_added, node})
    {:reply, {:ok, node}, world}
  end

  def handle_call({:remove_node, node_id}, _from, world) do
    {removed, nodes} = Map.pop(world.nodes, node_id)
    world = %{world | nodes: nodes}

    if removed do
      broadcast(world, {:node_removed, node_id})
    end

    {:reply, {:ok, removed}, world}
  end

  def handle_call({:update_node, node_id, updates}, _from, world) do
    case Map.get(world.nodes, node_id) do
      nil ->
        {:reply, {:error, :not_found}, world}

      node ->
        updated = struct(node, updates)
        world = %{world | nodes: Map.put(world.nodes, node_id, updated)}
        broadcast(world, {:node_updated, updated})
        {:reply, {:ok, updated}, world}
    end
  end

  def handle_call({:fire_emitter, emitter_id}, _from, world) do
    with %Node{type: :emitter} = node <- Map.get(world.nodes, emitter_id),
         {:ok, tokenes} <- Emitter.fire(node) do
      new_tokenes = Map.new(tokenes, fn t -> {t.id, t} end)
      world = %{world | tokenes: Map.merge(world.tokenes, new_tokenes)}
      broadcast(world, {:emit, emitter_id, tokenes})
      {:reply, {:ok, tokenes}, world}
    else
      nil -> {:reply, {:error, :not_found}, world}
      {:error, reason} -> {:reply, {:error, reason}, world}
    end
  end

  def handle_call({:absorb_tokene, collector_id, tokene_id}, _from, world) do
    with %Node{type: :collector} = collector <- Map.get(world.nodes, collector_id),
         false <- Collector.full?(collector),
         %Tokene{} = tokene <- Map.get(world.tokenes, tokene_id) do
      {status, updated_collector} = Collector.absorb(collector, tokene)

      world = %{
        world
        | nodes: Map.put(world.nodes, collector_id, updated_collector),
          tokenes: Map.delete(world.tokenes, tokene_id)
      }

      world = maybe_auto_trigger(world, status, updated_collector, collector_id)
      broadcast(world, {:absorb, collector_id, tokene_id})
      {:reply, {:ok, status}, world}
    else
      true -> {:reply, {:error, :full}, world}
      _ -> {:reply, {:error, :not_found}, world}
    end
  end

  def handle_call({:apply_transformer, transformer_id, tokene_id}, _from, world) do
    with %Node{type: :transformer} = transformer <- Map.get(world.nodes, transformer_id),
         %Tokene{} = tokene <- Map.get(world.tokenes, tokene_id) do
      result_tokenes = Transformer.apply_effect(transformer, tokene)
      new_tokene_map = Map.new(result_tokenes, fn t -> {t.id, t} end)

      world = %{
        world
        | tokenes:
            world.tokenes
            |> Map.delete(tokene_id)
            |> Map.merge(new_tokene_map)
      }

      broadcast(world, {:transform, transformer_id, tokene_id, result_tokenes})
      {:reply, {:ok, result_tokenes}, world}
    else
      _ -> {:reply, {:error, :not_found}, world}
    end
  end

  def handle_call({:trigger_collector, collector_id}, _from, world) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        {:ok, output, cleared} = Collector.trigger(collector)
        world = %{world | nodes: Map.put(world.nodes, collector_id, cleared)}
        broadcast(world, {:trigger, collector_id, output})
        {:reply, {:ok, output}, world}

      _ ->
        {:reply, {:error, :not_found}, world}
    end
  end

  def handle_call({:update_node_position, node_id, position}, _from, world) do
    case Map.get(world.nodes, node_id) do
      nil ->
        {:reply, {:error, :not_found}, world}

      node ->
        updated = %{node | position: position}
        world = %{world | nodes: Map.put(world.nodes, node_id, updated)}
        {:reply, :ok, world}
    end
  end

  def handle_call({:clear_collector, collector_id}, _from, world) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        cleared = Collector.clear(collector)
        world = %{world | nodes: Map.put(world.nodes, collector_id, cleared)}
        {:reply, :ok, world}

      _ ->
        {:reply, {:error, :not_found}, world}
    end
  end

  def handle_call({:rotate_passive, node_id}, _from, world) do
    case Map.get(world.nodes, node_id) do
      %Node{type: :passive, config: config} = node ->
        current = Map.get(config, :angle, 0.0)
        next = rotate_angle(current)
        updated = %{node | config: Map.put(config, :angle, next)}
        world = %{world | nodes: Map.put(world.nodes, node_id, updated)}
        broadcast(world, {:node_updated, updated})
        {:reply, {:ok, next}, world}

      _ ->
        {:reply, {:error, :not_found}, world}
    end
  end

  def handle_call({:remove_tokene, tokene_id}, _from, world) do
    world = %{world | tokenes: Map.delete(world.tokenes, tokene_id)}
    {:reply, :ok, world}
  end

  @impl true
  def handle_cast(:pause, world), do: {:noreply, %{world | paused: true}}
  def handle_cast(:resume, world), do: {:noreply, %{world | paused: false}}

  def handle_cast({:set_gravity, gravity}, world) do
    {:noreply, %{world | environment: Map.put(world.environment, :gravity, gravity)}}
  end

  # --- Private ---

  defp maybe_auto_trigger(world, :full, %{config: %{trigger_mode: :on_full}}, collector_id) do
    auto_trigger(world, collector_id)
  end

  defp maybe_auto_trigger(world, _status, _collector, _collector_id), do: world

  defp auto_trigger(world, collector_id) do
    case Map.get(world.nodes, collector_id) do
      %Node{type: :collector} = collector ->
        {:ok, output, cleared} = Collector.trigger(collector)
        world = %{world | nodes: Map.put(world.nodes, collector_id, cleared)}
        broadcast(world, {:trigger, collector_id, output})
        world

      _ ->
        world
    end
  end

  @rotation_steps [0.0, 0.2618, 0.5236, 0.7854, -0.7854, -0.5236, -0.2618]
  defp rotate_angle(current) do
    idx = Enum.find_index(@rotation_steps, &(abs(&1 - current) < 0.01)) || 0
    Enum.at(@rotation_steps, rem(idx + 1, length(@rotation_steps)))
  end

  defp broadcast(%__MODULE__{id: world_id}, event) do
    Phoenix.PubSub.broadcast(Quantok.PubSub, "world:#{world_id}", event)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
