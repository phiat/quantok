/**
 * Phoenix LiveView hook that integrates Three.js rendering with Rapier2D physics.
 * This is the main entry point for the client-side world simulation.
 */

import { initRapier, PhysicsWorld } from "./physics";
import { WorldRenderer } from "./renderer";
import {
  TOKENE_CAP, HIGHLIGHT_MS, OFFSCREEN_THRESHOLD, FPS_INTERVAL_MS,
  SHATTER_THRESHOLD, SENSOR_COOLDOWN_MS, MAGNET_DT,
  CONVEYOR_COUPLING, CONVEYOR_CONTACT_BAND, PORTAL_EXIT_CLEARANCE,
  BASE_HALF_LIFE,
} from "./config";

// LiveView events the server pushes to this hook. Listed once so adding a new
// event is one line, and so the dispatch dance (queue events that arrive
// before async init completes, then drain) covers everything by construction.
const SERVER_EVENTS = [
  "emit_tokenes", "absorb_tokene", "transform_tokene",
  "add_node", "remove_node", "update_node_config",
  "set_gravity", "set_decay",
  "clear_tokenes", "clear_nodes",
  "update_collector", "shatter_tokene",
];

const WorldCanvas = {
  async mounted() {
    this._initState();
    this._registerServerEvents();

    // Async init — the event handlers above queue anything that arrives while
    // we're waiting on WASM, so the early "add_node" pushes for default-world
    // nodes don't get dropped.
    this.rapier = await initRapier();
    this.physics = new PhysicsWorld(this.rapier);
    this.worldRenderer = new WorldRenderer(this.el);
    this.running = true;

    this._setupMouseHandlers();

    // Drain anything that arrived during init
    this._ready = true;
    for (const [type, data] of this._eventQueue) this._handle(type, data);
    this._eventQueue = [];

    this.animate();
  },

  _initState() {
    this.tokeneData = new Map();
    this.nodeData = new Map();
    this.conveyors = new Map(); // id -> { x, y, hw, hh, angle, speed }
    this.magnets = new Map();   // id -> { x, y, r, r2, strength, sign, regex, encoding }
    this.sensorCooldown = new Map();
    // Runtime decay state — overrides per-tokene decay.enabled so toggling
    // affects existing tokenes, not just newly emitted ones.
    this.decayEnabled = false;
    this.decayRate = 1.0;
    this._pendingShatter = new Set();
    this._pendingTimeouts = [];
    this._ready = false;
    this._eventQueue = [];
    this.maxTokenes = TOKENE_CAP;
    this._fpsFrames = 0;
    this._fpsLast = performance.now();
    // Drag state — populated lazily on first mousedown.
    this._drag = null; // { nodeId, offsetX, offsetY, startX, startY }
    this._hoverNode = null;
  },

  _registerServerEvents() {
    for (const type of SERVER_EVENTS) {
      this.handleEvent(type, (data) => this._dispatch(type, data));
    }
  },

  _setupMouseHandlers() {
    // Hover menu overlay (created lazily on first mounted setup).
    this._menu = document.createElement("div");
    this._menu.className = "q-node-menu";
    this._menu.style.display = "none";
    this.el.parentElement.appendChild(this._menu);

    this._onMouseDownBound = (e) => this._onMouseDown(e);
    this._onMouseMoveBound = (e) => this._onMouseMove(e);
    this._onMouseUpBound = () => this._onMouseUp();
    this._onMouseLeaveBound = (e) => {
      // Don't hide menu if the cursor moved into the menu overlay.
      if (this._menu.contains(e.relatedTarget)) return;
      this._onMouseUp();
      this._hideMenu();
    };
    this._onMenuLeaveBound = (e) => {
      // Keep the menu while moving from menu back into the canvas.
      if (e.relatedTarget === this.el) return;
      this._hideMenu();
    };

    this.el.addEventListener("mousedown", this._onMouseDownBound);
    this.el.addEventListener("mousemove", this._onMouseMoveBound);
    this.el.addEventListener("mouseup", this._onMouseUpBound);
    this.el.addEventListener("mouseleave", this._onMouseLeaveBound);
    this._menu.addEventListener("mouseleave", this._onMenuLeaveBound);
  },

  _dispatch(type, data) {
    if (this._ready) {
      this._handle(type, data);
    } else {
      this._eventQueue.push([type, data]);
    }
  },

  _handle(type, data) {
    // Snake-case "emit_tokenes" -> camelCase "onEmitTokenes". Listed in
    // SERVER_EVENTS; the corresponding `on…` method must exist on this object.
    const method = "on" + type.replace(/(^|_)(.)/g, (_m, _u, c) => c.toUpperCase());
    const fn = this[method];
    if (typeof fn === "function") fn.call(this, data);
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
    if (this._menu) {
      this._menu.removeEventListener("mouseleave", this._onMenuLeaveBound);
      if (this._menu.parentElement) this._menu.remove();
    }
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
    if (!id) {
      this._hideMenu();
      this.pushEvent("deselect_node", {});
      return;
    }
    const group = this.worldRenderer.nodeMeshes.get(id);
    if (!group) return;
    const world = this.worldRenderer.screenToWorld(e.clientX, e.clientY);
    this._drag = {
      nodeId: id,
      offsetX: world.x - group.position.x,
      offsetY: world.y - group.position.y,
      startX: e.clientX,
      startY: e.clientY,
    };
    this._dragMoved = false;
    this._hideMenu();
  },

  _onMouseMove(e) {
    // Camera pan
    if (this.worldRenderer._isPanning) {
      this.worldRenderer.updatePan(e.clientX, e.clientY);
      return;
    }

    if (this._drag) {
      // Only treat as drag once cursor moves past a small threshold —
      // otherwise a normal click registers as a drag and never selects.
      const DRAG_THRESHOLD_PX = 4;
      const dx = e.clientX - this._drag.startX;
      const dy = e.clientY - this._drag.startY;
      if (!this._dragMoved && dx * dx + dy * dy < DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX) {
        return;
      }
      this._dragMoved = true;
      const world = this.worldRenderer.screenToWorld(e.clientX, e.clientY);
      const nx = world.x - this._drag.offsetX;
      const ny = world.y - this._drag.offsetY;
      this.worldRenderer.moveNode(this._drag.nodeId, nx, ny);
      // Use moveBody so passives (static) move too, not just kinematic nodes
      this.physics.moveBody(this._drag.nodeId, nx, -ny);
      // Per-feature caches that hold a node's physics-space position need to
      // be kept in sync, otherwise force fields keep pointing at the old spot
      // and a config-rebuild teleports the node back to where it was first
      // installed.
      const conv = this.conveyors.get(this._drag.nodeId);
      if (conv) { conv.x = nx; conv.y = -ny; }
      const mag = this.magnets.get(this._drag.nodeId);
      if (mag) { mag.x = nx; mag.y = -ny; }
      const nd = this.nodeData.get(this._drag.nodeId);
      if (nd) { nd.position_x = nx; nd.position_y = -ny; }
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
      if (this._dragMoved) {
        const group = this.worldRenderer.nodeMeshes.get(id);
        if (group) {
          this.pushEvent("move_node", {
            node_id: id,
            x: group.position.x,
            y: -group.position.y,
          });
        }
      } else {
        // Click without drag = select node
        this.pushEvent("select_node", { node_id: id });
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
      const body = group.children.find(c => c.userData?.isBody);
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
    // Pipe outlet: just below the node body (negate Y from Three.js back to Rapier)
    const bodyH = nodeGroup?.children?.find(c => c.userData?.isBody)?.geometry?.parameters?.height || 40;
    const nodeInfo = this.nodeData.get(emitter_id);
    const pipeLen = nodeInfo?.type === "collector" ? 14 : 20;
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
        this._enforceTokeneCap();
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
    this._enforceTokeneCap();
  },

  onTransformTokene({ transformer_id, old_tokene_id, new_tokenes }) {
    // Remove old
    this.physics.remove(old_tokene_id);
    const oldMesh = this.worldRenderer.meshes.get(old_tokene_id);
    // Negate Y back from Three.js Y-up to Rapier Y-down
    const oldPos = oldMesh ? { x: oldMesh.position.x, y: -oldMesh.position.y } : { x: 0, y: 0 };
    this.worldRenderer.removeTokene(old_tokene_id);
    this.tokeneData.delete(old_tokene_id);

    // The new tokenes spawn inside the transformer's sensor zone. Without
    // a cooldown they'd immediately re-fire the transformer (and each cycle
    // multiplies the population — runaway with duplicator/tiktoken). Seed the
    // transformer's cooldown set with the new ids and let it expire naturally.
    let cooldownSet = null;
    if (transformer_id) {
      if (!this.sensorCooldown.has(transformer_id)) {
        this.sensorCooldown.set(transformer_id, new Set());
      }
      cooldownSet = this.sensorCooldown.get(transformer_id);
    }

    // Spawn new at old position with slight spread
    new_tokenes.forEach((t, i) => {
      const hw = t.width / 2;
      const hh = t.height / 2;
      const xOff = (i - (new_tokenes.length - 1) / 2) * 10;
      this.physics.spawnTokene(t.id, oldPos.x + xOff, oldPos.y, hw, hh, t.mass);
      this.worldRenderer.createTokeneMesh(t.id, t.value, t.encoding, t.width, t.height);
      this.tokeneData.set(t.id, { ...t, _spawnedAt: performance.now() });

      if (cooldownSet) {
        cooldownSet.add(t.id);
        // Use the same window as a tokene entering a transformer for the first
        // time — the new tokenes spawned inside the zone need to drift out
        // before being eligible again.
        const tid = setTimeout(() => cooldownSet.delete(t.id), SENSOR_COOLDOWN_MS.transformer);
        this._pendingTimeouts.push(tid);
      }
    });
  },

  onAddNode({ node }) {
    this._installNode(node);
    // Flash a fading halo so the user can see where the new node landed
    this.worldRenderer.highlightNode(node.id, HIGHLIGHT_MS);
  },

  // Build the physics body, sensor (if any), and mesh for a node from its
  // current config. Used by add_node and (after a tear-down) by config updates
  // that change geometry — e.g., a transformer's radius driving both its
  // visual size and its sensor zone.
  _installNode(node) {
    const [x, y] = [node.position_x || 0, node.position_y || 0];
    const w = node.width || 80;
    const h = node.height || 40;

    this.worldRenderer.createNodeMesh(
      node.id, node.type, node.label, x, -y, w, h, node.config || {}
    );

    if (node.type === "passive") {
      if (node.config?.shape === "portal") {
        this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2, { passthrough: true });
        const r = parseFloat(node.config?.radius) || 30;
        this.physics.spawnSensor(node.id, x, y, r);
      } else {
        this.physics.spawnStatic(node.id, x, y, w / 2, h / 2,
          node.config?.angle || 0,
          node.config?.friction || 0.5,
          node.config?.restitution || 0.3
        );
      }
      if (node.config?.shape === "conveyor") {
        this.conveyors.set(node.id, {
          x, y,
          hw: w / 2,
          hh: h / 2,
          angle: parseFloat(node.config?.angle) || 0,
          speed: parseFloat(node.config?.speed) || 0,
        });
      }
    } else if (node.type === "collector") {
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2);
      const sensorRadius = node.config?.sensor_radius || 60;
      this.physics.spawnSensor(node.id, x, y, sensorRadius);
    } else if (node.type === "transformer") {
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2, { passthrough: true });
      const effectRadius = parseFloat(node.config?.radius) || 60;
      this.physics.spawnSensor(node.id, x, y, effectRadius);
      if (node.config?.effect === "magnet") {
        this._registerMagnet(node);
      }
    } else {
      this.physics.spawnKinematic(node.id, x, y, w / 2, h / 2);
    }

    this.nodeData.set(node.id, node);
  },

  onRemoveNode({ node_id }) {
    this._tearDownNode(node_id);
    this.nodeData.delete(node_id);
  },

  // Like onRemoveNode but keeps nodeData — used by reinstall paths so the
  // caller can swap in a new config without losing the entry.
  _tearDownNode(node_id) {
    this.physics.remove(node_id);
    this.worldRenderer.removeNode(node_id);
    this.conveyors.delete(node_id);
    this.magnets.delete(node_id);
    this.sensorCooldown.delete(node_id);
  },

  onUpdateNodeConfig({ node_id, width, height, config, buffer }) {
    const node = this.nodeData.get(node_id);
    if (!node) return;
    const merged = { ...node, config: { ...(node.config || {}), ...(config || {}) } };
    if (typeof width === "number") merged.width = width;
    if (typeof height === "number") merged.height = height;

    // Transformers, passives, and collectors have geometry baked into their
    // physics body, collider, mesh, and (where applicable) sensor zone. Any
    // field that changes shape/size has to rebuild all of those. Cheapest
    // correct path: full tear-down + reinstall under the same id.
    if (merged.type === "transformer" || merged.type === "passive" || merged.type === "collector") {
      this._tearDownNode(node_id);
      this._installNode(merged);
      // Buffer paint is held client-side and is wiped by the mesh rebuild.
      // The server includes the current buffer so we can repaint on the spot.
      if (merged.type === "collector" && Array.isArray(buffer)) {
        this.worldRenderer.updateCollectorBuffer(node_id, buffer);
      }
      return;
    }

    this.nodeData.set(node_id, merged);
  },

  _registerMagnet(node) {
    const r = parseFloat(node.config?.radius) || 100;
    const polarity = node.config?.polarity || "attract";
    const pattern = node.config?.pattern;
    let regex = null;
    if (pattern && pattern !== "") {
      try { regex = new RegExp(pattern); } catch (_) { regex = null; }
    }
    this.magnets.set(node.id, {
      x: node.position_x || 0,
      y: node.position_y || 0,
      r,
      r2: r * r,
      strength: parseFloat(node.config?.strength) || 250,
      // attract pulls toward center (force opposite of dx,dy) -> sign -1
      // repel pushes away from center -> sign +1
      sign: polarity === "repel" ? 1 : -1,
      regex,
      encoding: node.config?.target_encoding || null,
    });
  },

  onSetGravity({ x, y }) {
    this.physics.setGravity(x, y);
  },

  onSetDecay({ enabled, rate }) {
    this.decayEnabled = !!enabled;
    if (typeof rate === "number") this.decayRate = rate;
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
    this.conveyors.clear();
    this.magnets.clear();
    this.sensorCooldown.clear();
  },

  animate() {
    if (!this.running) return;

    // Step physics
    this.physics.step();

    const now = performance.now();
    const decayOn = this.decayEnabled;
    if (decayOn && this._decayAnchor == null) this._decayAnchor = now;
    const decayRate = this.decayRate || 1;
    const decayAnchor = this._decayAnchor;

    // Pre-compute per-conveyor trig so the inner loop is cheap.
    const conveyorCount = this.conveyors.size;
    let convList = null;
    if (conveyorCount > 0) {
      convList = [];
      for (const conv of this.conveyors.values()) {
        const cos = Math.cos(conv.angle);
        const sin = Math.sin(conv.angle);
        convList.push({ conv, cos, sin });
      }
    }

    // Snapshot magnets to a plain array so the inner loop avoids Map iteration.
    const magList = this.magnets.size > 0 ? Array.from(this.magnets.values()) : null;

    // Single pass over tokeneData: transform sync + offscreen check + decay +
    // conveyor force. Previously each was its own iteration, paying for the
    // WASM crossing to fetch transforms multiple times per tokene per frame.
    const offscreen = [];
    for (const [id, t] of this.tokeneData) {
      const transform = this.physics.getTransform(id);
      if (!transform) continue;

      // 1) Render sync
      this.worldRenderer.updateTokeneTransform(id, transform.x, -transform.y, -transform.rotation);

      // 2) Offscreen culling
      if (Math.abs(transform.y) > OFFSCREEN_THRESHOLD || Math.abs(transform.x) > OFFSCREEN_THRESHOLD) {
        offscreen.push(id);
        continue;
      }

      // 3) Decay
      if (decayOn) {
        const halfLife = BASE_HALF_LIFE[t.encoding];
        if (halfLife) {
          const startedAt = Math.max(t._spawnedAt || now, decayAnchor);
          const elapsed = (now - startedAt) * decayRate;
          const initialIntegrity = t.integrity || 0.5;
          const ratio = initialIntegrity * Math.pow(0.5, elapsed / halfLife);
          this.worldRenderer.updateTokeneDecay(id, ratio / initialIntegrity);
          if (ratio < SHATTER_THRESHOLD * initialIntegrity && !this._pendingShatter.has(id)) {
            this._pendingShatter.add(id);
            this.pushEvent("tokene_shattered", { tokene_id: id });
          }
        }
      } else if (this._lastDecayState) {
        // One-shot reset when decay was just turned off
        this.worldRenderer.updateTokeneDecay(id, 1.0);
      }

      // 4) Conveyor surface drag
      if (convList) {
        this._applyConveyorForceToTokene(id, t, transform, convList);
      }

      // 5) Magnet radial force (regex + encoding filter, attract or repel)
      if (magList) {
        this._applyMagnetForceToTokene(id, t, transform, magList);
      }
    }
    if (!decayOn) this._decayAnchor = null;
    this._lastDecayState = decayOn;

    // Remove offscreen tokenes after iteration (avoid mutating Map during iteration)
    for (const id of offscreen) {
      this.physics.remove(id);
      this.worldRenderer.removeTokene(id);
      this.tokeneData.delete(id);
      this.pushEvent("tokene_offscreen", { tokene_id: id });
    }

    // Check sensor intersections (collectors + transformers)
    this.checkSensorIntersections();

    // Fade any active add-highlights
    this.worldRenderer.updateHighlights(now);

    // Render
    this.worldRenderer.render();

    // FPS readout: roll over periodically so the number is readable.
    this._fpsFrames++;
    const fpsDt = now - this._fpsLast;
    if (fpsDt >= FPS_INTERVAL_MS) {
      const fps = Math.round((this._fpsFrames * 1000) / fpsDt);
      const el = document.getElementById("q-fps");
      if (el) el.textContent = `${fps} fps · ${this.tokeneData.size} tok`;
      this._fpsFrames = 0;
      this._fpsLast = now;
    }

    this._rafId = requestAnimationFrame(() => this.animate());
  },

  /**
   * Evict oldest tokenes when the count exceeds maxTokenes. Insertion order
   * is preserved by Map so we just take the first N keys.
   */
  _enforceTokeneCap() {
    const overflow = this.tokeneData.size - this.maxTokenes;
    if (overflow <= 0) return;
    let dropped = 0;
    for (const id of this.tokeneData.keys()) {
      if (dropped >= overflow) break;
      this.physics.remove(id);
      this.worldRenderer.removeTokene(id);
      this.tokeneData.delete(id);
      this.pushEvent("tokene_offscreen", { tokene_id: id });
      dropped++;
    }
  },

  /**
   * Per-tokene conveyor surface drag. Called inside the main animate loop
   * with a pre-fetched transform so we don't pay for an extra
   * physics.getTransform per conveyor per tokene per frame.
   */
  /**
   * Per-tokene magnet radial force. Falls off linearly from center to radius.
   * A tokene must match (or pass) BOTH the regex on its value AND the encoding
   * filter; either filter being empty means "match anything for this filter".
   */
  _applyMagnetForceToTokene(tid, tdata, xform, magList) {
    for (let i = 0; i < magList.length; i++) {
      const m = magList[i];
      const dx = xform.x - m.x;
      const dy = xform.y - m.y;
      const d2 = dx * dx + dy * dy;
      if (d2 > m.r2 || d2 < 1) continue;

      // Encoding filter
      if (m.encoding && tdata.encoding !== m.encoding) continue;
      // Regex filter
      if (m.regex && !m.regex.test(tdata.value || "")) continue;

      const d = Math.sqrt(d2);
      const falloff = 1 - d / m.r;   // 1 at center -> 0 at edge
      // strength is px/s² acceleration. Multiply by mass so applyImpulse
      // produces the same per-frame Δv regardless of how heavy the tokene is
      // — otherwise bits fly to the magnet while sentences crawl.
      const body = this.physics.getBody(tid);
      if (!body) continue;
      const massBody = body.mass() || 1;
      const a = m.sign * m.strength * falloff * MAGNET_DT * massBody;
      const fx = (dx / d) * a;
      const fy = (dy / d) * a;
      // sign -1 attracts (force opposite of dx,dy); +1 repels (same direction)
      body.applyImpulse({ x: fx, y: fy }, true);
    }
  },

  _applyConveyorForceToTokene(tid, tdata, xform, convList) {
    const thx = (tdata.width || 16) / 2;
    const thy = (tdata.height || 16) / 2;

    for (let i = 0; i < convList.length; i++) {
      const { conv, cos, sin } = convList[i];
      const dx = xform.x - conv.x;
      const dy = xform.y - conv.y;
      // Conveyor-local coords
      const localX = dx * cos + dy * sin;
      const localY = -dx * sin + dy * cos;
      if (Math.abs(localX) > conv.hw + thx) continue;
      if (localY > -conv.hh + 1) continue;                                  // not above
      if (localY < -conv.hh - thy - CONVEYOR_CONTACT_BAND) continue;        // too far above
      const body = this.physics.getBody(tid);
      if (!body) continue;
      const v = body.linvel();
      const vt = v.x * cos + v.y * sin;
      const dv = (conv.speed - vt) * CONVEYOR_COUPLING;
      const m = body.mass() || 1;
      body.applyImpulse({ x: cos * dv * m, y: sin * dv * m }, true);
    }
  },

  checkSensorIntersections() {
    for (const [nodeId, nodeInfo] of this.nodeData) {
      const isPortal = nodeInfo.type === "passive" && nodeInfo.config?.shape === "portal";
      if (nodeInfo.type !== "collector" && nodeInfo.type !== "transformer" && !isPortal) continue;
      // Magnets compute force per frame in animate() — they don't fire one-shot
      // tokene_near_transformer events, since their effect is continuous.
      if (nodeInfo.type === "transformer" && nodeInfo.config?.effect === "magnet") continue;

      const intersecting = this.physics.getSensorIntersections(nodeId);
      for (const tokeneId of intersecting) {
        if (!this.tokeneData.has(tokeneId)) continue;

        // Cooldown to avoid spamming the server / ping-ponging through portals
        if (!this.sensorCooldown.has(nodeId)) {
          this.sensorCooldown.set(nodeId, new Set());
        }
        const cooldownSet = this.sensorCooldown.get(nodeId);
        if (cooldownSet.has(tokeneId)) continue;

        cooldownSet.add(tokeneId);
        const cooldownMs = isPortal
          ? SENSOR_COOLDOWN_MS.portal
          : SENSOR_COOLDOWN_MS[nodeInfo.type] || SENSOR_COOLDOWN_MS.collector;
        const tid = setTimeout(() => cooldownSet.delete(tokeneId), cooldownMs);
        this._pendingTimeouts.push(tid);

        if (isPortal) {
          this._teleportThroughPortal(nodeId, nodeInfo, tokeneId, cooldownMs);
        } else if (nodeInfo.type === "collector") {
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

  _teleportThroughPortal(srcId, srcInfo, tokeneId, cooldownMs) {
    const channel = srcInfo.config?.channel;
    if (!channel) return;

    // Find a peer portal with the same channel (any one — first match wins).
    let dstInfo = null;
    let dstId = null;
    for (const [id, info] of this.nodeData) {
      if (id === srcId) continue;
      if (info.type !== "passive" || info.config?.shape !== "portal") continue;
      if (info.config?.channel === channel) {
        dstId = id;
        dstInfo = info;
        break;
      }
    }
    if (!dstInfo) return;

    const body = this.physics.getBody(tokeneId);
    if (!body) return;

    const dst = this.physics.getTransform(dstId);
    if (!dst) return;

    // Exit just above the destination ring so the tokene drops out the top
    // rather than spawning inside the sensor (which would re-trigger the
    // destination's cooldown and potentially tunnel through it).
    // Rapier is Y-down so "above" means -y.
    const r = parseFloat(dstInfo.config?.radius) || 30;
    body.setTranslation({ x: dst.x, y: dst.y - r - PORTAL_EXIT_CLEARANCE }, true);
    if (body.setLinvel) body.setLinvel({ x: 0, y: 0 }, true);
    if (body.setAngvel) body.setAngvel(0, true);

    // Reserve the destination too so the tokene doesn't bounce right back.
    if (!this.sensorCooldown.has(dstId)) {
      this.sensorCooldown.set(dstId, new Set());
    }
    const dstCd = this.sensorCooldown.get(dstId);
    dstCd.add(tokeneId);
    const tid = setTimeout(() => dstCd.delete(tokeneId), cooldownMs);
    this._pendingTimeouts.push(tid);
  },
};

export default WorldCanvas;
