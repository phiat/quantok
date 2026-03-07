defmodule QuantokWeb.WorldLive do
  use QuantokWeb, :live_view

  alias Quantok.Node.{Collector, Emitter, Passive, Transformer}
  alias Quantok.Tokene
  alias Quantok.World
  alias Quantok.World.Snapshot

  @impl true
  def mount(_params, _session, socket) do
    {:ok, world_pid} = World.start_link(world_name: "Sandbox")
    Process.link(world_pid)
    world = World.get_state(world_pid)

    # Subscribe to world events
    Phoenix.PubSub.subscribe(Quantok.PubSub, "world:#{world.id}")

    # Add default nodes
    floor = Passive.new(:floor, position: {0.0, 350.0}, width: 1200.0, height: 10.0)
    World.add_node(world_pid, floor)

    emitter = Emitter.new(command: "date", chunker: Quantok.Chunker.Word, position: {0.0, -300.0}, label: "date")
    World.add_node(world_pid, emitter)

    collector = Collector.new(capacity: 8, position: {0.0, 250.0}, label: "Collector")
    World.add_node(world_pid, collector)

    socket =
      socket
      |> assign(:world_pid, world_pid)
      |> assign(:world_id, world.id)
      |> assign(:paused, false)
      |> assign(:tokene_count, 0)
      |> assign(:node_count, 2)
      |> assign(:saved_worlds, list_saved_worlds())
      |> assign(:world_name, "Sandbox")
      |> assign(:next_x, 0)
      |> push_node(floor)
      |> push_node(emitter)
      |> push_node(collector)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen w-screen overflow-hidden">
      <header class="q-topbar">
        <span class="q-logo">Quantok</span>
        <span class="q-sep"></span>
        <button phx-click="fire_all" class="q-tb">fire all</button>
        <button phx-click="toggle_pause" class="q-tb">{if @paused, do: "resume", else: "pause"}</button>
        <button phx-click="clear_tokenes" class="q-tb">clear</button>
        <span class="q-sep"></span>
        <button phx-click="save_world" class="q-tb">save</button>
        <button :for={world <- @saved_worlds} phx-click="load_world" phx-value-name={world} class="q-tb q-tb--load">{world}</button>
        <span class="q-spacer"></span>
        <span class="q-status">{@tokene_count} tok · {@node_count} nodes · {if @paused, do: "paused", else: @world_name}</span>
      </header>

      <div class="flex flex-1 overflow-hidden">
        <nav class="q-sidebar">
          <div class="q-section">Emitters</div>
          <button phx-click="add_emitter" phx-value-command="date" phx-value-chunker="word" class="q-btn q-btn--emit">date · word</button>
          <button phx-click="add_emitter" phx-value-command="date" phx-value-chunker="byte" class="q-btn q-btn--emit">date · byte</button>
          <button phx-click="add_emitter" phx-value-command="echo hello world" phx-value-chunker="token" class="q-btn q-btn--emit">echo · token</button>
          <button phx-click="add_emitter" phx-value-command="uname -a" phx-value-chunker="word" class="q-btn q-btn--emit">uname · word</button>
          <button phx-click="add_source_emitter" phx-value-source="clock" phx-value-chunker="rune" class="q-btn q-btn--emit">clock · rune</button>
          <button phx-click="add_source_emitter" phx-value-source="sequence" phx-value-command="alpha" phx-value-chunker="word" class="q-btn q-btn--emit">A–Z · word</button>
          <button phx-click="add_source_emitter" phx-value-source="manual" phx-value-command="The quick brown fox jumps over the lazy dog" phx-value-chunker="word" class="q-btn q-btn--emit">pangram · word</button>

          <div class="q-section">Collectors</div>
          <button phx-click="add_collector" phx-value-capacity="8" class="q-btn q-btn--collect">collect · 8</button>
          <button phx-click="add_collector" phx-value-capacity="16" class="q-btn q-btn--collect">collect · 16</button>
          <button phx-click="add_typed_collector" phx-value-action="reverse" phx-value-capacity="8" class="q-btn q-btn--collect">reverse · 8</button>
          <button phx-click="add_typed_collector" phx-value-action="upcase" phx-value-capacity="8" class="q-btn q-btn--collect">upcase · 8</button>
          <button phx-click="add_typed_collector" phx-value-action="count" phx-value-capacity="8" class="q-btn q-btn--collect">count · 8</button>

          <div class="q-section">Transformers</div>
          <button phx-click="add_transformer" phx-value-effect="splitter" class="q-btn q-btn--transform">splitter</button>
          <button phx-click="add_transformer" phx-value-effect="heater" class="q-btn q-btn--transform">heater</button>
          <button phx-click="add_transformer" phx-value-effect="cooler" class="q-btn q-btn--transform">cooler</button>
          <button phx-click="add_transformer" phx-value-effect="duplicator" class="q-btn q-btn--transform">duplicator</button>
          <button phx-click="add_transformer" phx-value-effect="crusher" class="q-btn q-btn--transform">crusher</button>

          <div class="q-section">World</div>
          <button phx-click="add_passive" phx-value-shape="ramp" class="q-btn q-btn--passive">ramp</button>
          <button phx-click="add_passive" phx-value-shape="wall" class="q-btn q-btn--passive">wall</button>
          <button phx-click="add_passive" phx-value-shape="funnel" class="q-btn q-btn--passive">funnel</button>
        </nav>

        <div class="q-canvas-wrap">
          <canvas id="world-canvas" phx-hook="WorldCanvas" class="w-full h-full" phx-update="ignore"></canvas>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    if socket.assigns.paused do
      World.resume(socket.assigns.world_pid)
    else
      World.pause(socket.assigns.world_pid)
    end

    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  @allowed_shell_commands ["date", "uname -a", "echo hello world", "hostname", "whoami", "uptime"]

  def handle_event("add_emitter", %{"command" => command, "chunker" => chunker}, socket) do
    if command in @allowed_shell_commands do
      chunker_mod = chunker_module(chunker)
      {x, socket} = next_x(socket)

      emitter =
        Emitter.new(command: command, chunker: chunker_mod, position: {x, -300.0}, label: command)

      {:ok, _} = World.add_node(socket.assigns.world_pid, emitter)

      {:noreply, socket |> push_node(emitter) |> update(:node_count, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_source_emitter", params, socket) do
    source_mod = source_module(params["source"])
    chunker_mod = chunker_module(params["chunker"] || "word")
    command = params["command"] || ""
    {x, socket} = next_x(socket)
    label = params["source"]

    emitter =
      Emitter.new(
        source: source_mod,
        command: command,
        chunker: chunker_mod,
        position: {x, -300.0},
        label: label
      )

    {:ok, _} = World.add_node(socket.assigns.world_pid, emitter)

    {:noreply, socket |> push_node(emitter) |> update(:node_count, &(&1 + 1))}
  end

  def handle_event("add_collector", %{"capacity" => cap_str}, socket) do
    capacity = String.to_integer(cap_str)
    {x, socket} = next_x(socket)
    collector = Collector.new(capacity: capacity, position: {x, 250.0}, label: "Collector")
    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply, socket |> push_node(collector) |> update(:node_count, &(&1 + 1))}
  end

  def handle_event("add_typed_collector", %{"action" => action, "capacity" => cap_str}, socket) do
    capacity = String.to_integer(cap_str)
    action_mod = collector_action(action)
    {x, socket} = next_x(socket)
    label = String.capitalize(action)

    collector =
      Collector.new(
        capacity: capacity,
        action: action_mod,
        position: {x, 250.0},
        label: label
      )

    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply, socket |> push_node(collector) |> update(:node_count, &(&1 + 1))}
  end

  def handle_event("add_transformer", %{"effect" => effect}, socket) do
    case effect_atom(effect) do
      nil ->
        {:noreply, socket}

      effect_atom ->
        {x, socket} = next_x(socket)
        transformer = Transformer.new(effect_atom, position: {x, 0.0}, radius: 60.0)
        {:ok, _} = World.add_node(socket.assigns.world_pid, transformer)
        {:noreply, socket |> push_node(transformer) |> update(:node_count, &(&1 + 1))}
    end
  end

  def handle_event("add_passive", %{"shape" => shape}, socket) do
    case shape_atom(shape) do
      nil ->
        {:noreply, socket}

      shape_atom ->
        {x, socket} = next_x(socket)
        passive = Passive.new(shape_atom, position: {x, 100.0})
        {:ok, _} = World.add_node(socket.assigns.world_pid, passive)
        {:noreply, socket |> push_node(passive)}
    end
  end

  def handle_event("fire_all", _params, socket) do
    world = World.get_state(socket.assigns.world_pid)

    world.nodes
    |> Map.values()
    |> Enum.filter(&(&1.type == :emitter))
    |> Enum.each(fn emitter ->
      World.fire_emitter(socket.assigns.world_pid, emitter.id)
    end)

    {:noreply, socket}
  end

  def handle_event("clear_tokenes", _params, socket) do
    world = World.get_state(socket.assigns.world_pid)
    Enum.each(Map.keys(world.tokenes), &World.remove_tokene(socket.assigns.world_pid, &1))
    {:noreply, socket |> push_event("clear_tokenes", %{}) |> assign(:tokene_count, 0)}
  end

  def handle_event("save_world", _params, socket) do
    world = World.get_state(socket.assigns.world_pid)
    name = world.name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    path = Path.join(saves_dir(), "#{name}.json")
    :ok = Snapshot.save_to_file(world, path)

    {:noreply, assign(socket, :saved_worlds, list_saved_worlds())}
  end

  def handle_event("load_world", %{"name" => name}, socket) do
    # Prevent path traversal — only allow alphanumeric, underscore, hyphen
    safe_name = name |> Path.basename() |> String.replace(~r/[^a-zA-Z0-9_\-]/, "")

    path =
      worlds_search_paths()
      |> Enum.map(&Path.join(&1, "#{safe_name}.json"))
      |> Enum.find(&File.exists?/1)

    if path do
      {:ok, snapshot} = Snapshot.load_from_file(path)

      # Clear existing world
      world = World.get_state(socket.assigns.world_pid)
      Enum.each(Map.keys(world.tokenes), &World.remove_tokene(socket.assigns.world_pid, &1))
      Enum.each(Map.keys(world.nodes), &World.remove_node(socket.assigns.world_pid, &1))

      # Load snapshot
      {:ok, node_count} = Snapshot.load_into(socket.assigns.world_pid, snapshot)

      # Push all nodes to client
      loaded_world = World.get_state(socket.assigns.world_pid)

      socket =
        socket
        |> push_event("clear_tokenes", %{})
        |> push_event("clear_nodes", %{})
        |> assign(:tokene_count, 0)
        |> assign(:node_count, node_count)
        |> assign(:world_name, snapshot["name"] || name)

      socket =
        Enum.reduce(Map.values(loaded_world.nodes), socket, fn node, acc ->
          push_node(acc, node)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tokene_near_collector", %{"tokene_id" => tid, "collector_id" => cid}, socket) do
    case World.absorb_tokene(socket.assigns.world_pid, cid, tid) do
      {:ok, _status} -> :ok
      _ -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("tokene_near_transformer", %{"tokene_id" => tid, "transformer_id" => xid}, socket) do
    case World.apply_transformer(socket.assigns.world_pid, xid, tid) do
      {:ok, _result} -> :ok
      _ -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("tokene_offscreen", %{"tokene_id" => tid}, socket) do
    World.remove_tokene(socket.assigns.world_pid, tid)
    {:noreply, update(socket, :tokene_count, &max(&1 - 1, 0))}
  end

  def handle_event("tokene_shattered", %{"tokene_id" => tid}, socket) do
    World.remove_tokene(socket.assigns.world_pid, tid)
    {:noreply, update(socket, :tokene_count, &max(&1 - 1, 0))}
  end

  def handle_event("move_node", %{"node_id" => id, "x" => x, "y" => y}, socket) do
    World.update_node_position(socket.assigns.world_pid, id, {x * 1.0, y * 1.0})
    {:noreply, socket}
  end

  def handle_event("fire_emitter", %{"node_id" => id}, socket) do
    World.fire_emitter(socket.assigns.world_pid, id)
    {:noreply, socket}
  end

  def handle_event("trigger_collector", %{"node_id" => id}, socket) do
    World.trigger_collector(socket.assigns.world_pid, id)
    {:noreply, socket}
  end

  def handle_event("clear_collector", %{"node_id" => id}, socket) do
    World.clear_collector(socket.assigns.world_pid, id)

    {:noreply,
     push_event(socket, "update_collector", %{collector_id: id, buffer: []})}
  end

  def handle_event("rotate_passive", %{"node_id" => id}, socket) do
    World.rotate_passive(socket.assigns.world_pid, id)
    {:noreply, socket}
  end

  def handle_event("remove_node", %{"node_id" => id}, socket) do
    world = World.get_state(socket.assigns.world_pid)
    node = Map.get(world.nodes, id)
    World.remove_node(socket.assigns.world_pid, id)

    is_passive = match?(%{type: :passive}, node)
    count_delta = if is_passive or is_nil(node), do: 0, else: -1
    {:noreply, update(socket, :node_count, &max(&1 + count_delta, 0))}
  end

  # PubSub handlers
  @impl true
  def handle_info({:emit, emitter_id, tokenes}, socket) do
    rate = get_emit_rate(socket.assigns.world_pid, emitter_id)

    tokene_data =
      Enum.map(tokenes, fn t ->
        {w, h} = Tokene.dimensions(t)

        %{
          id: t.id,
          value: t.value,
          encoding: to_string(t.encoding),
          width: w,
          height: h,
          mass: Tokene.mass(t),
          integrity: t.integrity,
          emit_rate: rate,
          created_at: t.created_at,
          decay: %{
            enabled: t.decay.enabled,
            half_life: if(t.decay.half_life == :infinite, do: 0, else: t.decay.half_life),
            shatter: to_string(t.decay.shatter)
          }
        }
      end)

    socket =
      socket
      |> push_event("emit_tokenes", %{emitter_id: emitter_id, tokenes: tokene_data})
      |> update(:tokene_count, &(&1 + length(tokenes)))

    {:noreply, socket}
  end

  def handle_info({:absorb, collector_id, tokene_id}, socket) do
    buffer_data = get_buffer_data(socket.assigns.world_pid, collector_id)

    socket =
      socket
      |> push_event("absorb_tokene", %{
        collector_id: collector_id,
        tokene_id: tokene_id,
        buffer: buffer_data
      })
      |> update(:tokene_count, &max(&1 - 1, 0))

    {:noreply, socket}
  end

  def handle_info({:trigger, collector_id, output}, socket) do
    socket =
      socket
      |> push_event("update_collector", %{
        collector_id: collector_id,
        buffer: [],
        output: output
      })

    {:noreply, socket}
  end

  def handle_info({:node_added, _node}, socket), do: {:noreply, socket}
  def handle_info({:node_removed, _id}, socket), do: {:noreply, socket}
  def handle_info({:node_updated, _node}, socket), do: {:noreply, socket}
  def handle_info({:transform, _transformer_id, old_tokene_id, result_tokenes}, socket) do
    new_tokene_data =
      Enum.map(result_tokenes, fn t ->
        {w, h} = Tokene.dimensions(t)

        %{
          id: t.id,
          value: t.value,
          encoding: to_string(t.encoding),
          width: w,
          height: h,
          mass: Tokene.mass(t),
          integrity: t.integrity,
          decay: %{
            enabled: t.decay.enabled,
            half_life: if(t.decay.half_life == :infinite, do: 0, else: t.decay.half_life),
            shatter: to_string(t.decay.shatter)
          }
        }
      end)

    count_delta = length(result_tokenes) - 1

    socket =
      socket
      |> push_event("transform_tokene", %{
        old_tokene_id: old_tokene_id,
        new_tokenes: new_tokene_data
      })
      |> update(:tokene_count, &max(&1 + count_delta, 0))

    {:noreply, socket}
  end

  # Helpers

  defp push_node(socket, node) do
    {px, py} = node.position

    push_event(socket, "add_node", %{
      node: %{
        id: node.id,
        type: to_string(node.type),
        label: node.label,
        position_x: px,
        position_y: py,
        width: node_width(node),
        height: node_height(node),
        config: serialize_config(node.config)
      }
    })
  end

  defp node_width(%{type: :passive, config: %{width: w}}), do: w
  defp node_width(%{type: :collector, config: %{capacity: cap}}), do: max(cap * 12, 80)
  defp node_width(%{type: :transformer, config: %{radius: r}}), do: r * 2
  defp node_width(_), do: 80.0

  defp node_height(%{type: :passive, config: %{height: h}}), do: h
  defp node_height(%{type: :transformer, config: %{radius: r}}), do: r * 2
  defp node_height(_), do: 40.0

  defp serialize_config(config) when is_map(config) do
    config
    |> Map.take([
      :capacity, :shape, :angle, :friction, :restitution,
      :strength, :radius, :effect, :sensor_radius
    ])
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v), do: v

  defp effect_atom("splitter"), do: :splitter
  defp effect_atom("crusher"), do: :crusher
  defp effect_atom("heater"), do: :heater
  defp effect_atom("cooler"), do: :cooler
  defp effect_atom("filter"), do: :filter
  defp effect_atom("duplicator"), do: :duplicator
  defp effect_atom("painter"), do: :painter
  defp effect_atom(_), do: nil

  defp shape_atom("floor"), do: :floor
  defp shape_atom("wall"), do: :wall
  defp shape_atom("ramp"), do: :ramp
  defp shape_atom("funnel"), do: :funnel
  defp shape_atom("attractor"), do: :attractor
  defp shape_atom("repeller"), do: :repeller
  defp shape_atom(_), do: nil

  defp source_module("clock"), do: Quantok.Node.Emitter.Clock
  defp source_module("file"), do: Quantok.Node.Emitter.File
  defp source_module("manual"), do: Quantok.Node.Emitter.Manual
  defp source_module("sequence"), do: Quantok.Node.Emitter.Sequence
  defp source_module(_), do: Quantok.Node.Emitter.Shell

  defp collector_action("echo"), do: Quantok.Node.Collector.Echo
  defp collector_action("shell"), do: Quantok.Node.Collector.Shell
  defp collector_action("reverse"), do: Quantok.Node.Collector.Reverse
  defp collector_action("upcase"), do: Quantok.Node.Collector.Upcase
  defp collector_action("count"), do: Quantok.Node.Collector.Count
  defp collector_action("display"), do: Quantok.Node.Collector.Display
  defp collector_action(_), do: Quantok.Node.Collector.Echo

  defp chunker_module("bit"), do: Quantok.Chunker.Bit
  defp chunker_module("byte"), do: Quantok.Chunker.Byte
  defp chunker_module("rune"), do: Quantok.Chunker.Rune
  defp chunker_module("token"), do: Quantok.Chunker.BPE
  defp chunker_module("word"), do: Quantok.Chunker.Word
  defp chunker_module("phrase"), do: Quantok.Chunker.Phrase
  defp chunker_module("sentence"), do: Quantok.Chunker.Sentence
  defp chunker_module(_), do: Quantok.Chunker.Word

  # Deterministic stagger: alternates left/right of center, growing outward
  defp next_x(socket) do
    n = socket.assigns.next_x
    # Sequence: 0, -120, 120, -240, 240, -360, ...
    x = if n == 0, do: 0.0, else: (div(n + 1, 2) * 120.0 * if(rem(n, 2) == 1, do: -1, else: 1))
    {x, assign(socket, :next_x, n + 1)}
  end

  defp saves_dir do
    Path.join(Application.app_dir(:quantok, "priv"), "worlds")
  end

  defp worlds_search_paths do
    [saves_dir()]
  end

  defp list_saved_worlds do
    worlds_search_paths()
    |> Enum.flat_map(fn dir ->
      dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".json"))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp get_buffer_data(world_pid, collector_id) do
    world = World.get_state(world_pid)

    case Map.get(world.nodes, collector_id) do
      %{type: :collector, config: %{buffer: buffer}} ->
        Enum.map(buffer, fn t ->
          %{value: t.value, encoding: to_string(t.encoding)}
        end)

      _ ->
        []
    end
  end

  defp get_emit_rate(world_pid, emitter_id) do
    world = World.get_state(world_pid)

    case Map.get(world.nodes, emitter_id) do
      %{config: %{emit_rate: rate}} -> rate
      _ -> 250
    end
  end
end
