defmodule QuantokWeb.WorldConfig do
  @moduledoc """
  The right-side configuration panel. Shows when a node is selected or a
  template is being configured. Each field renders as buttons or an input
  that pushes `update_node_config` back to the parent LiveView.
  """

  use Phoenix.Component

  attr :selected_node, :any, default: nil
  attr :template_node, :any, default: nil

  def config_panel(assigns) do
    active = assigns.template_node || assigns.selected_node
    is_template = !is_nil(assigns.template_node)
    assigns = assigns |> assign(:active, active) |> assign(:is_template, is_template)

    ~H"""
    <div class="q-config">
      <div class="q-config-header">
        <button
          phx-click="commit_template"
          class={"q-config-add" <> if(@is_template, do: "", else: " q-config-add--off")}
          disabled={!@is_template}
          title="add to world"
        >
          +
        </button>
        <span class="q-config-title">{(@active && @active.label) || "config"}</span>
        <button
          phx-click="clear_config"
          class={"q-config-close" <> if(@active, do: "", else: " q-config-close--off")}
          disabled={!@active}
        >
          ×
        </button>
      </div>
      <.body :if={@active} node={@active} is_template={@is_template} />
      <div :if={!@active} class="q-config-empty">click a node, or pick a type from the menu</div>
    </div>
    """
  end

  attr :node, :any, required: true
  attr :is_template, :boolean, default: false

  defp body(%{node: %{type: :emitter, config: config}} = assigns) do
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="q-config-body">
      <div :if={!@is_template} class="q-cfg-actions">
        <button
          phx-click="fire_emitter"
          phx-value-node_id={@node.id}
          class="q-cfg-btn q-cfg-btn--action"
          title="emit one batch from this emitter"
        >
          fire
        </button>
      </div>

      <label class="q-cfg-label">command</label>
      <form phx-change="update_node_config" phx-submit="update_node_config">
        <input type="hidden" name="field" value="command" />
        <input type="text" name="val" value={@config.command} class="q-cfg-input" phx-debounce="500" />
      </form>

      <label class="q-cfg-label">chunker</label>
      <div class="q-cfg-btns">
        <button
          :for={c <- ~w(bit byte rune token word phrase sentence)}
          phx-click="update_node_config"
          phx-value-field="chunker"
          phx-value-val={c}
          class={"q-cfg-btn" <> if(module_label(@config.chunker) == c, do: " q-cfg-btn--active", else: "")}
        >
          {c}
        </button>
      </div>

      <label class="q-cfg-label">emit rate</label>
      <div class="q-cfg-btns">
        <button
          :for={r <- [50, 100, 250, 500]}
          phx-click="update_node_config"
          phx-value-field="emit_rate"
          phx-value-val={r}
          class={"q-cfg-btn" <> if(@config.emit_rate == r, do: " q-cfg-btn--active", else: "")}
        >
          {r}ms
        </button>
      </div>
    </div>
    """
  end

  defp body(%{node: %{type: :collector, config: config}} = assigns) do
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="q-config-body">
      <div :if={!@is_template} class="q-cfg-actions">
        <button
          phx-click="trigger_collector"
          phx-value-node_id={@node.id}
          class="q-cfg-btn q-cfg-btn--action"
          title="run action on current buffer and release"
        >
          flush
        </button>
      </div>

      <label class="q-cfg-label">capacity</label>
      <div class="q-cfg-btns">
        <button
          :for={c <- [2, 4, 8, 16]}
          phx-click="update_node_config"
          phx-value-field="capacity"
          phx-value-val={c}
          class={"q-cfg-btn" <> if(@config.capacity == c, do: " q-cfg-btn--active", else: "")}
        >
          {c}
        </button>
      </div>

      <label class="q-cfg-label">trigger</label>
      <div class="q-cfg-btns">
        <button
          :for={t <- ~w(on_full manual timed)}
          phx-click="update_node_config"
          phx-value-field="trigger_mode"
          phx-value-val={t}
          class={"q-cfg-btn" <> if(to_string(@config.trigger_mode) == t, do: " q-cfg-btn--active", else: "")}
        >
          {t}
        </button>
      </div>

      <label class="q-cfg-label">action</label>
      <div class="q-cfg-btns">
        <button
          :for={a <- ~w(echo reverse upcase count hash sum min max)}
          phx-click="update_node_config"
          phx-value-field="action"
          phx-value-val={a}
          class={"q-cfg-btn" <> if(module_label(@config.action) == a, do: " q-cfg-btn--active", else: "")}
        >
          {a}
        </button>
      </div>

      <label class="q-cfg-label">emit</label>
      <div class="q-cfg-btns">
        <button
          phx-click="update_node_config"
          phx-value-field="emit"
          phx-value-val="true"
          class={"q-cfg-btn" <> if(@config.emit, do: " q-cfg-btn--active", else: "")}
        >
          on
        </button>
        <button
          phx-click="update_node_config"
          phx-value-field="emit"
          phx-value-val="false"
          class={"q-cfg-btn" <> if(!@config.emit, do: " q-cfg-btn--active", else: "")}
        >
          off
        </button>
      </div>

      <div :if={@config.emit}>
        <label class="q-cfg-label">output chunker</label>
        <div class="q-cfg-btns">
          <button
            :for={c <- ~w(byte rune token word phrase sentence)}
            phx-click="update_node_config"
            phx-value-field="output_chunker"
            phx-value-val={c}
            class={"q-cfg-btn" <> if(module_label(@config.output_chunker) == c, do: " q-cfg-btn--active", else: "")}
          >
            {c}
          </button>
        </div>

        <label class="q-cfg-label">emit rate</label>
        <div class="q-cfg-btns">
          <button
            :for={r <- [50, 100, 250, 500]}
            phx-click="update_node_config"
            phx-value-field="emit_rate"
            phx-value-val={r}
            class={"q-cfg-btn" <> if(@config.emit_rate == r, do: " q-cfg-btn--active", else: "")}
          >
            {r}ms
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp body(%{node: %{type: :transformer, config: config}} = assigns) do
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="q-config-body">
      <label class="q-cfg-label">effect</label>
      <div class="q-cfg-btns">
        <button
          :for={e <- ~w(splitter heater cooler duplicator crusher tiktoken)}
          phx-click="update_node_config"
          phx-value-field="effect"
          phx-value-val={e}
          class={"q-cfg-btn" <> if(to_string(@config.effect) == e, do: " q-cfg-btn--active", else: "")}
        >
          {e}
        </button>
      </div>

      <label class="q-cfg-label">radius</label>
      <div class="q-cfg-btns">
        <button
          :for={r <- [30, 60, 90, 120]}
          phx-click="update_node_config"
          phx-value-field="radius"
          phx-value-val={r}
          class={"q-cfg-btn" <> if(round(@config.radius) == r, do: " q-cfg-btn--active", else: "")}
        >
          {r}
        </button>
      </div>
    </div>
    """
  end

  defp body(%{node: %{type: :passive, config: config}} = assigns) do
    assigns = assign(assigns, :config, config)

    ~H"""
    <div class="q-config-body">
      <label class="q-cfg-label">shape</label>
      <div class="q-cfg-btns">
        <button
          :for={s <- ~w(floor wall ramp funnel conveyor portal)}
          phx-click="update_node_config"
          phx-value-field="shape"
          phx-value-val={s}
          class={"q-cfg-btn" <> if(to_string(@config.shape) == s, do: " q-cfg-btn--active", else: "")}
        >
          {s}
        </button>
      </div>

      <label class="q-cfg-label">width</label>
      <div class="q-cfg-btns">
        <button
          :for={w <- [100, 200, 400, 800]}
          phx-click="update_node_config"
          phx-value-field="width"
          phx-value-val={w}
          class={"q-cfg-btn" <> if(round(@config.width) == w, do: " q-cfg-btn--active", else: "")}
        >
          {w}
        </button>
      </div>

      <div :if={@config.shape == :conveyor}>
        <label class="q-cfg-label">speed</label>
        <div class="q-cfg-btns">
          <button
            :for={s <- [-160, -80, -40, 40, 80, 160]}
            phx-click="update_node_config"
            phx-value-field="speed"
            phx-value-val={s}
            class={"q-cfg-btn" <> if(round(@config.speed) == s, do: " q-cfg-btn--active", else: "")}
          >
            {s}
          </button>
        </div>
      </div>

      <div :if={@config.shape == :portal}>
        <label class="q-cfg-label">channel</label>
        <div class="q-cfg-btns">
          <button
            :for={c <- ~w(A B C D)}
            phx-click="update_node_config"
            phx-value-field="channel"
            phx-value-val={c}
            class={"q-cfg-btn" <> if(to_string(@config.channel) == c, do: " q-cfg-btn--active", else: "")}
          >
            {c}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp body(assigns), do: ~H""

  defp module_label(nil), do: ""
  # BPE is exposed as "token" in the UI; canonical encoding name is :token.
  defp module_label(Quantok.Chunker.BPE), do: "token"

  defp module_label(mod) when is_atom(mod) do
    mod |> to_string() |> String.split(".") |> List.last() |> String.downcase()
  end
end
