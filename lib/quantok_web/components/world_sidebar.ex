defmodule QuantokWeb.WorldSidebar do
  @moduledoc """
  The left-side node menu. Each entry is a single button that adds the node
  with defaults; click the added node in the canvas to configure it.
  """

  use Phoenix.Component

  def sidebar(assigns) do
    ~H"""
    <nav class="q-sidebar">
      <div class="q-section">Emitters</div>
      <.item
        label="clock · word"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "clock", "command" => "%A %B %-d", "chunker" => "word"}}
      />
      <.item
        label="clock · byte"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "clock", "command" => "%H:%M:%S", "chunker" => "byte"}}
      />
      <.item
        label="clock · rune"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "clock", "command" => "%H:%M:%S", "chunker" => "rune"}}
      />
      <.item
        label="hello · token"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "manual", "command" => "hello world", "chunker" => "token"}}
      />
      <.item
        label="A–Z · word"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "sequence", "command" => "alpha", "chunker" => "word"}}
      />
      <.item
        label="pangram · word"
        variant="emit"
        event="add_source_emitter"
        params={
          %{
            "source" => "manual",
            "command" => "The quick brown fox jumps over the lazy dog",
            "chunker" => "word"
          }
        }
      />
      <.item
        label="random alnum · byte"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "random", "command" => "alnum:32", "chunker" => "byte"}}
      />
      <.item
        label="random hex · byte"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "random", "command" => "hex:32", "chunker" => "byte"}}
      />
      <.item
        label="shell · word"
        variant="emit"
        event="add_source_emitter"
        params={%{"source" => "shell", "command" => "echo hello", "chunker" => "word"}}
      />
      <.item
        label="emoji · rune"
        variant="emit"
        event="add_source_emitter"
        params={
          %{
            "source" => "manual",
            "command" => "🚀🌌💫🌟⚡🔥💧🌱🌳🌲🌴🍀🌷🌹🌻🌼🍄🌊🌋🏔️🐶🐱🐭🐰🦊🐻🐼🦁🐢🦋🐝🐙🦀🍎🍊🍋🍌🍉🍇🍓🍑🍕🍔🍟😀😎🤔🤖⚽🎨",
            "chunker" => "rune"
          }
        }
      />

      <div class="q-section">Collectors</div>
      <.item
        label="collect · 8"
        variant="collect"
        event="add_collector"
        params={%{"capacity" => "8"}}
      />
      <.item
        label="collect · 16"
        variant="collect"
        event="add_collector"
        params={%{"capacity" => "16"}}
      />
      <.item
        label="reverse · 8"
        variant="collect"
        event="add_typed_collector"
        params={%{"action" => "reverse", "capacity" => "8"}}
      />
      <.item
        label="upcase · 8"
        variant="collect"
        event="add_typed_collector"
        params={%{"action" => "upcase", "capacity" => "8"}}
      />
      <.item
        label="count · 8"
        variant="collect"
        event="add_typed_collector"
        params={%{"action" => "count", "capacity" => "8"}}
      />
      <.item
        label="timed · 4s"
        variant="collect"
        event="add_timed_collector"
        params={%{"capacity" => "8", "interval" => "120"}}
      />
      <.item
        label="reverse · emit"
        variant="collect"
        event="add_emit_collector"
        params={%{"action" => "reverse", "capacity" => "4", "chunker" => "word"}}
      />
      <.item
        label="upcase · emit"
        variant="collect"
        event="add_emit_collector"
        params={%{"action" => "upcase", "capacity" => "4", "chunker" => "word"}}
      />
      <.item
        label="echo · emit"
        variant="collect"
        event="add_emit_collector"
        params={%{"action" => "echo", "capacity" => "4", "chunker" => "byte"}}
      />
      <.item
        label="sha256 · emit"
        variant="collect"
        event="add_emit_collector"
        params={%{"action" => "hash", "capacity" => "8", "chunker" => "word"}}
      />

      <div class="q-section">Transformers</div>
      <.item
        label="splitter"
        variant="transform"
        event="add_transformer"
        params={%{"effect" => "splitter"}}
      />
      <.item
        label="heater"
        variant="transform"
        event="add_transformer"
        params={%{"effect" => "heater"}}
      />
      <.item
        label="cooler"
        variant="transform"
        event="add_transformer"
        params={%{"effect" => "cooler"}}
      />
      <.item
        label="duplicator"
        variant="transform"
        event="add_transformer"
        params={%{"effect" => "duplicator"}}
      />
      <.item
        label="crusher"
        variant="transform"
        event="add_transformer"
        params={%{"effect" => "crusher"}}
      />

      <div class="q-section">World</div>
      <.item label="ramp" variant="passive" event="add_passive" params={%{"shape" => "ramp"}} />
      <.item label="wall" variant="passive" event="add_passive" params={%{"shape" => "wall"}} />
      <.item label="funnel" variant="passive" event="add_passive" params={%{"shape" => "funnel"}} />
      <.item
        label="conveyor →"
        variant="passive"
        event="add_passive"
        params={%{"shape" => "conveyor", "speed" => "80"}}
      />
      <.item
        label="conveyor ←"
        variant="passive"
        event="add_passive"
        params={%{"shape" => "conveyor", "speed" => "-80"}}
      />
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :variant, :string, required: true
  attr :event, :string, required: true
  attr :params, :map, required: true

  defp item(assigns) do
    # Body button: preview the type in the config panel (kind from event - "add_")
    kind = String.replace_prefix(assigns.event, "add_", "")

    body_attrs =
      assigns.params
      |> Map.new(fn {k, v} -> {"phx-value-" <> k, v} end)
      |> Map.put("phx-value-kind", kind)

    add_attrs = Map.new(assigns.params, fn {k, v} -> {"phx-value-" <> k, v} end)

    assigns =
      assigns
      |> assign(:body_attrs, body_attrs)
      |> assign(:add_attrs, add_attrs)

    ~H"""
    <div class={"q-row q-row--" <> @variant}>
      <button class="q-row-body" phx-click="preview_template" {@body_attrs}>{@label}</button>
      <button class="q-row-add" phx-click={@event} {@add_attrs} title="add">+</button>
    </div>
    """
  end
end
