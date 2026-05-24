defmodule QuantokWeb.WorldLive do
  use QuantokWeb, :live_view

  alias Quantok.Node.{Collector, Emitter, Passive, Transformer}
  alias Quantok.Tokene
  alias Quantok.World
  alias Quantok.World.Snapshot
  alias QuantokWeb.{WorldConfig, WorldSidebar}

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
        command: "date",
        chunker: Quantok.Chunker.Word,
        position: {0.0, -300.0},
        label: "date"
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
      |> assign(:decay_enabled, false)
      |> assign(:decay_rate, 1.0)
      |> assign(:decay_shatter, :split)
      |> assign(:selected_node, nil)
      |> assign(:template_node, nil)
      |> assign(:next_x, 0)
      |> push_node(floor)
      |> push_node(emitter)
      |> push_node(collector)

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
    <div class="flex flex-col h-screen w-screen overflow-hidden">
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
            :for={r <- [{0.5, "½×"}, {1.0, "1×"}, {2.0, "2×"}, {4.0, "4×"}]}
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
        <span class="q-status">
          {@tokene_count} tok · {@node_count} nodes · {if @paused, do: "paused", else: @world_name}
        </span>
      </header>

      <div class="flex flex-1 overflow-hidden">
        <WorldSidebar.sidebar />

        <WorldConfig.config_panel selected_node={@selected_node} template_node={@template_node} />

        <div class="q-canvas-wrap">
          <canvas id="world-canvas" phx-hook="WorldCanvas" class="w-full h-full" phx-update="ignore">
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
    shatter_atom = shatter_atom(shatter)
    World.set_decay(socket.assigns.world_pid, %{shatter: shatter_atom})
    {:noreply, assign(socket, :decay_shatter, shatter_atom)}
  end

  @allowed_shell_commands ["date", "uname -a", "echo hello world", "hostname", "whoami", "uptime"]

  def handle_event("add_emitter", %{"command" => command, "chunker" => chunker}, socket) do
    if command in @allowed_shell_commands do
      chunker_mod = chunker_module(chunker)
      {x, socket} = next_x(socket)

      emitter =
        Emitter.new(command: command, chunker: chunker_mod, position: {x, -300.0}, label: command)

      {:ok, _} = World.add_node(socket.assigns.world_pid, emitter)

      {:noreply,
       socket
       |> push_node(emitter)
       |> update(:node_count, &(&1 + 1))
       |> assign(:selected_node, emitter)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_source_emitter", params, socket) do
    # Drop unknown sources silently. The Shell source must go through
    # add_emitter so the @allowed_shell_commands check applies.
    case source_module(params["source"]) do
      nil ->
        {:noreply, socket}

      source_mod ->
        chunker_mod = chunker_module(params["chunker"] || "word")
        command = params["command"] || ""
        {x, socket} = next_x(socket)

        emitter =
          Emitter.new(
            source: source_mod,
            command: command,
            chunker: chunker_mod,
            position: {x, -300.0},
            label: params["source"]
          )

        {:ok, _} = World.add_node(socket.assigns.world_pid, emitter)

        {:noreply,
         socket
         |> push_node(emitter)
         |> update(:node_count, &(&1 + 1))
         |> assign(:selected_node, emitter)}
    end
  end

  def handle_event("add_collector", %{"capacity" => cap_str}, socket) do
    capacity = String.to_integer(cap_str)
    {x, socket} = next_x(socket)
    collector = Collector.new(capacity: capacity, position: {x, 250.0}, label: "Collector")
    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply,
     socket
     |> push_node(collector)
     |> update(:node_count, &(&1 + 1))
     |> assign(:selected_node, collector)}
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
        emit: true,
        output_chunker: Quantok.Chunker.Byte,
        position: {x, 250.0},
        label: label
      )

    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply,
     socket
     |> push_node(collector)
     |> update(:node_count, &(&1 + 1))
     |> assign(:selected_node, collector)}
  end

  def handle_event("add_timed_collector", %{"capacity" => cap_str, "interval" => int_str}, socket) do
    capacity = String.to_integer(cap_str)
    interval = String.to_integer(int_str)
    {x, socket} = next_x(socket)

    collector =
      Collector.new(
        capacity: capacity,
        trigger_mode: :timed,
        tick_interval: interval,
        emit: true,
        output_chunker: Quantok.Chunker.Byte,
        position: {x, 250.0},
        label: "Timed"
      )

    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply,
     socket
     |> push_node(collector)
     |> update(:node_count, &(&1 + 1))
     |> assign(:selected_node, collector)}
  end

  def handle_event(
        "add_emit_collector",
        %{"action" => action, "capacity" => cap_str, "chunker" => chunker},
        socket
      ) do
    capacity = String.to_integer(cap_str)
    action_mod = collector_action(action)
    chunker_mod = chunker_module(chunker)
    {x, socket} = next_x(socket)
    label = String.capitalize(action) <> " emit"

    collector =
      Collector.new(
        capacity: capacity,
        action: action_mod,
        emit: true,
        output_chunker: chunker_mod,
        position: {x, 250.0},
        label: label
      )

    {:ok, _} = World.add_node(socket.assigns.world_pid, collector)

    {:noreply,
     socket
     |> push_node(collector)
     |> update(:node_count, &(&1 + 1))
     |> assign(:selected_node, collector)}
  end

  def handle_event("add_transformer", %{"effect" => effect}, socket) do
    case effect_atom(effect) do
      nil ->
        {:noreply, socket}

      effect_atom ->
        {x, socket} = next_x(socket)
        transformer = Transformer.new(effect_atom, position: {x, 0.0}, radius: 60.0)
        {:ok, _} = World.add_node(socket.assigns.world_pid, transformer)

        {:noreply,
         socket
         |> push_node(transformer)
         |> update(:node_count, &(&1 + 1))
         |> assign(:selected_node, transformer)}
    end
  end

  def handle_event("add_passive", %{"shape" => shape} = params, socket) do
    case shape_atom(shape) do
      nil ->
        {:noreply, socket}

      shape_atom ->
        {x, socket} = next_x(socket)
        passive = Passive.new(shape_atom, passive_opts(shape_atom, params, x))
        {:ok, _} = World.add_node(socket.assigns.world_pid, passive)

        {:noreply,
         socket
         |> push_node(passive)
         |> update(:node_count, &(&1 + 1))
         |> assign(:selected_node, passive)}
    end
  end

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
    World.rotate_passive(socket.assigns.world_pid, id)
    {:noreply, socket}
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
    case build_template(kind, params) do
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
        {x, socket} = next_x(socket)
        {_px, py} = template.position
        node = %{template | position: {x, py}}
        {:ok, _} = World.add_node(socket.assigns.world_pid, node)

        {:noreply,
         socket
         |> push_node(node)
         |> update(:node_count, &(&1 + 1))
         |> assign(:template_node, nil)
         |> assign(:selected_node, node)}
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

  defp do_load_world(socket, snapshot, name) do
    world = World.get_state(socket.assigns.world_pid)
    Enum.each(Map.keys(world.tokenes), &World.remove_tokene(socket.assigns.world_pid, &1))
    Enum.each(Map.keys(world.nodes), &World.remove_node(socket.assigns.world_pid, &1))

    {:ok, node_count} = Snapshot.load_into(socket.assigns.world_pid, snapshot)
    loaded_world = World.get_state(socket.assigns.world_pid)
    decay = Map.get(loaded_world.environment, :decay, %{})

    socket
    |> push_event("clear_tokenes", %{})
    |> push_event("clear_nodes", %{})
    |> assign(:tokene_count, 0)
    |> assign(:node_count, node_count)
    |> assign(:world_name, snapshot["name"] || name)
    |> assign(:decay_enabled, Map.get(decay, :enabled, false))
    |> assign(:decay_rate, Map.get(decay, :rate, 1.0))
    |> assign(:decay_shatter, Map.get(decay, :shatter, :split))
    |> then(fn s ->
      Enum.reduce(Map.values(loaded_world.nodes), s, &push_node(&2, &1))
    end)
  end

  defp clear_config_assigns(socket) do
    socket |> assign(:selected_node, nil) |> assign(:template_node, nil)
  end

  # --- Template builders (preview before commit) ---

  defp build_template("emitter", %{"command" => cmd, "chunker" => ch}) do
    if cmd in @allowed_shell_commands do
      Emitter.new(command: cmd, chunker: chunker_module(ch), position: {0.0, -300.0}, label: cmd)
    end
  end

  defp build_template("source_emitter", params) do
    case source_module(params["source"]) do
      nil ->
        nil

      source_mod ->
        Emitter.new(
          source: source_mod,
          command: params["command"] || "",
          chunker: chunker_module(params["chunker"] || "word"),
          position: {0.0, -300.0},
          label: params["source"]
        )
    end
  end

  defp build_template("collector", %{"capacity" => cap}) do
    Collector.new(
      capacity: parse_int(cap, 8),
      position: {0.0, 250.0},
      label: "Collector"
    )
  end

  defp build_template("typed_collector", %{"action" => action, "capacity" => cap}) do
    Collector.new(
      capacity: parse_int(cap, 8),
      action: collector_action(action),
      emit: true,
      output_chunker: Quantok.Chunker.Byte,
      position: {0.0, 250.0},
      label: String.capitalize(action)
    )
  end

  defp build_template("timed_collector", %{"capacity" => cap, "interval" => int}) do
    Collector.new(
      capacity: parse_int(cap, 8),
      trigger_mode: :timed,
      tick_interval: parse_int(int, 120),
      emit: true,
      output_chunker: Quantok.Chunker.Byte,
      position: {0.0, 250.0},
      label: "Timed"
    )
  end

  defp build_template("emit_collector", %{"action" => action, "capacity" => cap, "chunker" => ch}) do
    Collector.new(
      capacity: parse_int(cap, 4),
      action: collector_action(action),
      emit: true,
      output_chunker: chunker_module(ch),
      position: {0.0, 250.0},
      label: String.capitalize(action) <> " emit"
    )
  end

  defp build_template("transformer", %{"effect" => effect}) do
    case effect_atom(effect) do
      nil -> nil
      atom -> Transformer.new(atom, position: {0.0, 0.0}, radius: 60.0)
    end
  end

  defp build_template("passive", %{"shape" => shape} = params) do
    case shape_atom(shape) do
      nil -> nil
      atom -> Passive.new(atom, passive_opts(atom, params, 0.0))
    end
  end

  defp build_template(_, _), do: nil

  defp apply_config_changes(%{type: :emitter, config: config}, params) do
    case params["field"] do
      "command" -> %{config | command: params["val"] || config.command}
      "chunker" -> %{config | chunker: chunker_module(params["val"])}
      "emit_rate" -> %{config | emit_rate: parse_int(params["val"], config.emit_rate)}
      _ -> config
    end
  end

  defp apply_config_changes(%{type: :collector, config: config}, params) do
    apply_collector_field(config, params["field"], params["val"])
  end

  defp apply_config_changes(%{type: :transformer, config: config}, params) do
    case params["field"] do
      "effect" -> %{config | effect: effect_atom(params["val"]) || config.effect}
      "radius" -> %{config | radius: parse_float(params["val"], config.radius)}
      _ -> config
    end
  end

  defp apply_config_changes(%{type: :passive, config: config}, params) do
    case params["field"] do
      "shape" -> %{config | shape: shape_atom(params["val"]) || config.shape}
      "width" -> %{config | width: parse_float(params["val"], config.width)}
      "speed" -> %{config | speed: parse_float(params["val"], config.speed)}
      _ -> config
    end
  end

  defp apply_config_changes(%{config: config}, _params), do: config

  defp apply_collector_field(config, "capacity", val),
    do: %{config | capacity: parse_int(val, config.capacity)}

  defp apply_collector_field(config, "trigger_mode", val),
    do: %{config | trigger_mode: safe_trigger_mode(val)}

  defp apply_collector_field(config, "action", val), do: %{config | action: collector_action(val)}

  defp apply_collector_field(config, "output_chunker", val),
    do: %{config | output_chunker: chunker_module(val)}

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

  defp serialize_fragment(t) do
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
  end

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
      :capacity,
      :shape,
      :angle,
      :friction,
      :restitution,
      :strength,
      :radius,
      :effect,
      :sensor_radius,
      :trigger_mode,
      :emit,
      :tick_interval,
      :speed
    ])
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v), do: v

  defp passive_opts(:conveyor, params, x) do
    speed = parse_float(params["speed"] || "80", 80.0)
    [position: {x, 100.0}, speed: speed]
  end

  defp passive_opts(_shape, _params, x), do: [position: {x, 100.0}]

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
  defp shape_atom("conveyor"), do: :conveyor
  defp shape_atom(_), do: nil

  defp source_module("clock"), do: Quantok.Node.Emitter.Clock
  defp source_module("file"), do: Quantok.Node.Emitter.File
  defp source_module("manual"), do: Quantok.Node.Emitter.Manual
  defp source_module("sequence"), do: Quantok.Node.Emitter.Sequence
  defp source_module("random"), do: Quantok.Node.Emitter.Random
  defp source_module(_), do: nil

  defp collector_action("echo"), do: Quantok.Node.Collector.Echo
  defp collector_action("shell"), do: Quantok.Node.Collector.Shell
  defp collector_action("reverse"), do: Quantok.Node.Collector.Reverse
  defp collector_action("upcase"), do: Quantok.Node.Collector.Upcase
  defp collector_action("count"), do: Quantok.Node.Collector.Count
  defp collector_action("display"), do: Quantok.Node.Collector.Display
  defp collector_action("hash"), do: Quantok.Node.Collector.Hash
  defp collector_action(_), do: Quantok.Node.Collector.Echo

  defp shatter_atom("split"), do: :split
  defp shatter_atom("dissolve"), do: :dissolve
  defp shatter_atom("explode"), do: :explode
  defp shatter_atom("fossilize"), do: :fossilize
  defp shatter_atom(_), do: :split

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
    x = if n == 0, do: 0.0, else: div(n + 1, 2) * 120.0 * if(rem(n, 2) == 1, do: -1, else: 1)
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
end
