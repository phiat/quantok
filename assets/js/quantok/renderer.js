/**
 * Three.js renderer for the Quantok world.
 * Orthographic camera with zoom/pan, troika SDF text, bloom post-processing.
 */

import * as THREE from "three";
import { Text } from "troika-three-text";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";
import {
  ENCODING_COLORS, DEFAULT_COLOR, BG_COLOR,
  ZOOM_MIN, ZOOM_MAX, ZOOM_SPEED, lerpColor,
} from "./utils";

export class WorldRenderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.meshes = new Map();       // id -> THREE.Group (tokene bg + text)
    this.nodeMeshes = new Map();   // id -> THREE.Group (node)

    // Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(BG_COLOR);

    // Ortho camera
    const w = canvas.clientWidth || 1;
    const h = canvas.clientHeight || 1;
    this._baseW = w;
    this._baseH = h;
    this.camera = new THREE.OrthographicCamera(
      -w / 2, w / 2, h / 2, -h / 2, 0.1, 1000
    );
    this.camera.position.z = 100;

    // Camera controls state
    this.zoom = 1.0;
    this.panOffset = { x: 0, y: 0 };
    this._isPanning = false;
    this._panStart = { x: 0, y: 0 };

    // Renderer
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
    });
    this.resize();

    // Lighting (2.5D feel)
    const ambient = new THREE.AmbientLight(0xffffff, 0.7);
    this.scene.add(ambient);

    const directional = new THREE.DirectionalLight(0xffffff, 0.3);
    directional.position.set(2, 2, 5);
    this.scene.add(directional);

    // Post-processing
    this._useComposer = false;
    try {
      this.composer = new EffectComposer(this.renderer);
      this.composer.addPass(new RenderPass(this.scene, this.camera));

      this.bloomPass = new UnrealBloomPass(
        new THREE.Vector2(w, h),
        0.15,   // strength (subtle)
        0.4,    // radius
        0.85    // threshold
      );
      this.composer.addPass(this.bloomPass);
      this.composer.addPass(new OutputPass());
      this._useComposer = true;
    } catch (err) {
      console.warn("Post-processing unavailable, using direct render:", err);
    }

    // Event listeners
    this._onResize = () => this.resize();
    window.addEventListener("resize", this._onResize);

    this._onWheel = (e) => this._handleWheel(e);
    canvas.addEventListener("wheel", this._onWheel, { passive: false });
  }

  // --- Camera controls ---

  _handleWheel(e) {
    e.preventDefault();
    const delta = -e.deltaY * ZOOM_SPEED;
    const oldZoom = this.zoom;
    this.zoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, this.zoom * (1 + delta)));

    // Zoom toward mouse position
    const rect = this.canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left - rect.width / 2;
    const my = -(e.clientY - rect.top - rect.height / 2);

    // Adjust pan so the point under cursor stays fixed
    const zoomRatio = this.zoom / oldZoom;
    this.panOffset.x = mx - zoomRatio * (mx - this.panOffset.x);
    this.panOffset.y = my - zoomRatio * (my - this.panOffset.y);

    this._updateCamera();
  }

  startPan(screenX, screenY) {
    this._isPanning = true;
    this._panStart.x = screenX;
    this._panStart.y = screenY;
    this._panOffsetStart = { ...this.panOffset };
  }

  updatePan(screenX, screenY) {
    if (!this._isPanning) return;
    const dx = screenX - this._panStart.x;
    const dy = -(screenY - this._panStart.y);
    this.panOffset.x = this._panOffsetStart.x + dx;
    this.panOffset.y = this._panOffsetStart.y + dy;
    this._updateCamera();
  }

  endPan() {
    this._isPanning = false;
  }

  _updateCamera() {
    const w = this._baseW / this.zoom;
    const h = this._baseH / this.zoom;
    this.camera.left = -w / 2 - this.panOffset.x / this.zoom;
    this.camera.right = w / 2 - this.panOffset.x / this.zoom;
    this.camera.top = h / 2 - this.panOffset.y / this.zoom;
    this.camera.bottom = -h / 2 - this.panOffset.y / this.zoom;
    this.camera.updateProjectionMatrix();
  }

  // --- Tokene rendering (troika SDF text) ---

  /** Create a tokene mesh (colored bg + SDF text) */
  createTokeneMesh(id, value, encoding, width, height) {
    const color = ENCODING_COLORS[encoding] || DEFAULT_COLOR;
    const group = new THREE.Group();

    // Background rect
    const bgGeo = new THREE.PlaneGeometry(width, height);
    const bgMat = new THREE.MeshBasicMaterial({ color });
    const bgMesh = new THREE.Mesh(bgGeo, bgMat);
    bgMesh.position.z = 0;
    group.add(bgMesh);

    // SDF text
    const displayText = value.length > 12 ? value.slice(0, 11) + "\u2026" : value;
    const fontSize = Math.min(height * 0.7, width / (displayText.length * 0.62));

    const text = new Text();
    text.text = displayText;
    text.fontSize = Math.max(fontSize, 4);
    text.color = BG_COLOR;
    text.anchorX = "center";
    text.anchorY = "middle";
    text.fontWeight = "bold";
    text.position.z = 0.1;
    text.sync();
    group.add(text);

    group.userData = { id, encoding, value, bgMesh, baseColor: color };
    this.scene.add(group);
    this.meshes.set(id, group);
    return group;
  }

  // --- Node rendering ---

  /** Create a node mesh (emitter, collector, passive, transformer) */
  createNodeMesh(id, nodeType, label, x, y, width, height, config = {}) {
    const group = new THREE.Group();
    group.position.set(x, y, 0);

    let color;
    switch (nodeType) {
      case "emitter":     color = 0x44cc88; break;
      case "collector":   color = 0xffc49b; break;
      case "transformer": color = 0xcc66cc; break;
      case "passive":     color = 0x294c60; break;
      default:            color = 0x294c60;
    }

    // Main body
    const bodyGeo = new THREE.PlaneGeometry(width, height);
    const bodyMat = new THREE.MeshStandardMaterial({
      color,
      roughness: 0.6,
      metalness: 0.2,
      transparent: true,
      opacity: 0.85,
    });
    const bodyMesh = new THREE.Mesh(bodyGeo, bodyMat);
    bodyMesh.userData = { isBody: true };
    group.add(bodyMesh);

    // Pipe spout for emitters
    if (nodeType === "emitter") {
      const pipeW = 6;
      const pipeH = 20;
      const pipeGeo = new THREE.PlaneGeometry(pipeW, pipeH);
      const pipeMat = new THREE.MeshBasicMaterial({
        color,
        transparent: true,
        opacity: 0.9,
      });
      const pipe = new THREE.Mesh(pipeGeo, pipeMat);
      pipe.position.y = -(height / 2 + pipeH / 2);
      group.add(pipe);

      const tipGeo = new THREE.PlaneGeometry(pipeW + 4, 3);
      const tip = new THREE.Mesh(tipGeo, pipeMat.clone());
      tip.position.y = -(height / 2 + pipeH);
      group.add(tip);
    }

    // Label (troika SDF text)
    if (label) {
      const labelText = new Text();
      labelText.text = label;
      labelText.fontSize = 10;
      labelText.color = 0xffffff;
      labelText.anchorX = "center";
      labelText.anchorY = "middle";
      labelText.position.y = height / 2 + 10;
      labelText.position.z = 0.1;
      labelText.sync();
      group.add(labelText);
    }

    // Effect radius circle for transformers
    if (nodeType === "transformer" && config.radius) {
      const radius = parseFloat(config.radius);
      const circleGeo = new THREE.RingGeometry(radius - 1, radius, 32);
      const circleMat = new THREE.MeshBasicMaterial({
        color,
        transparent: true,
        opacity: 0.2,
        side: THREE.DoubleSide,
      });
      const circle = new THREE.Mesh(circleGeo, circleMat);
      circle.position.z = -0.1;
      group.add(circle);
    }

    // Spout for collectors that emit
    if (nodeType === "collector" && config.emit) {
      const pipeW = 6;
      const pipeH = 14;
      const pipeGeo = new THREE.PlaneGeometry(pipeW, pipeH);
      const pipeMat = new THREE.MeshBasicMaterial({
        color: 0xffc49b,
        transparent: true,
        opacity: 0.7,
      });
      const pipe = new THREE.Mesh(pipeGeo, pipeMat);
      pipe.position.y = -(height / 2 + pipeH / 2);
      group.add(pipe);

      const tipGeo = new THREE.PlaneGeometry(pipeW + 3, 2);
      const tip = new THREE.Mesh(tipGeo, pipeMat.clone());
      tip.position.y = -(height / 2 + pipeH);
      group.add(tip);
    }

    // Buffer slots for collectors
    if (nodeType === "collector" && config.capacity) {
      const slotWidth = Math.min(width / config.capacity, 12);
      for (let i = 0; i < config.capacity; i++) {
        const slotGeo = new THREE.PlaneGeometry(slotWidth - 1, height * 0.6);
        const slotMat = new THREE.MeshBasicMaterial({
          color: 0x333333,
          transparent: true,
          opacity: 0.3,
        });
        const slot = new THREE.Mesh(slotGeo, slotMat);
        const xOff = (i - (config.capacity - 1) / 2) * slotWidth;
        slot.position.set(xOff, 0, 0.1);
        slot.userData = { slotIndex: i };
        group.add(slot);
      }
    }

    // Apply rotation for passive nodes (ramps, walls)
    if (nodeType === "passive" && config.angle != null) {
      group.rotation.z = -config.angle;
    }

    // Conveyor: tint + direction chevrons
    if (nodeType === "passive" && config.shape === "conveyor") {
      bodyMat.color.setHex(0xadb6c4);
      bodyMat.opacity = 0.95;
      const speed = parseFloat(config.speed) || 0;
      const dir = speed >= 0 ? 1 : -1;
      const chevronCount = Math.max(2, Math.floor(width / 40));
      const spacing = width / chevronCount;
      const chevronMat = new THREE.MeshBasicMaterial({
        color: 0x001b2e,
        transparent: true,
        opacity: 0.75,
      });
      for (let i = 0; i < chevronCount; i++) {
        const cx = -width / 2 + spacing / 2 + i * spacing;
        const tri = new THREE.Shape();
        const s = Math.min(height * 0.45, 5);
        tri.moveTo(-s * dir, -s);
        tri.lineTo(s * dir, 0);
        tri.lineTo(-s * dir, s);
        tri.closePath();
        const geo = new THREE.ShapeGeometry(tri);
        const mesh = new THREE.Mesh(geo, chevronMat);
        mesh.position.set(cx, 0, 0.2);
        group.add(mesh);
      }
    }

    group.userData = { id, nodeType };
    this.scene.add(group);
    this.nodeMeshes.set(id, group);
    return group;
  }

  /** Update collector buffer slot visuals */
  updateCollectorBuffer(collectorId, buffer) {
    const group = this.nodeMeshes.get(collectorId);
    if (!group) return;

    const slots = group.children.filter(c => c.userData.slotIndex !== undefined);
    slots.sort((a, b) => a.userData.slotIndex - b.userData.slotIndex);

    for (let i = 0; i < slots.length; i++) {
      const slot = slots[i];
      if (i < buffer.length) {
        const item = buffer[i];
        const color = ENCODING_COLORS[item.encoding] || DEFAULT_COLOR;
        slot.material.color.setHex(color);
        slot.material.opacity = 0.85;
      } else {
        slot.material.color.setHex(0x333333);
        slot.material.opacity = 0.3;
      }
    }
  }

  // --- Transform updates ---

  /** Update tokene mesh position and rotation from physics */
  updateTokeneTransform(id, x, y, rotation) {
    const group = this.meshes.get(id);
    if (group) {
      group.position.set(x, y, 0);
      group.rotation.z = rotation;
    }
  }

  /** Update tokene visual decay: desaturation + opacity based on integrity ratio */
  updateTokeneDecay(id, integrityRatio) {
    const group = this.meshes.get(id);
    if (!group) return;
    const { bgMesh, baseColor } = group.userData;
    if (!bgMesh) return;

    // Desaturate: lerp from base color toward grey as integrity drops
    const { r, g, b } = lerpColor(baseColor, 0x555555, integrityRatio);
    bgMesh.material.color.setRGB(r, g, b);

    // Opacity: fade as integrity drops
    if (!bgMesh.material.transparent) bgMesh.material.transparent = true;
    bgMesh.material.opacity = 0.3 + integrityRatio * 0.7;

    // Pulse when near death (integrity < 15%)
    if (integrityRatio < 0.15 && integrityRatio > 0) {
      const pulse = 0.5 + 0.5 * Math.sin(performance.now() * 0.01);
      bgMesh.material.opacity *= 0.4 + pulse * 0.6;
    }
  }

  // --- Removal ---

  /** Remove a tokene mesh */
  removeTokene(id) {
    const group = this.meshes.get(id);
    if (group) {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) {
          if (child.material.map) child.material.map.dispose();
          child.material.dispose();
        }
        // troika Text cleanup
        if (child.dispose) child.dispose();
      });
      this.meshes.delete(id);
    }
  }

  /** Remove a node mesh */
  removeNode(id) {
    const group = this.nodeMeshes.get(id);
    if (group) {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) {
          if (child.material.map) child.material.map.dispose();
          child.material.dispose();
        }
        if (child.dispose) child.dispose();
      });
      this.nodeMeshes.delete(id);
    }
  }

  /** Move a node mesh (user dragging) */
  moveNode(id, x, y) {
    const group = this.nodeMeshes.get(id);
    if (group) {
      group.position.set(x, y, 0);
    }
  }

  // --- Coordinate conversion (accounts for zoom + pan) ---

  /** Convert screen coords to world coords */
  screenToWorld(screenX, screenY) {
    const rect = this.canvas.getBoundingClientRect();
    const ndcX = ((screenX - rect.left) / rect.width) * 2 - 1;
    const ndcY = -((screenY - rect.top) / rect.height) * 2 + 1;
    // Map NDC to camera frustum
    const x = (ndcX * (this.camera.right - this.camera.left)) / 2
            + (this.camera.right + this.camera.left) / 2;
    const y = (ndcY * (this.camera.top - this.camera.bottom)) / 2
            + (this.camera.top + this.camera.bottom) / 2;
    return { x, y };
  }

  /** Convert world coords to screen coords */
  worldToScreen(wx, wy) {
    const vec = new THREE.Vector3(wx, wy, 0);
    vec.project(this.camera);
    const rect = this.canvas.getBoundingClientRect();
    const sx = (vec.x * 0.5 + 0.5) * rect.width + rect.left;
    const sy = (-vec.y * 0.5 + 0.5) * rect.height + rect.top;
    return { x: sx, y: sy };
  }

  /** Hit-test node meshes at screen coords, returns node id or null */
  hitTestNode(screenX, screenY) {
    const world = this.screenToWorld(screenX, screenY);
    for (const [id, group] of this.nodeMeshes) {
      const body = group.children.find(c => c.userData.isBody);
      if (!body || !body.geometry) continue;
      const params = body.geometry.parameters;
      const hw = params.width / 2;
      const hh = params.height / 2;
      const gx = group.position.x;
      const gy = group.position.y;
      if (world.x >= gx - hw && world.x <= gx + hw &&
          world.y >= gy - hh && world.y <= gy + hh) {
        return id;
      }
    }
    return null;
  }

  // --- Rendering ---

  /** Render the scene with post-processing */
  render() {
    if (this._useComposer) {
      this.composer.render();
    } else {
      this.renderer.render(this.scene, this.camera);
    }
  }

  /** Handle window resize */
  resize() {
    const w = this.canvas.clientWidth || 1;
    const h = this.canvas.clientHeight || 1;
    this._baseW = w;
    this._baseH = h;
    this.renderer.setSize(w, h);
    if (this._useComposer) this.composer.setSize(w, h);
    this._updateCamera();
  }

  /** Clean up all GPU resources */
  dispose() {
    window.removeEventListener("resize", this._onResize);
    this.canvas.removeEventListener("wheel", this._onWheel);
    // Dispose tokene meshes
    this.meshes.forEach((group) => {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) {
          if (child.material.map) child.material.map.dispose();
          child.material.dispose();
        }
        if (child.dispose) child.dispose();
      });
    });
    this.meshes.clear();
    // Dispose node groups
    this.nodeMeshes.forEach((group) => {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) {
          if (child.material.map) child.material.map.dispose();
          child.material.dispose();
        }
        if (child.dispose) child.dispose();
      });
    });
    this.nodeMeshes.clear();
    // Dispose composer + renderer
    if (this._useComposer) this.composer.dispose();
    this.renderer.dispose();
  }
}
