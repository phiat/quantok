/**
 * Physics world wrapper around Rapier2D.
 * Manages rigid bodies, colliders, and sensor zones.
 */

let RAPIER = null;

export async function initRapier() {
  if (RAPIER) return RAPIER;
  RAPIER = await import("@dimforge/rapier2d-compat");
  // Suppress internal deprecation warning from rapier2d-compat's inline WASM loading
  const origWarn = console.warn;
  console.warn = (...args) => {
    if (typeof args[0] === "string" && args[0].includes("deprecated parameters")) return;
    origWarn.apply(console, args);
  };
  await RAPIER.init();
  console.warn = origWarn;
  return RAPIER;
}

export class PhysicsWorld {
  constructor(rapier, gravity = { x: 0.0, y: 150.0 }) {
    this.rapier = rapier;
    this.world = new rapier.World(gravity);
    this.bodies = new Map();     // id -> RigidBody
    this.colliders = new Map();  // id -> Collider
    this.sensors = new Map();    // id -> Collider (sensor)
    this.colliderToId = new Map(); // collider handle -> id
  }

  /** Spawn a dynamic tokene body */
  spawnTokene(id, x, y, hw, hh, mass) {
    const { RigidBodyDesc, ColliderDesc } = this.rapier;
    const bodyDesc = RigidBodyDesc.dynamic()
      .setTranslation(x, y)
      .setLinearDamping(0.05)
      .setAngularDamping(5.0);
    const body = this.world.createRigidBody(bodyDesc);

    const colliderDesc = ColliderDesc.cuboid(hw, hh)
      .setDensity(mass / (hw * hh * 4 || 1))
      .setRestitution(0.05)
      .setFriction(0.8);
    const collider = this.world.createCollider(colliderDesc, body);

    this.bodies.set(id, body);
    this.colliders.set(id, collider);
    this.colliderToId.set(collider.handle, id);
    return body;
  }

  /** Create a static floor/wall/ramp collider */
  spawnStatic(id, x, y, hw, hh, angle = 0, friction = 0.5, restitution = 0.3) {
    const { RigidBodyDesc, ColliderDesc } = this.rapier;
    const bodyDesc = RigidBodyDesc.fixed()
      .setTranslation(x, y)
      .setRotation(angle);
    const body = this.world.createRigidBody(bodyDesc);

    const colliderDesc = ColliderDesc.cuboid(hw, hh)
      .setRestitution(restitution)
      .setFriction(friction);
    const collider = this.world.createCollider(colliderDesc, body);

    this.bodies.set(id, body);
    this.colliders.set(id, collider);
    return body;
  }

  /** Create a kinematic body for draggable nodes */
  spawnKinematic(id, x, y, hw, hh) {
    const { RigidBodyDesc, ColliderDesc } = this.rapier;
    const bodyDesc = RigidBodyDesc.kinematicPositionBased()
      .setTranslation(x, y);
    const body = this.world.createRigidBody(bodyDesc);

    const colliderDesc = ColliderDesc.cuboid(hw, hh);
    const collider = this.world.createCollider(colliderDesc, body);

    this.bodies.set(id, body);
    this.colliders.set(id, collider);
    return body;
  }

  /** Create a sensor zone attached to existing body (for collector/transformer detection) */
  spawnSensor(id, x, y, radius) {
    const { ColliderDesc } = this.rapier;
    const body = this.bodies.get(id);

    if (body) {
      // Attach sensor collider to existing kinematic body — moves with it
      const colliderDesc = ColliderDesc.ball(radius).setSensor(true);
      const collider = this.world.createCollider(colliderDesc, body);
      this.sensors.set(id, collider);
      return collider;
    }

    // Fallback: create standalone sensor if no body exists yet
    const { RigidBodyDesc } = this.rapier;
    const bodyDesc = RigidBodyDesc.fixed().setTranslation(x, y);
    const newBody = this.world.createRigidBody(bodyDesc);
    const colliderDesc = ColliderDesc.ball(radius).setSensor(true);
    const collider = this.world.createCollider(colliderDesc, newBody);
    this.sensors.set(id, collider);
    this.bodies.set("sensor_" + id, newBody);
    return collider;
  }

  /** Remove a body, its colliders, and any associated sensor */
  remove(id) {
    // Save collider handle before removing body (body removal invalidates attached colliders)
    const collider = this.colliders.get(id);
    if (collider) {
      this.colliderToId.delete(collider.handle);
      this.colliders.delete(id);
    }
    const body = this.bodies.get(id);
    if (body) {
      this.world.removeRigidBody(body);
      this.bodies.delete(id);
    }
    // Clean up sensor (attached to body, already removed with it)
    this.sensors.delete(id);
    // Clean up standalone sensor body if it exists
    const sensorBody = this.bodies.get("sensor_" + id);
    if (sensorBody) {
      this.world.removeRigidBody(sensorBody);
      this.bodies.delete("sensor_" + id);
    }
  }

  /** Move a kinematic body to a new position */
  moveKinematic(id, x, y) {
    const body = this.bodies.get(id);
    if (body) {
      body.setNextKinematicTranslation({ x, y });
    }
  }

  /** Apply a force to a dynamic body (for attractors/repellers) */
  applyForce(id, fx, fy) {
    const body = this.bodies.get(id);
    if (body) {
      body.applyForce({ x: fx, y: fy }, true);
    }
  }

  /** Step the physics simulation */
  step() {
    this.world.step();
  }

  /** Get position and rotation of a body */
  getTransform(id) {
    const body = this.bodies.get(id);
    if (!body) return null;
    const pos = body.translation();
    return { x: pos.x, y: pos.y, rotation: body.rotation() };
  }

  /** Find all tokene IDs intersecting a sensor */
  getSensorIntersections(sensorId) {
    const sensor = this.sensors.get(sensorId);
    if (!sensor) return [];

    const ids = [];
    this.world.intersectionPairsWith(sensor, (otherCollider) => {
      const id = this.colliderToId.get(otherCollider.handle);
      if (id) ids.push(id);
    });
    return ids;
  }

  /** Set world gravity */
  setGravity(x, y) {
    this.world.gravity = new this.rapier.Vector2(x, y);
  }

  /** Get body count for debugging */
  bodyCount() {
    return this.bodies.size;
  }
}
