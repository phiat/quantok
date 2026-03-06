# Quantok Architecture

## Overview

Quantok is a physics sandbox where data chunks ("tokenes") are physical objects.
Emitters produce tokenes from commands/data, tokenes fall through a 2D world
affected by gravity and forces, and collectors absorb them to trigger actions.

## System Architecture

```
 Elixir/Phoenix Backend                Three.js + Rapier2D Frontend
 ==========================             ==============================

 World GenServer                        Scene (Three.js ortho camera)
   nodes: %{id => Node}                   node meshes (draggable)
   tokenes: %{id => Tokene}               tokene meshes (text on rect)
   environment: gravity, etc              buffer slot visuals
   paused: boolean                        passive geometry
                                          force field visuals

 Events (via LiveView push_event)       Physics (Rapier2D WASM)
   {:emit, id, [tokene]}                  dynamic rigid bodies (tokenes)
   {:absorb, id, tokene_id}               kinematic bodies (nodes)
   {:transform, id, id, [tokenes]}        static colliders (passives)
   {:trigger, id, output}                 sensor zones (buffers)
   {:node_added/removed/updated}          gravity + force fields

 Phoenix PubSub                         Client reports proximity
   "world:{id}" topic                     events back to server
   broadcast on every state change        for logic decisions
```

## Authority Split

- **Server**: all logic decisions - emit, absorb, split, trigger. Command
  execution. Buffer state. Node configuration. Tokene lifecycle.
- **Client**: physics simulation, rendering, collision detection, user
  interaction (drag, click, spawn). Owns the animation loop.
- **Bridge**: client detects proximity via Rapier sensors, reports to server.
  Server decides outcome, broadcasts events. Client animates the result.

The server never simulates physics. The client never executes commands.

## Data Flow: Emit -> Fall -> Collect

```
 1. User triggers emitter (click, auto-fire, or API)
 2. Server: Emitter.fire(node)
    a. Execute source (Shell.execute("date") -> "Fri Mar 6...")
    b. Chunk output (WordChunker -> ["Fri", "Mar", "6", ...])
    c. Create Tokene structs with encoding, integrity, mass
 3. Server: broadcast {:emit, emitter_id, tokenes} via PubSub
 4. Client: receive push_event, spawn Rapier rigid bodies at emitter position
    a. Create Three.js mesh (rounded rect + canvas text texture)
    b. Set mass from Tokene.mass(), dimensions from Tokene.dimensions()
 5. Client: physics loop - tokenes fall, collide with passives, bounce
 6. Client: Rapier sensor on collector detects tokene intersection
 7. Client: pushEvent("absorb", {tokene_id, collector_id}) to server
 8. Server: World.absorb_tokene() - add to buffer, remove from world
 9. Server: broadcast {:absorb, collector_id, tokene_id}
10. Client: remove rigid body, tween mesh into buffer slot
11. When buffer fills (on_full) or user triggers (manual):
    Server: Collector.trigger() - concatenate buffer, run action
    Server: broadcast {:trigger, collector_id, output}
    Server: optionally re-emit output as new tokenes
```

## Module Map (implemented)

```
lib/quantok/
  world.ex             - World GenServer: central state, node CRUD,
                          emitter firing, absorption, transforms,
                          node repositioning, PubSub broadcasting,
                          pause/resume, rotate_passive, clear_collector

  tokene.ex            - Tokene struct: value, encoding, byte_size,
                          integrity, mass/1, dimensions/1, splittable?/1,
                          child_encoding/1, parent_encoding/1

  node.ex              - Node struct + behaviour: id, type, label,
                          position, config. Constructor new/2.

  node/
    emitter.ex         - Emitter: fire/1 -> execute source + chunk output
    emitter/
      shell.ex         - Shell source: System.cmd("sh", ["-c", cmd])
      manual.ex        - Manual source: pass-through text
      clock.ex         - Clock source: formatted current time
      file.ex          - File source: read file contents
      sequence.ex      - Sequence source: alpha, digits, or count

    collector.ex       - Collector: absorb/2, trigger/1, clear/1,
                          buffer_text/1, buffer_count/1, full?/1
    collector/
      echo.ex          - Echo action: return text as-is
      shell.ex         - Shell action: run command with buffered text
      reverse.ex       - Reverse action: reverse text
      upcase.ex        - Upcase action: uppercase text
      count.ex         - Count action: char + byte count
      display.ex       - Display action: passthrough for viewing

    transformer.ex     - Transformer: apply_effect/2 dispatches by effect type
                          splitter, crusher, heater, cooler, filter,
                          duplicator, painter

    passive.ex         - Passive: static geometry config
                          floor, wall, ramp, funnel, attractor, repeller

  chunker.ex           - Chunker behaviour: chunk/1, encoding/0
  chunker/
    bit.ex             - Individual bits (sand)
    byte.ex            - Individual bytes (gravel)
    rune.ex            - Grapheme clusters (pebbles)
    bpe.ex             - BPE tokens via tiktokenex (stones)
    ngram.ex           - Sliding window n-grams
    word.ex            - Delimiter-split words (bricks)
    phrase.ex          - Phrase boundaries (blocks)
    sentence.ex        - Sentence boundaries (boulders)

  world/
    snapshot.ex        - Save/load: JSON serialization, file I/O,
                          version checking, module name mapping

lib/quantok_web/
  live/
    world_live.ex      - Main LiveView: sidebar + topbar UI, canvas hook,
                          node spawn/delete, drag-to-reposition, hover menus,
                          fire/trigger/clear actions, save/load worlds

assets/js/quantok/
  world_hook.js        - LiveView hook: event queue for async init,
                          drag interaction, hover context menus,
                          physics-render sync loop, sensor detection
  renderer.js          - Three.js ortho scene: node meshes with pipe spouts,
                          tokene meshes with encoding colors, text textures,
                          hit testing, coordinate transforms
  physics.js           - Rapier2D wrapper: dynamic/kinematic/static bodies,
                          sensor zones, deterministic physics params

priv/worlds/           - Bundled example world configurations
  hello_world.json     - Simple emitter + collector demo
  date_pipeline.json   - Date emitters + ramp + splitter + collector

tiktokenex/            - Standalone pure Elixir BPE tokenizer
  lib/tiktokenex.ex    - Public API: encode, decode, encode_to_chunks, count
  lib/tiktokenex/
    ranks.ex           - Rank file loader, persistent_term cache
    pretokenizer.ex    - Regex pre-tokenization (tiktoken patterns)
    bpe.ex             - Core BPE merge algorithm
  priv/ranks/          - cl100k_base.tiktoken, o200k_base.tiktoken
```

## Tech Stack

| Layer         | Choice                          | Why                                 |
|---------------|---------------------------------|-------------------------------------|
| Backend       | Elixir 1.19, Phoenix 1.8       | LiveView, PubSub, GenServer         |
| Realtime      | Phoenix LiveView + push_event   | Bidirectional, no separate WS layer |
| Database      | SQLite (default) or Postgres    | SQLite for dev, Postgres for prod   |
| Rendering     | Three.js (ortho camera)         | 2D with real materials & lighting   |
| Physics       | Rapier2D (WASM)                 | Fast, sensors, force API            |
| Tokenizer     | Tiktokenex (pure Elixir)        | No NIFs, portable, extractable      |
| Quality       | Credo --strict, ExUnit          | 130+ tests, zero warnings           |
| Task runner   | just (justfile)                 | Unified DX commands                 |
| Issue tracker | beads (bd)                      | Git-backed, dependency-aware        |

## Test Coverage

```
130 tests, 0 failures
  - Tokene: struct, integrity, mass, dimensions, splitting, hierarchy
  - Chunkers: all 8 implementations with edge cases
  - Emitter: shell, manual, clock, file, sequence sources
  - Collector: absorption, buffer management, triggering, reverse/upcase/count
  - Transformer: all 7 effects (split, crush, heat, cool, filter, dup, paint)
  - Passive: shapes, force detection, solid detection
  - World: full integration - CRUD, firing, absorption, auto-trigger, PubSub
  - Snapshot: serialize, round-trip JSON, load_into, file I/O, version check

tiktokenex: 47 tests
  - BPE algorithm, rank loading, pre-tokenization
  - Round-trip encode/decode, reference vectors, edge cases
```

## Database

The Repo adapter is configurable — SQLite by default, Postgres when `DATABASE_URL` is set.

```
# SQLite (default, zero-config)
just dev

# Postgres (set DATABASE_URL)
DATABASE_URL=postgres://user:pass@localhost/quantok_dev mix phx.server
```

Config flow: `config.exs` sets `:ecto_adapter` to SQLite3. `runtime.exs` overrides
to Postgres when `DATABASE_URL` is present in prod. `Repo` reads the adapter at
compile time via `Application.compile_env/3`.

## Design Principles

1. **Server is truth, client is presentation.** The World GenServer owns all
   state. Client physics are cosmetic — if a tokene appears to land in a
   collector, the server decides whether it actually absorbs.

2. **No wires.** Connections happen through physics — proximity, gravity,
   collisions. This makes the system feel like a toy, not a flowchart tool.

3. **Chunking is the core mechanic.** The same data viewed at different
   granularities has fundamentally different physical properties. This is
   the insight that makes the sim interesting.

4. **Integrity creates depth.** Tokenes aren't just passive objects — they
   resist or yield to transformation based on their integrity. This creates
   emergent gameplay from simple rules.

5. **Deterministic by default.** Zero chaos in the default setup — tokenes
   drip from emitter pipes in order, fall straight down, land predictably.
   Randomness is opt-in through world configuration.

6. **Extractable libraries.** Tiktokenex is a standalone hex package candidate.
   The Chunker behaviour could also be extracted. Build general tools, not
   monolithic apps.
