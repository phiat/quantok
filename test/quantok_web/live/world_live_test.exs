defmodule QuantokWeb.WorldLiveTest do
  use QuantokWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Quantok.World

  describe "add_source_emitter" do
    test "rejects unknown source values", %{conn: conn} do
      # source_module/1 must not fall through to a default — unknown
      # source strings should drop the event entirely.
      {:ok, view, _html} = live(conn, ~p"/")
      world_pid = world_pid(view)
      before = map_size(World.get_state(world_pid).nodes)

      render_hook(view, "add_source_emitter", %{
        "source" => "definitely-not-a-source",
        "command" => "echo hi",
        "chunker" => "word"
      })

      assert map_size(World.get_state(world_pid).nodes) == before
    end

    test "accepts known sources and adds the emitter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      world_pid = world_pid(view)
      before = map_size(World.get_state(world_pid).nodes)

      render_hook(view, "add_source_emitter", %{
        "source" => "clock",
        "chunker" => "rune"
      })

      assert map_size(World.get_state(world_pid).nodes) == before + 1
    end
  end

  defp world_pid(view) do
    :sys.get_state(view.pid).socket.assigns.world_pid
  end
end
