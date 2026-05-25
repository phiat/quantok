defmodule QuantokWeb.WorldLive do
  use QuantokWeb, :live_view

  alias Quantok.Node.{Collector, Emitter, Passive}
  alias Quantok.Tokene
  alias Quantok.World
  alias Quantok.World.Snapshot
  alias QuantokWeb.{WorldConfig, WorldSidebar}
  alias QuantokWeb.WorldSidebar.Actions, as: SidebarActions

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

    emitter =
      Emitter.new(
        source: Quantok.Node.Emitter.Clock,
        command: "%H:%M:%S",
        chunker: Quantok.Chunker.Word,
        position: {0.0, -300.0},
        label: "clock"
      )

    World.add_node(world_pid, emitter)

    collector =
      Collector.new(
        capacity: 8,
        position: {0.0, 250.0},
        label: "Collector",
        emit: true,
        output_chunker: Quantok.Chunker.Byte
      )

    World.add_node(world_pid, collector)

    socket =
      socket
      |> assign(:world_pid, world_pid)
      |> assign(:world_id, world.id)
      |> assign(:paused, false)
      |> assign(:tokene_count, 0)
      |> assign(:node_count, 3)
      |> assign(:saved_worlds, list_saved_worlds())
      |> assign(:world_name, "Sandbox")
      |> assign(:decay_enabled, true)
      |> assign(:decay_rate, 1.0)
      |> assign(:decay_shatter, :split)
      |> assign(:selected_node, nil)
      |> assign(:template_node, nil)
      |> assign(:next_x, 0)
      |> SidebarActions.push_node(floor)
      |> SidebarActions.push_node(emitter)
      |> SidebarActions.push_node(collector)
      |> push_event("set_decay", %{enabled: true, rate: 1.0})

    # Start physics tick timer (~30 ticks/sec)
    # ms (~30Hz)
    tick_rate = 33
    Process.send_after(self(), :tick, tick_rate)
    socket = assign(socket, :tick_rate, tick_rate)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="q-root">
      <header class="q-topbar">
        <span class="q-logo">Quantok</span>
        <span class="q-sep"></span>
        <button phx-click="fire_all" class="q-tb">fire all</button>
        <button phx-click="toggle_pause" class="q-tb">
          {if @paused, do: "resume", else: "pause"}
        </button>
        <button phx-click="clear_tokenes" class="q-tb">clear</button>
        <button
          phx-click="toggle_decay"
          class={"q-tb" <> if(@decay_enabled, do: " q-tb--active", else: "")}
        >
          {if @decay_enabled, do: "decay on", else: "decay off"}
        </button>
        <span :if={@decay_enabled} class="q-decay-group">
          <button
            :for={r <- [{0.5, "½×"}, {1.0, "1×"}, {2.0, "2×"}, {10.0, "10×"}]}
            phx-click="set_decay_rate"
            phx-value-rate={elem(r, 0)}
            class={"q-tb q-tb--sm" <> if(@decay_rate == elem(r, 0), do: " q-tb--active", else: "")}
          >
            {elem(r, 1)}
          </button>
          <span class="q-sep"></span>
          <button
            :for={s <- ["split", "dissolve", "explode", "fossilize"]}
            phx-click="set_decay_shatter"
            phx-value-shatter={s}
            class={"q-tb q-tb--sm" <> if(to_string(@decay_shatter) == s, do: " q-tb--active", else: "")}
          >
            {s}
          </button>
        </span>
        <span class="q-sep"></span>
        <button phx-click="save_world" class="q-tb">save</button>
        <button
          :for={world <- @saved_worlds}
          phx-click="load_world"
          phx-value-name={world}
          class="q-tb q-tb--load"
        >
          {world}
        </button>
        <span class="q-spacer"></span>
        <span id="q-fps" class="q-fps" phx-update="ignore" title="frames per second">— fps</span>
        <span class="q-status">
          {@tokene_count} tok · {@node_count} nodes · {if @paused, do: "paused", else: @world_name}
        </span>
      </header>

      <div class="q-main">
        <WorldSidebar.sidebar />

        <WorldConfig.config_panel selected_node={@selected_node} template_node={@template_node} />

        <div class="q-canvas-wrap">
          <canvas id="world-canvas" phx-hook="WorldCanvas" class="q-canvas" phx-update="ignore">
          </canvas>
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

  def handle_event("toggle_decay", _params, socket) do
    new_enabled = !socket.assigns.decay_enabled
    World.set_decay(socket.assigns.world_pid, %{enabled: new_enabled})

    {:noreply,
     socket
     |> assign(:decay_enabled, new_enabled)
     |> push_event("set_decay", %{enabled: new_enabled, rate: socket.assigns.decay_rate})}
  end

  def handle_event("set_decay_rate", %{"rate" => rate_str}, socket) do
    rate = String.to_float(rate_str)
    World.set_decay(socket.assigns.world_pid, %{rate: rate})

    {:noreply,
     socket
     |> assign(:decay_rate, rate)
     |> push_event("set_decay", %{enabled: socket.assigns.decay_enabled, rate: rate})}
  end

  def handle_event("set_decay_shatter", %{"shatter" => shatter}, socket) do
    shatter_atom = SidebarActions.shatter_atom(shatter)
    World.set_decay(socket.assigns.world_pid, %{shatter: shatter_atom})
    {:noreply, assign(socket, :decay_shatter, shatter_atom)}
  end

  def handle_event("add_source_emitter", params, socket),
    do: {:noreply, SidebarActions.add_source_emitter(socket, params)}

  def handle_event("add_collector", params, socket),
    do: {:noreply, SidebarActions.add_collector(socket, params)}

  def handle_event("add_typed_collector", params, socket),
    do: {:noreply, SidebarActions.add_typed_collector(socket, params)}

  def handle_event("add_timed_collector", params, socket),
    do: {:noreply, SidebarActions.add_timed_collector(socket, params)}

  def handle_event("add_emit_collector", params, socket),
    do: {:noreply, SidebarActions.add_emit_collector(socket, params)}

  def handle_event("add_transformer", params, socket),
    do: {:noreply, SidebarActions.add_transformer(socket, params)}

  def handle_event("add_passive", params, socket),
    do: {:noreply, SidebarActions.add_passive(socket, params)}

  def handle_event("fire_all", _params, socket) do
    World.fire_all_emitters(socket.assigns.world_pid)
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
    safe_name = name |> Path.basename() |> String.replace(~r/[^a-zA-Z0-9_\-]/, "")

    path =
      worlds_search_paths()
      |> Enum.map(&Path.join(&1, "#{safe_name}.json"))
      |> Enum.find(&File.exists?/1)

    with path when path != nil <- path,
         {:ok, snapshot} <- Snapshot.load_from_file(path) do
      {:noreply, do_load_world(socket, snapshot, name)}
    else
      nil ->
        {:noreply, socket}

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to load world #{safe_name}: #{inspect(reason)}")
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

  def handle_event(
        "tokene_near_transformer",
        %{"tokene_id" => tid, "transformer_id" => xid},
        socket
      ) do
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
    world = World.get_state(socket.assigns.world_pid)

    case Map.get(world.tokenes, tid) do
      nil ->
        {:noreply, socket}

      tokene ->
        {:ok, behavior, fragments} = Tokene.shatter(tokene)
        World.remove_tokene(socket.assigns.world_pid, tid)

        # Without registering, fragments only exist on the client — the server
        # wouldn't find them on a future shatter call, so they'd stay stuck
        # pulsing at near-death forever.
        if behavior in [:split, :explode] and fragments != [] do
          World.register_fragments(socket.assigns.world_pid, tokene.source_id, fragments)
        end

        {:noreply, apply_shatter(socket, tid, behavior, fragments)}
    end
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

    {:noreply, push_event(socket, "update_collector", %{collector_id: id, buffer: []})}
  end

  def handle_event("rotate_passive", %{"node_id" => id}, socket) do
    case World.rotate_passive(socket.assigns.world_pid, id) do
      {:ok, _new_angle} ->
        # Fetch the updated node and reuse the same client-rebuild path the
        # config panel uses so the rotation is reflected visually.
        world = World.get_state(socket.assigns.world_pid)
        node = Map.get(world.nodes, id)
        socket = maybe_push_config_update(socket, node)

        socket =
          if socket.assigns.selected_node && socket.assigns.selected_node.id == id,
            do: assign(socket, :selected_node, node),
            else: socket

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_node", %{"node_id" => id}, socket) do
    world = World.get_state(socket.assigns.world_pid)

    case Map.get(world.nodes, id) do
      nil ->
        {:noreply, clear_config_assigns(socket)}

      node ->
        {:noreply, socket |> assign(:selected_node, node) |> assign(:template_node, nil)}
    end
  end

  def handle_event("deselect_node", _params, socket) do
    {:noreply, clear_config_assigns(socket)}
  end

  def handle_event("clear_config", _params, socket) do
    {:noreply, clear_config_assigns(socket)}
  end

  def handle_event("preview_template", %{"kind" => kind} = params, socket) do
    case SidebarActions.build_template(kind, params) do
      nil ->
        {:noreply, socket}

      template ->
        {:noreply, socket |> assign(:template_node, template) |> assign(:selected_node, nil)}
    end
  end

  def handle_event("commit_template", _params, socket) do
    case socket.assigns.template_node do
      nil ->
        {:noreply, socket}

      template ->
        {_px, py} = template.position
        {x, socket} = SidebarActions.next_x(socket, py)
        node = %{template | position: {x, py}}

        {:noreply,
         socket
         |> SidebarActions.add_and_select(node)
         |> assign(:template_node, nil)}
    end
  end

  def handle_event("update_node_config", params, socket) do
    cond do
      socket.assigns.template_node ->
        node = socket.assigns.template_node
        updated_config = apply_config_changes(node, params)
        {:noreply, assign(socket, :template_node, %{node | config: updated_config})}

      socket.assigns.selected_node ->
        node = socket.assigns.selected_node
        updated_config = apply_config_changes(node, params)

        {:ok, updated} =
          World.update_node(socket.assigns.world_pid, node.id, %{config: updated_config})

        socket = maybe_push_config_update(socket, updated)

        {:noreply, assign(socket, :selected_node, updated)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_node", %{"node_id" => id}, socket) do
    world = World.get_state(socket.assigns.world_pid)
    node = Map.get(world.nodes, id)
    World.remove_node(socket.assigns.world_pid, id)

    count_delta = if is_nil(node), do: 0, else: -1

    socket =
      socket
      |> update(:node_count, &max(&1 + count_delta, 0))
      |> then(fn s ->
        if s.assigns.selected_node && s.assigns.selected_node.id == id,
          do: assign(s, :selected_node, nil),
          else: s
      end)

    {:noreply, socket}
  end

  # PubSub handlers
  @impl true
  def handle_info({:emit, emitter_id, tokenes, rate}, socket) do
    tokene_data =
      Enum.map(tokenes, &tokene_to_wire(&1, %{emit_rate: rate, created_at: &1.created_at}))

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

  def handle_info(:tick, socket) do
    unless socket.assigns.paused do
      World.tick(socket.assigns.world_pid)
    end

    Process.send_after(self(), :tick, socket.assigns.tick_rate)
    {:noreply, socket}
  end

  def handle_info({:node_added, _node}, socket), do: {:noreply, socket}
  def handle_info({:node_removed, _id}, socket), do: {:noreply, socket}
  def handle_info({:node_updated, _node}, socket), do: {:noreply, socket}

  def handle_info({:transform, transformer_id, old_tokene_id, result_tokenes}, socket) do
    new_tokene_data = Enum.map(result_tokenes, &tokene_to_wire/1)

    count_delta = length(result_tokenes) - 1

    socket =
      socket
      |> push_event("transform_tokene", %{
        transformer_id: transformer_id,
        old_tokene_id: old_tokene_id,
        new_tokenes: new_tokene_data
      })
      |> update(:tokene_count, &max(&1 + count_delta, 0))

    {:noreply, socket}
  end

  # Helpers

  defp do_load_world(socket, snapshot, name) do
    world = World.get_state(socket.assigns.world_pid)
    Enum.each(Map.keys(world.tokenes), &World.remove_tokene(socket.assigns.world_pid, &1))
    Enum.each(Map.keys(world.nodes), &World.remove_node(socket.assigns.world_pid, &1))

    {:ok, node_count} = Snapshot.load_into(socket.assigns.world_pid, snapshot)
    loaded_world = World.get_state(socket.assigns.world_pid)
    decay = Map.get(loaded_world.environment, :decay, %{})
    enabled = Map.get(decay, :enabled, true)
    rate = Map.get(decay, :rate, 1.0)

    socket
    |> push_event("clear_tokenes", %{})
    |> push_event("clear_nodes", %{})
    |> push_event("set_decay", %{enabled: enabled, rate: rate})
    |> assign(:tokene_count, 0)
    |> assign(:node_count, node_count)
    |> assign(:world_name, snapshot["name"] || name)
    |> assign(:decay_enabled, enabled)
    |> assign(:decay_rate, rate)
    |> assign(:decay_shatter, Map.get(decay, :shatter, :split))
    |> then(fn s ->
      Enum.reduce(Map.values(loaded_world.nodes), s, &SidebarActions.push_node(&2, &1))
    end)
  end

  defp clear_config_assigns(socket) do
    socket |> assign(:selected_node, nil) |> assign(:template_node, nil)
  end

  # --- Config-panel updates ---

  defp apply_config_changes(%{type: :emitter, config: config}, params) do
    case params["field"] do
      "command" -> %{config | command: params["val"] || config.command}
      "chunker" -> %{config | chunker: SidebarActions.chunker_module(params["val"])}
      "emit_rate" -> %{config | emit_rate: parse_int(params["val"], config.emit_rate)}
      _ -> config
    end
  end

  defp apply_config_changes(%{type: :collector, config: config}, params) do
    apply_collector_field(config, params["field"], params["val"])
  end

  defp apply_config_changes(%{type: :transformer, config: config}, params) do
    update_transformer_field(config, params["field"], params["val"])
  end

  defp apply_config_changes(%{type: :passive, config: config}, params) do
    case params["field"] do
      "shape" ->
        %{config | shape: SidebarActions.shape_atom(params["val"]) || config.shape}

      "width" ->
        %{config | width: parse_float(params["val"], config.width)}

      "height" ->
        %{config | height: parse_float(params["val"], config.height)}

      "angle" ->
        %{config | angle: parse_float(params["val"], config.angle)}

      "speed" ->
        %{config | speed: parse_float(params["val"], config.speed)}

      "channel" ->
        %{config | channel: params["val"] |> to_string() |> String.slice(0, 8)}

      _ ->
        config
    end
  end

  defp apply_config_changes(%{config: config}, _params), do: config

  defp update_transformer_field(config, "effect", val),
    do: %{config | effect: SidebarActions.effect_atom(val) || config.effect}

  defp update_transformer_field(config, "radius", val),
    do: %{config | radius: parse_float(val, config.radius)}

  defp update_transformer_field(config, "strength", val),
    do: %{config | strength: parse_float(val, config.strength)}

  defp update_transformer_field(config, "polarity", val),
    do: %{config | polarity: SidebarActions.polarity_atom(val) || config.polarity}

  defp update_transformer_field(config, "target_encoding", val) do
    case val do
      v when v in [nil, "", "any"] ->
        %{config | target_encoding: nil}

      v ->
        %{config | target_encoding: SidebarActions.encoding_atom(v) || config.target_encoding}
    end
  end

  defp update_transformer_field(config, "pattern", val) do
    pattern = val || ""
    compiled = if pattern == "", do: nil, else: SidebarActions.compile_regex(pattern)
    %{config | pattern: pattern, compiled_pattern: compiled}
  end

  defp update_transformer_field(config, _field, _val), do: config

  defp apply_collector_field(config, "capacity", val),
    do: %{config | capacity: parse_int(val, config.capacity)}

  defp apply_collector_field(config, "trigger_mode", val),
    do: %{config | trigger_mode: safe_trigger_mode(val)}

  defp apply_collector_field(config, "action", val),
    do: %{config | action: SidebarActions.collector_action(val)}

  defp apply_collector_field(config, "output_chunker", val),
    do: %{config | output_chunker: SidebarActions.chunker_module(val)}

  defp apply_collector_field(config, "emit_rate", val),
    do: %{config | emit_rate: parse_int(val, config.emit_rate)}

  defp apply_collector_field(config, "emit", val) do
    emit = val == "true"

    chunker =
      if emit and is_nil(config.output_chunker),
        do: Quantok.Chunker.Word,
        else: config.output_chunker

    %{config | emit: emit, output_chunker: chunker}
  end

  defp apply_collector_field(config, _, _), do: config

  defp safe_trigger_mode("on_full"), do: :on_full
  defp safe_trigger_mode("manual"), do: :manual
  defp safe_trigger_mode("timed"), do: :timed
  defp safe_trigger_mode(_), do: :on_full

  defp parse_int(val, default) do
    case Integer.parse(to_string(val)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_float(val, default) do
    case Float.parse(to_string(val)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp apply_shatter(socket, tid, :dissolve, _fragments) do
    socket
    |> push_event("shatter_tokene", %{tokene_id: tid, behavior: "dissolve", fragments: []})
    |> update(:tokene_count, &max(&1 - 1, 0))
  end

  defp apply_shatter(socket, tid, behavior, fragments)
       when behavior in [:split, :explode] do
    fragment_data = Enum.map(fragments, &serialize_fragment/1)

    socket
    |> push_event("shatter_tokene", %{
      tokene_id: tid,
      behavior: to_string(behavior),
      fragments: fragment_data
    })
    |> update(:tokene_count, &max(&1 + length(fragments) - 1, 0))
  end

  defp apply_shatter(socket, tid, :fossilize, [fossil | _]) do
    socket
    |> push_event("shatter_tokene", %{
      tokene_id: tid,
      behavior: "fossilize",
      fragments: [serialize_fragment(fossil)]
    })
  end

  defp serialize_fragment(t), do: tokene_to_wire(t)

  # The single source of truth for the tokene payload pushed to the client.
  # Emit adds :emit_rate and :created_at; transform/fragment omit them.
  defp tokene_to_wire(t, extras \\ %{}) do
    {w, h} = Tokene.dimensions(t)

    %{
      id: t.id,
      value: Tokene.display_value(t),
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
    |> Map.merge(extras)
  end

  # Magnets compute forces client-side from cached state, so config edits
  # (polarity/pattern/encoding/radius/strength) must be pushed so the client
  # can re-register the magnet entry.
  # Transformer + passive config changes have to round-trip: radius drives the
  # transformer's visible body + sensor zone; width / shape / speed / channel
  # drive a passive's collider and rendered geometry. The client tears down and
  # rebuilds physics + mesh under the same id.
  defp maybe_push_config_update(socket, %{type: type} = node)
       when type in [:transformer, :passive, :collector] do
    payload = %{
      node_id: node.id,
      width: SidebarActions.node_width(node),
      height: SidebarActions.node_height(node),
      config: SidebarActions.serialize_config(node.config)
    }

    # A collector rebuild clears the rendered buffer-slot fills (paint lives on
    # the client). Re-send the current buffer so the slots repaint immediately
    # after the new mesh is installed — otherwise mid-fill collectors look
    # empty until the next absorb event.
    payload =
      if type == :collector,
        do: Map.put(payload, :buffer, get_buffer_data(socket.assigns.world_pid, node.id)),
        else: payload

    push_event(socket, "update_node_config", payload)
  end

  defp maybe_push_config_update(socket, _node), do: socket

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
          %{value: Tokene.display_value(t), encoding: to_string(t.encoding)}
        end)

      _ ->
        []
    end
  end
end
