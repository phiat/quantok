# Quantok Research Notes

## Physics Engine: Rapier2D

**Chosen**: `@dimforge/rapier2d-compat` (WASM build of Rust Rapier2D)

Why Rapier:
- Fastest 2D physics in browser (Rust compiled to WASM)
- Proper rigid body simulation with collision detection
- Sensor colliders (trigger zones without physical collision)
- Built-in force/impulse API for attractors/repellers
- Deterministic stepping (same input = same output)
- Good Three.js integration examples
- MIT licensed

Alternatives considered:
- Matter.js: pure JS, slower, but simpler API and bigger community
- Planck.js: Box2D port, decent perf, less active
- cannon-es: 3D only, overkill

Key Rapier concepts:
- `RigidBodyDesc.dynamic()` for tokenes (gravity-affected)
- `RigidBodyDesc.kinematicPositionBased()` for draggable nodes
- `RigidBodyDesc.fixed()` for floors/walls
- `ColliderDesc.cuboid(hw, hh).setSensor(true)` for buffer zones
- `world.intersectionPairsWith(collider)` for proximity detection
- `EventQueue` for efficient collision event handling

Performance notes:
- Rapier handles 1000+ bodies easily at 60fps
- WASM module is ~400KB gzipped, loads async
- Physics step is ~1ms for 500 bodies (plenty of budget)

## Three.js Setup

Using OrthographicCamera for 2D with nice rendering capabilities:

```javascript
// Ortho camera for 2D
const frustumSize = 800;
const aspect = window.innerWidth / window.innerHeight;
const camera = new THREE.OrthographicCamera(
  -frustumSize * aspect / 2, frustumSize * aspect / 2,
  frustumSize / 2, -frustumSize / 2,
  0.1, 1000
);
camera.position.z = 100;

// Still get lighting for 2.5D feel
const ambient = new THREE.AmbientLight(0xffffff, 0.6);
const directional = new THREE.DirectionalLight(0xffffff, 0.4);
directional.position.set(1, 1, 2);
```

### Text on Tokenes

**Option A: Canvas Texture** (starting with this)
- Create a 2D canvas, render text, use as Three.js texture
- Pros: simple, full CSS font support, good for small text counts
- Cons: texture per unique text, gets expensive at 500+ unique strings

```javascript
function createTextTexture(text, width, height) {
  const canvas = document.createElement('canvas');
  canvas.width = width * 2; // retina
  canvas.height = height * 2;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#ffffff';
  ctx.font = `${height}px monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, canvas.width / 2, canvas.height / 2);
  return new THREE.CanvasTexture(canvas);
}
```

**Option B: troika-three-text** (upgrade later)
- SDF text rendering, crisp at any zoom
- Single draw call for many text instances
- GPU-accelerated
- Better for 500+ tokenes

**Option C: InstancedMesh + Texture Atlas** (if we need extreme perf)
- Pre-render all unique texts into one atlas texture
- Use UV offsets in InstancedMesh
- One draw call for thousands of tokenes

### Rendering Pipeline

```
requestAnimationFrame loop:
  1. Step Rapier physics world
  2. Read body positions from Rapier
  3. Update Three.js mesh positions to match
  4. Check sensor intersections -> report to server
  5. Render Three.js scene
```

## Rapier + Three.js Integration Pattern

```javascript
class PhysicsWorld {
  constructor() {
    this.rapier = null;  // loaded async
    this.world = null;
    this.bodies = new Map();  // tokene_id -> { rigidBody, collider }
    this.meshes = new Map();  // tokene_id -> THREE.Mesh
  }

  async init() {
    this.rapier = await import('@dimforge/rapier2d-compat');
    await this.rapier.init();
    this.world = new this.rapier.World({ x: 0.0, y: 9.81 });
  }

  spawnTokene(tokene) {
    const { RAPIER } = this.rapier;
    // Physics body
    const bodyDesc = RAPIER.RigidBodyDesc.dynamic()
      .setTranslation(tokene.x, tokene.y);
    const body = this.world.createRigidBody(bodyDesc);
    const colliderDesc = RAPIER.ColliderDesc.cuboid(tokene.hw, tokene.hh)
      .setDensity(tokene.mass);
    this.world.createCollider(colliderDesc, body);
    // Three.js mesh
    const mesh = createTokeneMesh(tokene);
    scene.add(mesh);
    this.bodies.set(tokene.id, body);
    this.meshes.set(tokene.id, mesh);
  }

  step() {
    this.world.step();
    // Sync positions
    for (const [id, body] of this.bodies) {
      const pos = body.translation();
      const mesh = this.meshes.get(id);
      mesh.position.set(pos.x, pos.y, 0);
      mesh.rotation.z = body.rotation();
    }
  }
}
```

## LiveView + Three.js Hook

Phoenix LiveView hook pattern for integrating Three.js:

```javascript
const Hooks = {};

Hooks.WorldCanvas = {
  mounted() {
    this.physics = new PhysicsWorld();
    this.physics.init().then(() => this.startLoop());

    // Server -> Client events
    this.handleEvent("emit_tokenes", ({ emitter_id, tokenes }) => {
      const emitter = this.getNodePosition(emitter_id);
      tokenes.forEach((t, i) => {
        setTimeout(() => {
          this.physics.spawnTokene({
            ...t, x: emitter.x, y: emitter.y - 20
          });
        }, i * t.emit_rate);
      });
    });

    this.handleEvent("absorb_tokene", ({ collector_id, tokene_id }) => {
      this.physics.removeTokene(tokene_id);
      this.animateAbsorb(collector_id, tokene_id);
    });
  },

  startLoop() {
    const animate = () => {
      this.physics.step();
      this.checkSensorIntersections();
      this.renderer.render(this.scene, this.camera);
      requestAnimationFrame(animate);
    };
    animate();
  },

  checkSensorIntersections() {
    // Check if any tokene is near a collector's sensor zone
    // Report to server for logic decisions
    for (const [collectorId, sensor] of this.sensors) {
      this.physics.world.intersectionPairsWith(sensor, (otherCollider) => {
        const tokeneId = this.colliderToTokene.get(otherCollider.handle);
        if (tokeneId) {
          this.pushEvent("tokene_near_collector", {
            tokene_id: tokeneId,
            collector_id: collectorId
          });
        }
      });
    }
  }
};
```

## SQLite for Persistence

Using ecto_sqlite3:
- No server process needed
- Single file database per world
- Good enough for single-user sandbox
- Easy backup (copy .db file)
- Postgres available as future option (quantok-qg9)

## Performance Targets

| Metric                | Target  | Notes                           |
|-----------------------|---------|---------------------------------|
| Active tokenes        | 500     | Comfortable with instancing     |
| Physics step          | < 2ms   | Rapier handles this easily      |
| Render frame          | < 12ms  | 60fps budget is 16.6ms          |
| Emit latency          | < 50ms  | Server -> spawn visible         |
| Absorb latency        | < 30ms  | Sensor detect -> visual absorb  |
| Tiktokenex encode     | < 5ms   | For typical command output       |
| World save/load       | < 200ms | JSON serialize + SQLite write   |

## Package.json Dependencies (Frontend)

```json
{
  "dependencies": {
    "three": "^0.170.0",
    "@dimforge/rapier2d-compat": "^0.14.0"
  },
  "devDependencies": {
    "esbuild": "^0.24.0"
  }
}
```

Note: rapier2d-compat is the WASM build that works without native compilation.
The non-compat version requires wasm-pack which is more complex to set up.
