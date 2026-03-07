defmodule Quantok.World.SnapshotTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.{Collector, Emitter, Passive, Transformer}
  alias Quantok.World
  alias Quantok.World.Snapshot

  setup do
    {:ok, pid} = World.start_link(world_name: "Test World")
    %{pid: pid}
  end

  test "serializes and deserializes a world", %{pid: pid} do
    emitter = Emitter.new(command: "date", label: "date emitter")
    collector = Collector.new(capacity: 8, label: "my collector")
    transformer = Transformer.new(:splitter, label: "my splitter")
    passive = Passive.new(:ramp, angle: 0.5, label: "my ramp")

    World.add_node(pid, emitter)
    World.add_node(pid, collector)
    World.add_node(pid, transformer)
    World.add_node(pid, passive)

    world = World.get_state(pid)
    snapshot = Snapshot.to_map(world)

    assert snapshot["version"] == 1
    assert snapshot["name"] == "Test World"
    assert length(snapshot["nodes"]) == 4
  end

  test "round-trip through JSON", %{pid: pid} do
    emitter = Emitter.new(command: "echo test", position: {50.0, -100.0}, label: "echo")
    World.add_node(pid, emitter)

    world = World.get_state(pid)
    json = Snapshot.to_json(world)
    {:ok, decoded} = Snapshot.from_json(json)

    assert decoded["name"] == "Test World"
    assert length(decoded["nodes"]) == 1

    node = hd(decoded["nodes"])
    assert node["type"] == "emitter"
    assert node["label"] == "echo"
    assert node["position"]["x"] == 50.0
  end

  test "load_into restores nodes", %{pid: pid} do
    snapshot = %{
      "version" => 1,
      "name" => "Loaded World",
      "environment" => %{"gravity" => %{"x" => 0.0, "y" => 5.0}},
      "nodes" => [
        %{
          "type" => "emitter",
          "label" => "test",
          "position" => %{"x" => 10.0, "y" => 20.0},
          "config" => %{
            "source" => "Quantok.Node.Emitter.Shell",
            "command" => "echo hi",
            "chunker" => "Quantok.Chunker.Word",
            "emit_rate" => 100
          }
        },
        %{
          "type" => "collector",
          "label" => "bucket",
          "position" => %{"x" => 0.0, "y" => 100.0},
          "config" => %{
            "capacity" => 4,
            "trigger_mode" => "on_full",
            "action" => "Quantok.Node.Collector.Echo",
            "command" => "echo"
          }
        }
      ]
    }

    {:ok, 2} = Snapshot.load_into(pid, snapshot)

    world = World.get_state(pid)
    assert map_size(world.nodes) == 2
  end

  test "save and load from file", %{pid: pid} do
    emitter = Emitter.new(command: "date", label: "file test")
    World.add_node(pid, emitter)

    world = World.get_state(pid)
    path = Path.join(System.tmp_dir!(), "quantok_snap_test_#{:rand.uniform(100_000)}.json")

    :ok = Snapshot.save_to_file(world, path)
    assert File.exists?(path)

    {:ok, loaded} = Snapshot.load_from_file(path)
    assert loaded["name"] == "Test World"
    assert length(loaded["nodes"]) == 1

    File.rm!(path)
  end

  test "rejects unsupported version", %{pid: pid} do
    result = Snapshot.load_into(pid, %{"version" => 99})
    assert {:error, {:unsupported_version, 99}} = result
  end

  test "list_saves finds JSON files" do
    dir = Path.join(System.tmp_dir!(), "quantok_saves_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "world1.json"), "{}")
    File.write!(Path.join(dir, "world2.json"), "{}")

    saves = Snapshot.list_saves(dir)
    names = Enum.map(saves, & &1.name)
    assert "world1" in names
    assert "world2" in names

    File.rm_rf!(dir)
  end
end
