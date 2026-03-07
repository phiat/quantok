defmodule Quantok.World.Snapshot do
  @moduledoc """
  Serialize and deserialize world state for save/load.
  Saves node configs and environment, not active tokenes (ephemeral).
  """

  alias Quantok.Node
  alias Quantok.Node.{Collector, Emitter, Passive, Transformer}
  alias Quantok.World

  @version 1

  @doc """
  Serialize a world state to a JSON-compatible map.
  """
  @spec to_map(World.t()) :: map()
  def to_map(%World{} = world) do
    %{
      "version" => @version,
      "name" => world.name,
      "environment" => serialize_environment(world.environment),
      "nodes" => Enum.map(Map.values(world.nodes), &serialize_node/1)
    }
  end

  @doc """
  Encode a world state to JSON string.
  """
  @spec to_json(World.t()) :: binary()
  def to_json(%World{} = world) do
    world |> to_map() |> Jason.encode!(pretty: true)
  end

  @doc """
  Restore nodes from a snapshot map into a running world.
  Returns {:ok, count} with the number of nodes restored.
  """
  @spec load_into(pid(), map()) :: {:ok, non_neg_integer()}
  def load_into(world_pid, %{"version" => 1} = snapshot) do
    load_environment(world_pid, snapshot["environment"])

    nodes = snapshot["nodes"] || []
    Enum.each(nodes, fn data -> World.add_node(world_pid, deserialize_node(data)) end)
    {:ok, length(nodes)}
  end

  def load_into(_world_pid, %{"version" => v}) do
    {:error, {:unsupported_version, v}}
  end

  defp load_environment(_world_pid, nil), do: :ok

  defp load_environment(world_pid, env) do
    gx = get_in(env, ["gravity", "x"]) || 0.0
    gy = get_in(env, ["gravity", "y"]) || 9.81
    World.set_gravity(world_pid, {gx, gy})
    load_decay(world_pid, env["decay"])
  end

  defp load_decay(_world_pid, nil), do: :ok

  defp load_decay(world_pid, decay) do
    World.set_decay(world_pid, %{
      enabled: decay["enabled"] == true,
      rate: decay["rate"] || 1.0,
      shatter: safe_shatter(decay["shatter"])
    })
  end

  defp safe_shatter("split"), do: :split
  defp safe_shatter("dissolve"), do: :dissolve
  defp safe_shatter("explode"), do: :explode
  defp safe_shatter("fossilize"), do: :fossilize
  defp safe_shatter(_), do: :split

  @doc """
  Load from a JSON string.
  """
  @spec from_json(binary()) :: {:ok, map()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> {:ok, map}
      {:error, reason} -> {:error, {:json_decode, reason}}
    end
  end

  @doc """
  List saved world files from a directory.
  """
  @spec list_saves(binary()) :: [%{name: binary(), path: binary(), modified: DateTime.t()}]
  def list_saves(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      stat = File.stat!(path, time: :posix)

      %{
        name: Path.basename(path, ".json"),
        path: path,
        modified: DateTime.from_unix!(stat.mtime)
      }
    end)
    |> Enum.sort_by(& &1.modified, {:desc, DateTime})
  end

  @doc """
  Save a world snapshot to a JSON file.
  """
  @spec save_to_file(World.t(), binary()) :: :ok | {:error, term()}
  def save_to_file(%World{} = world, path) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.write(path, to_json(world))
  end

  @doc """
  Load a world snapshot from a JSON file.
  """
  @spec load_from_file(binary()) :: {:ok, map()} | {:error, term()}
  def load_from_file(path) do
    case File.read(path) do
      {:ok, json} -> from_json(json)
      {:error, reason} -> {:error, {:file_read, reason}}
    end
  end

  # --- Serialization ---

  defp serialize_environment(env) do
    {gx, gy} = Map.get(env, :gravity, {0.0, 9.81})
    decay = Map.get(env, :decay, %{})

    %{
      "gravity" => %{"x" => gx, "y" => gy},
      "tick_rate" => Map.get(env, :tick_rate, 30),
      "decay" => %{
        "enabled" => Map.get(decay, :enabled, false),
        "rate" => Map.get(decay, :rate, 1.0),
        "shatter" => to_string(Map.get(decay, :shatter, :split))
      }
    }
  end

  defp serialize_node(%Node{} = node) do
    {px, py} = node.position

    %{
      "type" => to_string(node.type),
      "label" => node.label,
      "position" => %{"x" => px, "y" => py},
      "config" => serialize_node_config(node.type, node.config)
    }
  end

  defp serialize_node_config(:emitter, config) do
    %{
      "source" => module_to_string(config.source),
      "command" => config.command,
      "chunker" => module_to_string(config.chunker),
      "emit_rate" => config.emit_rate,
      "auto_repeat" => config[:auto_repeat] || false,
      "repeat_interval" => config[:repeat_interval] || 5000
    }
  end

  defp serialize_node_config(:collector, config) do
    base = %{
      "capacity" => config.capacity,
      "trigger_mode" => to_string(config.trigger_mode),
      "tick_interval" => config.tick_interval,
      "action" => module_to_string(config.action),
      "command" => config.command,
      "output_mode" => to_string(config.output_mode)
    }

    base =
      if config.output_chunker do
        Map.put(base, "output_chunker", module_to_string(config.output_chunker))
      else
        base
      end

    if config.paired_emitter_id do
      Map.put(base, "paired_emitter_id", config.paired_emitter_id)
    else
      base
    end
  end

  defp serialize_node_config(:transformer, config) do
    %{
      "effect" => to_string(config.effect),
      "radius" => config.radius,
      "strength" => config.strength,
      "target_encoding" => config[:target_encoding] && to_string(config.target_encoding),
      "pattern" => config[:pattern],
      "color" => config[:color]
    }
  end

  defp serialize_node_config(:passive, config) do
    %{
      "shape" => to_string(config.shape),
      "width" => config.width,
      "height" => config.height,
      "angle" => config.angle,
      "friction" => config.friction,
      "restitution" => config.restitution,
      "strength" => config.strength,
      "radius" => config.radius
    }
  end

  # --- Deserialization ---

  @allowed_shell_commands ["date", "uname -a", "echo hello world", "hostname", "whoami", "uptime"]

  defp deserialize_node(%{"type" => "emitter"} = data) do
    source = string_to_module(data["config"]["source"], :emitter_source)
    command = data["config"]["command"] || "echo hello"

    # Shell source commands must be in the allowlist
    safe_command =
      if source == Quantok.Node.Emitter.Shell and command not in @allowed_shell_commands do
        "echo hello"
      else
        command
      end

    Emitter.new(
      source: source,
      command: safe_command,
      chunker: string_to_module(data["config"]["chunker"], :chunker),
      emit_rate: data["config"]["emit_rate"] || 100,
      position: deserialize_position(data["position"]),
      label: data["label"] || "Emitter"
    )
  end

  @allowed_collector_commands ["echo", "cat", "wc -c", "wc -w", "wc -l"]

  defp deserialize_node(%{"type" => "collector"} = data) do
    action = string_to_module(data["config"]["action"], :collector_action)
    command = data["config"]["command"] || "echo"

    # Shell action commands must be in the allowlist
    safe_command =
      if action == Quantok.Node.Collector.Shell and command not in @allowed_collector_commands do
        "echo"
      else
        command
      end

    config = data["config"]
    output_chunker = if config["output_chunker"],
      do: string_to_module(config["output_chunker"], :chunker),
      else: nil

    opts = [
      capacity: config["capacity"] || 8,
      trigger_mode: safe_trigger_mode(config["trigger_mode"]),
      tick_interval: config["tick_interval"] || 120,
      action: action,
      command: safe_command,
      output_mode: safe_output_mode(config["output_mode"]),
      output_chunker: output_chunker,
      position: deserialize_position(data["position"]),
      label: data["label"] || "Collector"
    ]

    opts =
      if config["paired_emitter_id"] do
        Keyword.put(opts, :paired_emitter_id, config["paired_emitter_id"])
      else
        opts
      end

    Collector.new(opts)
  end

  defp deserialize_node(%{"type" => "transformer"} = data) do
    effect = safe_effect(data["config"]["effect"])

    Transformer.new(effect,
      radius: data["config"]["radius"] || 50.0,
      strength: data["config"]["strength"] || 0.5,
      position: deserialize_position(data["position"]),
      label: data["label"] || "Transformer"
    )
  end

  defp deserialize_node(%{"type" => "passive"} = data) do
    shape = safe_shape(data["config"]["shape"])
    config = data["config"]

    Passive.new(shape,
      width: config["width"] || 200.0,
      height: config["height"] || 10.0,
      angle: config["angle"] || 0.0,
      friction: config["friction"] || 0.5,
      restitution: config["restitution"] || 0.3,
      strength: config["strength"] || 1.0,
      radius: config["radius"] || 100.0,
      position: deserialize_position(data["position"]),
      label: data["label"]
    )
  end

  defp deserialize_position(%{"x" => x, "y" => y}), do: {x * 1.0, y * 1.0}
  defp deserialize_position(_), do: {0.0, 0.0}

  # Module name mapping (safe, no arbitrary atom creation)

  @source_modules %{
    "Quantok.Node.Emitter.Shell" => Quantok.Node.Emitter.Shell,
    "Quantok.Node.Emitter.Manual" => Quantok.Node.Emitter.Manual,
    "Quantok.Node.Emitter.Clock" => Quantok.Node.Emitter.Clock,
    "Quantok.Node.Emitter.File" => Quantok.Node.Emitter.File,
    "Quantok.Node.Emitter.Sequence" => Quantok.Node.Emitter.Sequence
  }

  @chunker_modules %{
    "Quantok.Chunker.Bit" => Quantok.Chunker.Bit,
    "Quantok.Chunker.Byte" => Quantok.Chunker.Byte,
    "Quantok.Chunker.Rune" => Quantok.Chunker.Rune,
    "Quantok.Chunker.BPE" => Quantok.Chunker.BPE,
    "Quantok.Chunker.Word" => Quantok.Chunker.Word,
    "Quantok.Chunker.Phrase" => Quantok.Chunker.Phrase,
    "Quantok.Chunker.Sentence" => Quantok.Chunker.Sentence
  }

  @action_modules %{
    "Quantok.Node.Collector.Echo" => Quantok.Node.Collector.Echo,
    "Quantok.Node.Collector.Shell" => Quantok.Node.Collector.Shell,
    "Quantok.Node.Collector.Reverse" => Quantok.Node.Collector.Reverse,
    "Quantok.Node.Collector.Upcase" => Quantok.Node.Collector.Upcase,
    "Quantok.Node.Collector.Count" => Quantok.Node.Collector.Count,
    "Quantok.Node.Collector.Display" => Quantok.Node.Collector.Display
  }

  defp safe_trigger_mode("on_full"), do: :on_full
  defp safe_trigger_mode("manual"), do: :manual
  defp safe_trigger_mode("timed"), do: :timed
  defp safe_trigger_mode("on_tick"), do: :timed
  defp safe_trigger_mode(_), do: :on_full

  defp safe_output_mode("emit"), do: :emit
  defp safe_output_mode("paired"), do: :paired
  defp safe_output_mode("discard"), do: :discard
  defp safe_output_mode(_), do: :discard

  defp safe_effect("splitter"), do: :splitter
  defp safe_effect("crusher"), do: :crusher
  defp safe_effect("heater"), do: :heater
  defp safe_effect("cooler"), do: :cooler
  defp safe_effect("filter"), do: :filter
  defp safe_effect("duplicator"), do: :duplicator
  defp safe_effect("painter"), do: :painter
  defp safe_effect(_), do: :splitter

  defp safe_shape("floor"), do: :floor
  defp safe_shape("wall"), do: :wall
  defp safe_shape("ramp"), do: :ramp
  defp safe_shape("funnel"), do: :funnel
  defp safe_shape("attractor"), do: :attractor
  defp safe_shape("repeller"), do: :repeller
  defp safe_shape(_), do: :floor

  defp module_to_string(mod), do: to_string(mod) |> String.replace_leading("Elixir.", "")

  defp string_to_module(str, :emitter_source), do: Map.get(@source_modules, str, Quantok.Node.Emitter.Shell)
  defp string_to_module(str, :chunker), do: Map.get(@chunker_modules, str, Quantok.Chunker.Word)
  defp string_to_module(str, :collector_action), do: Map.get(@action_modules, str, Quantok.Node.Collector.Echo)
end
