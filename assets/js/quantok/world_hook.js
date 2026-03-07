/**
 * Phoenix LiveView hook that integrates Three.js rendering with Rapier2D physics.
 * This is the main entry point for the client-side world simulation.
 */

import { initRapier, PhysicsWorld } from "./physics";
import { WorldRenderer } from "./renderer";
import { OFFSCREEN_THRESHOLD } from "./utils";

const WorldCanvas = {
  async mounted() {
    this.tokeneData = new Map();
    this.nodeData = new Map();
    this.sensorCooldown = new Map();
    this._pendingShatter = new Set();
    this._pendingTimeouts = [];
    this._ready = false;
    this._eventQueue = [];

    // Register event handlers BEFORE async init so mount-time push_events are captured
    this.handleEvent("emit_tokenes", (data) => this._dispatch("emit_tokenes", data));
    this.handleEvent("absorb_tokene", (data) => this._dispatch("absorb_tokene", data));
    this.handleEvent("transform_tokene", (data) => this._dispatch("transform_tokene", data));
    this.handleEvent("add_node", (data) => this._dispatch("add_node", data));
    this.handleEvent("remove_node", (data) => this._dispatch("remove_node", data));
    this.handleEvent("set_gravity", (data) => this._dispatch("set_gravity", data));
    this.handleEvent("clear_tokenes", (data) => this._dispatch("clear_tokenes", data));
    this.handleEvent("clear_nodes", (data) => this._dispatch("clear_nodes", data));
    this.handleEvent("update_collector", (data) => this._dispatch("update_collector", data));
    this.handleEvent("shatter_tokene", (data) => this._dispatch("shatter_tokene", data));

    // Async init
    this.rapier = await initRapier();
    this.physics = new PhysicsWorld(this.rapier);
    this.worldRenderer = new WorldRenderer(this.el);
    this.running = true;

    // Drag state
    this._drag = null; // { nodeId, offsetX, offsetY }
    this._hoverNode = null;

    // Create hover menu overlay
    this._menu = document.createElement("div");
    this._menu.className = "q-node-menu";
    this._menu.style.display = "none";
    this.el.parentElement.appendChild(this._menu);

    // Mouse events (store refs for cleanup)
    this._onMouseDownBound = (e) => this._onMouseDown(e);
    this._onMouseMoveBound = (e) => this._onMouseMove(e);
    this._onMouseUpBound = () => this._onMouseUp();
    this._onMouseLeaveBound = () => { this._onMouseUp(); this._hideMenu(); };
    this.el.addEventListener("mousedown", this._onMouseDownBound);
    this.el.addEventListener("mousemove", this._onMouseMoveBound);
    this.el.addEventListener("mouseup", this._onMouseUpBound);
    this.el.addEventListener("mouseleave", this._onMouseLeaveBound);

    // Replay any events that arrived during init
    this._ready = true;
    for (const [type, data] of this._eventQueue) {
      this._handle(type, data);
    }
    this._eventQueue = [];

    // Start animation loop
    this.animate();
  },

  _dispatch(type, data) {
    if (this._ready) {
      this._handle(type, data);
    } else {
      this._eventQueue.push([type, data]);
    }
  },

  _handle(type, data) {
    switch (type) {
      case "emit_tokenes":     this.onEmitTokenes(data); break;
      case "absorb_tokene":    this.onAbsorbTokene(data); break;
      case "transform_tokene": this.onTransformTokene(data); break;
      case "add_node":         this.onAddNode(data); break;
      case "remove_node":      this.onRemoveNode(data); break;
      case "set_gravity":      this.onSetGravity(data); break;
      case "clear_tokenes":    this.onClearTokenes(); break;
      case "clear_nodes":      this.onClearNodes(); break;
      case "update_collector": this.onUpdateCollector(data); break;
      case "shatter_tokene":  this.onShatterTokene(data); break;
    }
  },

  destroyed() {
    this.running = false;
    if (this._rafId) cancelAnimationFrame(this._rafId);
    for (const t of this._pendingTimeouts) clearTimeout(t);
    this._pendingTimeouts = [];
    this.el.removeEventListener("mousedown", this._onMouseDownBound);
    this.el.removeEventListener("mousemove", this._onMouseMoveBound);
    this.el.removeEventListener("mouseup", this._onMouseUpBound);
    this.el.removeEventListener("mouseleave", this._onMouseLeaveBound);
    if (this._menu && this._menu.parentElement) this._menu.remove();
    this.worldRenderer.dispose();
  },

  // --- Node interaction ---

  _onMouseDown(e) {
    // Shift+click or middle-click = pan
    if (e.shiftKey || e.button === 1) {
      this.worldRenderer.startPan(e.clientX, e.clientY);
      this._hideMenu();
      return;
    }

    const id = this.worldRenderer.hitTestNode(e.clientX, e.clientY);
    if (!id) { this._hideMenu(); return; }
    const group = this.worldRenderer.nodeMeshes.get(id);
    if (!group) return;
    const world = this.worldRenderer.screenToWorld(e.clientX, e.clientY);
    this._drag = {
      nodeId: id,
      offsetX: world.x - group.position.x,
      offsetY: world.y - group.position.y,
    };
    this._hideMenu();
  },

  _onMouseMove(e) {
    // Camera pan
    if (this.worldRenderer._isPanning) {
      this.worldRenderer.updatePan(e.clientX, e.clientY);
      return;
    }

    if (this._drag) {
      const world = this.worldRenderer.screenToWorld(e.clientX, e.clientY);
      const nx = world.x - this._drag.offsetX;
      const ny = world.y - this._drag.offsetY;
      this.worldRenderer.moveNode(this._drag.nodeId, nx, ny);
      this.physics.moveKinematic(this._drag.nodeId, nx, -ny);
      return;
    }
    // Hover detection
    const id = this.worldRenderer.hitTestNode(e.clientX, e.clientY);
    if (id && id !== this._hoverNode) {
      this._hoverNode = id;
      this._showMenu(id, e.clientX, e.clientY);
    } else if (!id && this._hoverNode) {
      const rect = this._menu.getBoundingClientRect();
      if (e.clientX < rect.left || e.clientX > rect.right ||
          e.clientY < rect.top || e.clientY > rect.bottom) {
        this._hideMenu();
      }
    }
  },

  _onMouseUp() {
    // End pan
    if (this.worldRenderer._isPanning) {
      this.worldRenderer.endPan();
      return;
    }

    if (this._drag) {
      const id = this._drag.nodeId;
      const group = this.worldRenderer.nodeMeshes.get(id);
      if (group) {
        this.pushEvent("move_node", {
          node_id: id,
          x: group.position.x,
          y: -group.position.y,
        });
      }
      this._drag = null;
    }
  },

  _showMenu(nodeId, mx, my) {
    const info = this.nodeData.get(nodeId);
    if (!info) return;

    const actions = [];
    if (info.type === "emitter") {
      actions.push({ label: "fire", event: "fire_emitter", data: { node_id: nodeId } });
    }
    if (info.type === "collector") {
      actions.push({ label: "trigger", event: "trigger_collector", data: { node_id: nodeId } });
      actions.push({ label: "clear", event: "clear_collector", data: { node_id: nodeId } });
    }
    if (info.type === "passive") {
      actions.push({ label: "rotate", event: "rotate_passive", data: { node_id: nodeId } });
    }
    actions.push({ label: "×", event: "remove_node", data: { node_id: nodeId } });

    this._menu.textContent = "";
    for (const a of actions) {
      const btn = document.createElement("button");
      btn.textContent = a.label;
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        this.pushEvent(a.event, a.data);
        this._hideMenu();
      });
      this._menu.appendChild(btn);
    }

    // Position above node
    const group = this.worldRenderer.nodeMeshes.get(nodeId);
    if (group) {
      const body = group.children[0];
      const h = body?.geometry?.parameters?.height || 40;
      const screen = this.worldRenderer.worldToScreen(group.position.x, group.position.y + h / 2 + 8);
      const parentRect = this.el.parentElement.getBoundingClientRect();
      this._menu.style.left = `${screen.x - parentRect.left}px`;
      this._menu.style.top = `${screen.y - parentRect.top}px`;
    }

    this._menu.style.display = "flex";
  },

  _hideMenu() {
    this._menu.style.display = "none";
    this._hoverNode = null;
  },

  onEmitTokenes({ emitter_id, tokenes }) {
    const nodeGroup = this.worldRenderer.nodeMeshes.get(emitter_id);
    const baseX = nodeGroup ? nodeGroup.position.x : 0;
    // Pipe outlet: just below the emitter body (negate Y from Three.js back to Rapier)
    const bodyH = nodeGroup?.children[0]?.geometry?.parameters?.height || 40;
    const pipeLen = 20;
    const baseY = nodeGroup ? -nodeGroup.position.y + bodyH / 2 + pipeLen + 5 : -200;

    tokenes.forEach((t, i) => {
      const timer = setTimeout(() => {
        if (!this.running) return;
        const hw = t.width / 2;
        const hh = t.height / 2;
        // All tokenes drop from the same pipe outlet point
        this.physics.spawnTokene(t.id, baseX, baseY, hw, hh, t.mass);
        this.worldRenderer.createTokeneMesh(t.id, t.value, t.encoding, t.width, t.height);
        this.tokeneData.set(t.id, { ...t, _spawnedAt: performance.now() });
      }, i * (t.emit_rate || 100));
      this._pendingTimeouts.push(timer);
    });
  },

  onAbsorbTokene({ collector_id, tokene_id, buffer }) {
    this.physics.remove(tokene_id);
    this.worldRenderer.removeTokene(tokene_id);
    this.tokeneData.delete(tokene_id);
    if (buffer) {
      this.worldRenderer.updateCollectorBuffer(collector_id, buffer);
    }
  },

  onUpdateCollector({ collector_id, buffer }) {
    this.worldRenderer.updateCollectorBuffer(collector_id, buffer || []);
  },

  onShatterTokene({ tokene_id, behavior, fragments }) {
    this._pendingShatter.delete(tokene_id);
    const oldMesh = this.worldRenderer.meshes.get(tokene_id);
    const oldPos = oldMesh
      ? { x: oldMesh.position.x, y: -oldMesh.position.y }
      : { x: 0, y: 0 };

    // Remove the shattered tokene
    this.physics.remove(tokene_id);
    this.worldRenderer.removeTokene(tokene_id);
    this.tokeneData.delete(tokene_id);

    if (behavior === "dissolve" || !fragments || fragments.length === 0) {
      return;
    }

    // Spawn fragment tokenes at old position with spread
    fragments.forEach((t, i) => {
      const hw = t.width / 2;
      const hh = t.height / 2;
      const spread = behavior === "explode" ? 20 : 10;
      const xOff = (i - (fragments.length - 1) / 2) * spread;
      this.physics.spawnTokene(t.id, oldPos.x + xOff, oldPos.y, hw, hh, t.mass);
      this.worldRenderer.createTokeneMesh(t.id, t.value, t.encoding, t.width, t.height);
      this.tokeneData.set(t.id, { ...t, _spawnedAt: performance.now() });

      // Explode: apply random impulse
      if (behavior === "explode") {
        const body = this.physics.getBody(t.id);
        if (body) {
          const angle = (Math.random() - 0.5) * Math.PI;
          const force = 50 + Math.random() * 100;
          body.applyImpulse({ x: Math.cos(angle) * force, y: Math.sin(angle) * force }, true);
        }
      }

      // Fossilize: make static (grey, no decay)
      if (behavior === "fossilize") {
        const body = this.physics.getBody(t.id);
        if (body) body.setBodyType(this.rapier.RigidBodyType.Fixed);
      }
    });
  },

  onTransformTokene({ old_tokene_id, new_tokenes }) {
    // Remove old
    this.physics.remove(old_tokene_id);
    const oldMesh = this.worldRenderer.meshes.get(old_tokene_id);
    // Negate Y back from Three.js Y-up to Rapier Y-down
    const oldPos = oldMesh ? { x: oldMesh.position.x, y: -oldMesh.position.y } : { x: 0, y: 0 };
    this.worldRenderer.removeTokene(old_tokene_id);
    this.tokeneData.delete(old_tokene_id);

    // Spawn new at old position with slight spread
    new_tokenes.forEach((t, i) => {
      const hw = t.width / 2;
      const hh = t.height / 2;
      const xOff = (i - (new_tokenes.length - 1) / 2) * 10;
      this.physics.spawnTokene(t.id, oldPos.x + xOff, oldPos.y, hw, hh, t.mass);
      this.worldRenderer.createTokeneMesh(t.id, t.value, t.encoding, t.width, t.height);
      this.tokeneData.set(t.id, { ...t, _spawnedAt: performance.now() });
    });
  },

  onAddNode({ node }) {
    const [x, y] = [node.position_x || 0, node.position_y || 0];
    const w = node.width || 80;
    const h = node.height || 40;

    // Three.js uses Y-up; negate Y for rendering
    this.worldRenderer.createNodeMesh(
      node.id, node.type, node.label, x, -y, w, h, node.config || {}
    );

    // Create physics body based on type
    if (node.type === "passive") {
      this.physics.spawnStatic(node.id, x, y, w / 2, h / 2,
        node.config?.angle || 0,
        node.config?.friction || 0.5,
        node.config?.restitution || 0.3
      );
    } else if (node.type === "collector") {
      // Kinematic body + sensor zone
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2);
      const sensorRadius = node.config?.sensor_radius || 60;
      this.physics.spawnSensor(node.id, x, y, sensorRadius);
    } else if (node.type === "transformer") {
      // Transformer: kinematic body + sensor zone for effect radius
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2);
      const effectRadius = parseFloat(node.config?.radius) || 60;
      this.physics.spawnSensor(node.id, x, y, effectRadius);
    } else {
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2);
    }

    this.nodeData.set(node.id, node);
  },

  onRemoveNode({ node_id }) {
    this.physics.remove(node_id);
    this.worldRenderer.removeNode(node_id);
    this.nodeData.delete(node_id);
    this.sensorCooldown.delete(node_id);
  },

  onSetGravity({ x, y }) {
    this.physics.setGravity(x, y);
  },

  onClearTokenes() {
    for (const id of this.tokeneData.keys()) {
      this.physics.remove(id);
      this.worldRenderer.removeTokene(id);
    }
    this.tokeneData.clear();
  },

  onClearNodes() {
    for (const [id] of this.nodeData) {
      this.physics.remove(id);
      this.worldRenderer.removeNode(id);
    }
    this.nodeData.clear();
    this.sensorCooldown.clear();
  },

  animate() {
    if (!this.running) return;

    // Step physics
    this.physics.step();

    // Sync Three.js meshes with Rapier bodies
    const offscreen = [];
    for (const [id] of this.tokeneData) {
      const transform = this.physics.getTransform(id);
      if (transform) {
        this.worldRenderer.updateTokeneTransform(id, transform.x, -transform.y, -transform.rotation);

        if (Math.abs(transform.y) > OFFSCREEN_THRESHOLD || Math.abs(transform.x) > OFFSCREEN_THRESHOLD) {
          offscreen.push(id);
        }
      }
    }
    // Remove offscreen tokenes after iteration (avoid mutating Map during iteration)
    for (const id of offscreen) {
      this.physics.remove(id);
      this.worldRenderer.removeTokene(id);
      this.tokeneData.delete(id);
      this.pushEvent("tokene_offscreen", { tokene_id: id });
    }

    // Visual decay: compute integrity per-frame for decaying tokenes
    const now = performance.now();
    for (const [id, t] of this.tokeneData) {
      if (!t.decay || !t.decay.enabled || !t.decay.half_life) continue;
      const elapsed = now - (t._spawnedAt || now);
      const initialIntegrity = t.integrity || 0.5;
      const ratio = initialIntegrity * Math.pow(0.5, elapsed / t.decay.half_life);
      this.worldRenderer.updateTokeneDecay(id, ratio / initialIntegrity);
      if (ratio < 0.05 * initialIntegrity && !this._pendingShatter.has(id)) {
        this._pendingShatter.add(id);
        this.pushEvent("tokene_shattered", { tokene_id: id });
      }
    }

    // Check sensor intersections (collectors + transformers)
    this.checkSensorIntersections();

    // Render
    this.worldRenderer.render();

    this._rafId = requestAnimationFrame(() => this.animate());
  },

  checkSensorIntersections() {
    for (const [nodeId, nodeInfo] of this.nodeData) {
      if (nodeInfo.type !== "collector" && nodeInfo.type !== "transformer") continue;

      const intersecting = this.physics.getSensorIntersections(nodeId);
      for (const tokeneId of intersecting) {
        if (!this.tokeneData.has(tokeneId)) continue;

        // Cooldown to avoid spamming the server
        if (!this.sensorCooldown.has(nodeId)) {
          this.sensorCooldown.set(nodeId, new Set());
        }
        const cooldownSet = this.sensorCooldown.get(nodeId);
        if (cooldownSet.has(tokeneId)) continue;

        cooldownSet.add(tokeneId);
        const cooldownMs = nodeInfo.type === "transformer" ? 1000 : 500;
        const tid = setTimeout(() => cooldownSet.delete(tokeneId), cooldownMs);
        this._pendingTimeouts.push(tid);

        if (nodeInfo.type === "collector") {
          this.pushEvent("tokene_near_collector", {
            tokene_id: tokeneId,
            collector_id: nodeId,
          });
        } else {
          this.pushEvent("tokene_near_transformer", {
            tokene_id: tokeneId,
            transformer_id: nodeId,
          });
        }
      }
    }
  },
};

export default WorldCanvas;
