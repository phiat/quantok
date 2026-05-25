defmodule QuantokWeb.WorldSidebar.Actions do
  @moduledoc """
  Plumbing for the sidebar (and the matching template-preview flow): turns
  string-keyed UI events into new nodes, places them, and installs them in the
  world. The atom/module lookup tables are also here because the config panel
  reads strings from the same vocabulary back.

  Each `add_*/2` returns an updated socket. Callers (`WorldLive`) wrap the
  result with `{:noreply, ...}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Quantok.Node.{Collector, Emitter, Passive, Transformer}
  alias Quantok.World

  # --- Add handlers ---------------------------------------------------------

  def add_source_emitter(socket, params) do
    case source_module(params["source"]) do
      nil ->
        socket

      source_mod ->
        chunker_mod = chunker_module(params["chunker"] || "word")
        command = params["command"] || ""
        {x, socket} = next_x(socket, -300.0)

        emitter =
          Emitter.new(
            source: source_mod,
            command: command,
            chunker: chunker_mod,
            position: {x, -300.0},
            label: params["source"]
          )

        add_and_select(socket, emitter)
    end
  end

  def add_collector(socket, %{"capacity" => cap_str}) do
    capacity = String.to_integer(cap_str)
    {x, socket} = next_x(socket, 250.0)
    collector = Collector.new(capacity: capacity, position: {x, 250.0}, label: "Collector")
    add_and_select(socket, collector)
  end

  def add_typed_collector(socket, %{"action" => action, "capacity" => cap_str}) do
    capacity = String.to_integer(cap_str)
    action_mod = collector_action(action)
    {x, socket} = next_x(socket, 250.0)

    collector =
      Collector.new(
        capacity: capacity,
        action: action_mod,
        emit: true,
        output_chunker: Quantok.Chunker.Byte,
        position: {x, 250.0},
        label: String.capitalize(action)
      )

    add_and_select(socket, collector)
  end

  def add_timed_collector(socket, %{"capacity" => cap_str, "interval" => int_str}) do
    capacity = String.to_integer(cap_str)
    interval = String.to_integer(int_str)
    {x, socket} = next_x(socket, 250.0)

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

    add_and_select(socket, collector)
  end

  def add_emit_collector(socket, %{
        "action" => action,
        "capacity" => cap_str,
        "chunker" => chunker
      }) do
    capacity = String.to_integer(cap_str)
    action_mod = collector_action(action)
    chunker_mod = chunker_module(chunker)
    {x, socket} = next_x(socket, 250.0)

    collector =
      Collector.new(
        capacity: capacity,
        action: action_mod,
        emit: true,
        output_chunker: chunker_mod,
        position: {x, 250.0},
        label: String.capitalize(action) <> " emit"
      )

    add_and_select(socket, collector)
  end

  def add_transformer(socket, %{"effect" => effect} = params) do
    case effect_atom(effect) do
      nil ->
        socket

      effect_atom ->
        {x, socket} = next_x(socket, 0.0)
        opts = transformer_opts(effect_atom, params, x)
        add_and_select(socket, Transformer.new(effect_atom, opts))
    end
  end

  def add_passive(socket, %{"shape" => "portal"}) do
    world = World.get_state(socket.assigns.world_pid)

    used =
      world.nodes
      |> Map.values()
      |> Enum.filter(&(&1.type == :passive and &1.config.shape == :portal))
      |> Enum.map(& &1.config.channel)
      |> MapSet.new()

    case Enum.find(~w(A B C D E F), &(not MapSet.member?(used, &1))) do
      nil ->
        socket

      channel ->
        {x1, socket} = next_x(socket, 100.0)
        portal1 = Passive.new(:portal, channel: channel, position: {x1, 100.0})
        socket = add_and_select(socket, portal1)

        {x2, socket} = next_x(socket, 100.0)
        portal2 = Passive.new(:portal, channel: channel, position: {x2, 100.0})
        add_and_select(socket, portal2)
    end
  end

  def add_passive(socket, %{"shape" => shape} = params) do
    case shape_atom(shape) do
      nil ->
        socket

      shape_atom ->
        {x, socket} = next_x(socket, 100.0)
        passive = Passive.new(shape_atom, passive_opts(shape_atom, params, x))
        add_and_select(socket, passive)
    end
  end

  # --- Templates (preview before commit) ------------------------------------

  def build_template("source_emitter", params) do
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

  def build_template("collector", %{"capacity" => cap}) do
    Collector.new(capacity: parse_int(cap, 8), position: {0.0, 250.0}, label: "Collector")
  end

  def build_template("typed_collector", %{"action" => action, "capacity" => cap}) do
    Collector.new(
      capacity: parse_int(cap, 8),
      action: collector_action(action),
      emit: true,
      output_chunker: Quantok.Chunker.Byte,
      position: {0.0, 250.0},
      label: String.capitalize(action)
    )
  end

  def build_template("timed_collector", %{"capacity" => cap, "interval" => int}) do
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

  def build_template("emit_collector", %{"action" => action, "capacity" => cap, "chunker" => ch}) do
    Collector.new(
      capacity: parse_int(cap, 4),
      action: collector_action(action),
      emit: true,
      output_chunker: chunker_module(ch),
      position: {0.0, 250.0},
      label: String.capitalize(action) <> " emit"
    )
  end

  def build_template("transformer", %{"effect" => effect}) do
    case effect_atom(effect) do
      nil -> nil
      atom -> Transformer.new(atom, position: {0.0, 0.0}, radius: 60.0)
    end
  end

  def build_template("passive", %{"shape" => shape} = params) do
    case shape_atom(shape) do
      nil -> nil
      atom -> Passive.new(atom, passive_opts(atom, params, 0.0))
    end
  end

  def build_template(_, _), do: nil

  # --- Install + push -------------------------------------------------------

  @doc """
  Install a node in the world, push it to the client, bump the node counter,
  and select it. Public so `commit_template` (which builds the node from a
  preview) can share the same install path.
  """
  def add_and_select(socket, node) do
    {:ok, _} = World.add_node(socket.assigns.world_pid, node)
    new_count = socket.assigns.node_count + 1

    socket
    |> push_node(node)
    |> assign(:node_count, new_count)
    |> assign(:selected_node, node)
  end

  @doc """
  Push an "add_node" event so the client creates the matching three.js mesh
  and physics body. Reused by snapshot load and live config refreshes.
  """
  def push_node(socket, node) do
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

  @doc """
  Bounding-box width for the wire payload. Public so config-update pushes can
  recompute the same value the server uses at install time.
  """
  def node_width(%{type: :passive, config: %{width: w}}), do: w
  def node_width(%{type: :collector, config: %{capacity: cap}}), do: max(cap * 12, 80)
  def node_width(%{type: :transformer, config: %{radius: r}}), do: r * 2
  def node_width(_), do: 80.0

  @doc "Bounding-box height for the wire payload (see `node_width/1`)."
  def node_height(%{type: :passive, config: %{height: h}}), do: h
  def node_height(%{type: :transformer, config: %{radius: r}}), do: r * 2
  def node_height(_), do: 40.0

  @doc """
  Serialize a node's config map into JSON-safe terms (atoms → strings).
  Public so config-panel updates can re-push the same payload shape.
  """
  def serialize_config(config) when is_map(config) do
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
      :speed,
      :channel,
      :polarity,
      :target_encoding,
      :pattern
    ])
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v), do: v

  # --- Per-type opts (used by both add_* and build_template) ----------------

  def transformer_opts(:magnet, params, x) do
    # Magnet defaults live in Quantok.Node.Transformer.default_radius/strength.
    polarity = polarity_atom(params["polarity"]) || :attract
    base = [position: {x, 0.0}, polarity: polarity]

    base
    |> maybe_kw(:target_encoding, encoding_atom(params["target_encoding"]))
    |> maybe_kw(:pattern, params["pattern"])
  end

  def transformer_opts(_effect, _params, x), do: [position: {x, 0.0}, radius: 60.0]

  defp maybe_kw(kw, _key, nil), do: kw
  defp maybe_kw(kw, _key, ""), do: kw
  defp maybe_kw(kw, key, value), do: Keyword.put(kw, key, value)

  def passive_opts(:conveyor, params, x) do
    speed = parse_float(params["speed"] || "80", 80.0)
    [position: {x, 100.0}, speed: speed]
  end

  def passive_opts(:portal, params, x) do
    channel = (params["channel"] || "A") |> to_string() |> String.slice(0, 8)
    [position: {x, 100.0}, channel: channel]
  end

  def passive_opts(_shape, _params, x), do: [position: {x, 100.0}]

  # --- Placement ------------------------------------------------------------

  # Pick the next x position that isn't already occupied. Walks the staggered
  # sequence (0, -120, 120, -240, ...) and skips slots near an existing node
  # at roughly the same y row.
  def next_x(socket, y) do
    world = World.get_state(socket.assigns.world_pid)
    occupied = Enum.map(world.nodes, fn {_, n} -> n.position end)

    x =
      0
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&staggered_x/1)
      |> Stream.drop_while(fn cx -> overlaps?(occupied, cx, y) end)
      |> Enum.at(0)

    {x, assign(socket, :next_x, socket.assigns.next_x + 1)}
  end

  defp staggered_x(0), do: 0.0

  defp staggered_x(n),
    do: div(n + 1, 2) * 120.0 * if(rem(n, 2) == 1, do: -1, else: 1)

  defp overlaps?(occupied, cx, y) do
    Enum.any?(occupied, fn {ox, oy} ->
      abs(ox - cx) < 80 and (is_nil(y) or abs(oy - y) < 100)
    end)
  end

  # --- Lookups (shared with config panel) -----------------------------------

  def effect_atom("splitter"), do: :splitter
  def effect_atom("crusher"), do: :crusher
  def effect_atom("heater"), do: :heater
  def effect_atom("cooler"), do: :cooler
  def effect_atom("filter"), do: :filter
  def effect_atom("duplicator"), do: :duplicator
  def effect_atom("painter"), do: :painter
  def effect_atom("tiktoken"), do: :tiktoken
  def effect_atom("magnet"), do: :magnet
  def effect_atom(_), do: nil

  def polarity_atom("attract"), do: :attract
  def polarity_atom("repel"), do: :repel
  def polarity_atom(_), do: nil

  def encoding_atom("bit"), do: :bit
  def encoding_atom("byte"), do: :byte
  def encoding_atom("rune"), do: :rune
  def encoding_atom("token"), do: :token
  def encoding_atom("token_id"), do: :token_id
  def encoding_atom("word"), do: :word
  def encoding_atom("phrase"), do: :phrase
  def encoding_atom("sentence"), do: :sentence
  def encoding_atom(_), do: nil

  def compile_regex(pattern) do
    case Regex.compile(pattern) do
      {:ok, r} -> r
      _ -> nil
    end
  end

  def shape_atom("floor"), do: :floor
  def shape_atom("wall"), do: :wall
  def shape_atom("ramp"), do: :ramp
  def shape_atom("conveyor"), do: :conveyor
  def shape_atom("portal"), do: :portal
  def shape_atom(_), do: nil

  def source_module("clock"), do: Quantok.Node.Emitter.Clock
  def source_module("emoji"), do: Quantok.Node.Emitter.Emoji
  def source_module("file"), do: Quantok.Node.Emitter.File
  def source_module("manual"), do: Quantok.Node.Emitter.Manual
  def source_module("sequence"), do: Quantok.Node.Emitter.Sequence
  def source_module("random"), do: Quantok.Node.Emitter.Random
  def source_module("shell"), do: Quantok.Node.Emitter.Shell
  def source_module(_), do: nil

  def collector_action("echo"), do: Quantok.Node.Collector.Echo
  def collector_action("shell"), do: Quantok.Node.Collector.Shell
  def collector_action("reverse"), do: Quantok.Node.Collector.Reverse
  def collector_action("upcase"), do: Quantok.Node.Collector.Upcase
  def collector_action("count"), do: Quantok.Node.Collector.Count
  def collector_action("display"), do: Quantok.Node.Collector.Display
  def collector_action("hash"), do: Quantok.Node.Collector.Hash
  def collector_action("sum"), do: Quantok.Node.Collector.Sum
  def collector_action("min"), do: Quantok.Node.Collector.Min
  def collector_action("max"), do: Quantok.Node.Collector.Max
  def collector_action(_), do: Quantok.Node.Collector.Echo

  def shatter_atom("split"), do: :split
  def shatter_atom("dissolve"), do: :dissolve
  def shatter_atom("explode"), do: :explode
  def shatter_atom("fossilize"), do: :fossilize
  def shatter_atom(_), do: :split

  def chunker_module("bit"), do: Quantok.Chunker.Bit
  def chunker_module("byte"), do: Quantok.Chunker.Byte
  def chunker_module("rune"), do: Quantok.Chunker.Rune
  def chunker_module("token"), do: Quantok.Chunker.BPE
  def chunker_module("word"), do: Quantok.Chunker.Word
  def chunker_module("phrase"), do: Quantok.Chunker.Phrase
  def chunker_module("sentence"), do: Quantok.Chunker.Sentence
  def chunker_module(_), do: Quantok.Chunker.Word

  # --- Tiny parsers shared by builders --------------------------------------

  defp parse_int(val, default) do
    case Integer.parse(to_string(val || "")) do
      {n, _} -> n
      _ -> default
    end
  end

  defp parse_float(val, default) do
    case Float.parse(to_string(val || "")) do
      {f, _} -> f
      _ -> default
    end
  end
end
