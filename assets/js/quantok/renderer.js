/**
 * Three.js renderer for the Quantok world.
 * Orthographic camera for 2D with lighting for depth.
 */

import * as THREE from "three";

// Encoding -> color mapping (bright, warm palette against dark bg)
const ENCODING_COLORS = {
  bit:      0xe0e0e0,
  byte:     0x66aaee,
  rune:     0xeea855,
  token:    0x55ddaa,
  ngram:    0x55dddd,
  word:     0xffc49b,  // peach glow
  phrase:   0xee9933,
  sentence: 0xd4a0ff,
};

const DEFAULT_COLOR = 0xadb6c4;  // pale slate

export class WorldRenderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.meshes = new Map();       // id -> THREE.Mesh
    this.nodeMeshes = new Map();   // id -> THREE.Group
    this.textureCache = new Map(); // text -> THREE.Texture

    // Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x001b2e);

    // Ortho camera
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    this.camera = new THREE.OrthographicCamera(
      -w / 2, w / 2, h / 2, -h / 2, 0.1, 1000
    );
    this.camera.position.z = 100;

    // Renderer — defer setSize until first render to avoid 0x0 canvas
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

    // Handle resize
    this._onResize = () => this.resize();
    window.addEventListener("resize", this._onResize);

    // Camera pan state
    this.panOffset = { x: 0, y: 0 };
    this.zoom = 1.0;
  }

  /** Create a tokene mesh (rounded rect with text) */
  createTokeneMesh(id, value, encoding, width, height) {
    const color = ENCODING_COLORS[encoding] || DEFAULT_COLOR;

    // Geometry
    const geometry = new THREE.PlaneGeometry(width, height);

    // Material with text texture
    const texture = this.getTextTexture(value, width, height, color);
    const material = new THREE.MeshBasicMaterial({
      map: texture,
    });

    const mesh = new THREE.Mesh(geometry, material);
    mesh.userData = { id, encoding, value };
    this.scene.add(mesh);
    this.meshes.set(id, mesh);
    return mesh;
  }

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
    group.add(bodyMesh);

    // Pipe spout for emitters
    if (nodeType === "emitter") {
      const pipeW = 6;
      const pipeH = 20;
      const pipeGeo = new THREE.PlaneGeometry(pipeW, pipeH);
      const pipeMat = new THREE.MeshStandardMaterial({
        color,
        roughness: 0.4,
        metalness: 0.3,
        transparent: true,
        opacity: 0.9,
      });
      const pipe = new THREE.Mesh(pipeGeo, pipeMat);
      pipe.position.y = -(height / 2 + pipeH / 2);
      group.add(pipe);

      // Small nozzle tip
      const tipGeo = new THREE.PlaneGeometry(pipeW + 4, 3);
      const tip = new THREE.Mesh(tipGeo, pipeMat.clone());
      tip.position.y = -(height / 2 + pipeH);
      group.add(tip);
    }

    // Label
    if (label) {
      const labelTexture = this.getTextTexture(label, width, 16, 0xffffff);
      const labelGeo = new THREE.PlaneGeometry(width, 16);
      const labelMat = new THREE.MeshBasicMaterial({
        map: labelTexture,
        transparent: true,
      });
      const labelMesh = new THREE.Mesh(labelGeo, labelMat);
      labelMesh.position.y = height / 2 + 10;
      group.add(labelMesh);
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

    group.userData = { id, nodeType };
    this.scene.add(group);
    this.nodeMeshes.set(id, group);
    return group;
  }

  /** Update tokene mesh position and rotation from physics */
  updateTokeneTransform(id, x, y, rotation) {
    const mesh = this.meshes.get(id);
    if (mesh) {
      mesh.position.set(x, y, 0);
      mesh.rotation.z = rotation;
    }
  }

  /** Update tokene opacity based on integrity */
  updateTokeneIntegrity(id, integrity) {
    const mesh = this.meshes.get(id);
    if (mesh) {
      mesh.material.opacity = 0.3 + integrity * 0.7;
    }
  }

  /** Remove a tokene mesh */
  removeTokene(id) {
    const mesh = this.meshes.get(id);
    if (mesh) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
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
        if (child.material) child.material.dispose();
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

  /** Create or get cached text texture */
  getTextTexture(text, width, height, color) {
    const key = `${text}_${width}_${height}_${color}`;
    if (this.textureCache.has(key)) return this.textureCache.get(key);

    const canvas = document.createElement("canvas");
    const scale = 2; // retina
    canvas.width = Math.max(width * scale, 4);
    canvas.height = Math.max(height * scale, 4);

    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Solid bg, full bleed
    const hex = "#" + (color & 0xffffff).toString(16).padStart(6, "0");
    ctx.fillStyle = hex;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Dark text, fill the space
    const fontSize = Math.min(canvas.height * 0.85, canvas.width / (text.length * 0.52));
    ctx.fillStyle = "#001b2e";
    ctx.font = `bold ${Math.max(fontSize, 8)}px monospace`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";

    // Truncate if too long
    const displayText = text.length > 12 ? text.slice(0, 11) + "\u2026" : text;
    ctx.fillText(displayText, canvas.width / 2, canvas.height / 2);

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearFilter;
    this.textureCache.set(key, texture);
    return texture;
  }

  /** Render the scene */
  render() {
    this.renderer.render(this.scene, this.camera);
  }

  /** Handle window resize */
  resize() {
    const w = this.canvas.clientWidth || 1;
    const h = this.canvas.clientHeight || 1;
    this.camera.left = -w / 2;
    this.camera.right = w / 2;
    this.camera.top = h / 2;
    this.camera.bottom = -h / 2;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
  }

  /** Convert screen coords to world coords */
  screenToWorld(screenX, screenY) {
    const rect = this.canvas.getBoundingClientRect();
    const x = screenX - rect.left - rect.width / 2;
    const y = -(screenY - rect.top - rect.height / 2);
    return { x, y };
  }

  /** Convert world coords to screen coords */
  worldToScreen(wx, wy) {
    const rect = this.canvas.getBoundingClientRect();
    const sx = wx + rect.width / 2 + rect.left;
    const sy = -wy + rect.height / 2 + rect.top;
    return { x: sx, y: sy };
  }

  /** Hit-test node meshes at screen coords, returns node id or null */
  hitTestNode(screenX, screenY) {
    const world = this.screenToWorld(screenX, screenY);
    // Simple AABB check against node groups
    for (const [id, group] of this.nodeMeshes) {
      const body = group.children[0]; // first child is the body mesh
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

  /** Clean up all GPU resources */
  dispose() {
    window.removeEventListener("resize", this._onResize);
    // Dispose tokene meshes
    this.meshes.forEach((mesh) => {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    });
    this.meshes.clear();
    // Dispose node groups
    this.nodeMeshes.forEach((group) => {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) child.material.dispose();
      });
    });
    this.nodeMeshes.clear();
    // Dispose cached textures
    this.textureCache.forEach((t) => t.dispose());
    this.textureCache.clear();
    // Dispose renderer
    this.renderer.dispose();
  }
}
