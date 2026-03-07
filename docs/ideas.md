# Quantok Ideas & Design Notes

## Naming

- **Quantok**: project name (quantum + token, the quantization of data)
- **Tokene**: the fundamental unit - a chunk of data made physical
  (mineral/tangible feel, like a stone carved with glyphs)

## Core Concept

Data has mass. Information is physical. The act of chunking data into different
granularities changes its physical properties - bits are sand, words are bricks,
sentences are boulders. A BPE token is a precisely shaped stone.

---

## DX & Engineering Excellence

### Testing Strategy
- Property-based tests for chunkers: `chunk(x) |> join == x` for all inputs
- StreamData for fuzzing tokene operations (split then fuse = identity?)
- Benchmark suite for tiktokenex (compare against Python tiktoken)
- Integration test that runs a full emit->fall->collect cycle with real World GenServer
- Visual regression tests for Three.js rendering (screenshot comparison)

### CLI / Mix Tasks
- `mix quantok.demo` - start server with a pre-built demo world
- `mix quantok.bench` - run tiktokenex benchmarks
- `mix quantok.world.export <name>` - export a world to JSON
- `mix quantok.world.import <file>` - import a world from JSON
- `mix quantok.chunk <text> --encoding word` - chunk text from CLI (useful for debugging)

### Justfile Additions to Consider
- `just demo` - start with a demo world loaded
- `just bench` - run benchmarks
- `just chunk "hello world" word` - quick chunker test
- `just profile` - run with :fprof for performance analysis
- `just docs` - generate ExDoc documentation

### Code Quality
- Dialyzer/dialyxir for type checking (complement to credo)
- ExDoc for library documentation (especially tiktokenex)
- Boundary library for enforcing module dependencies
- CI pipeline: `just check` as the gate

---

## Tokene Integrity & Splitting

Every tokene has an integrity value (0.0 - 1.0) that determines how resistant
it is to breaking apart. The split hierarchy:

```
sentence (0.1) -> phrase (0.2) -> word (0.4) -> token (0.6) -> rune (0.8) -> byte (0.95) -> bit (1.0)
```

When a tokene breaks, it re-chunks at the next level down using the appropriate
chunker. A word-tokene splits into BPE tokens. A sentence splits into phrases.

### Advanced Integrity Ideas
- **Fatigue**: repeated transformer hits accumulate, eventually breaking even
  high-integrity tokenes. Like metal fatigue.
- **Annealing**: if a tokene survives a heater zone without breaking, its
  integrity actually increases (tempered by the heat).
- **Resonance**: certain frequencies of collision weaken specific encodings.
  A "word resonator" makes words more fragile without affecting bytes.
- **Composite tokenes**: fusing tokenes of different encodings creates a
  composite with mixed integrity (average? weighted?).

---

## Transformer Mechanics

Transformers modify tokenes through proximity (no wires/connections):

### Implemented
- **Splitter**: breaks tokene down one encoding level
- **Crusher**: shatters to individual bytes
- **Heater**: reduces integrity over time in zone
- **Cooler**: increases integrity over time in zone
- **Filter**: regex-based, only passes matching tokenes
- **Duplicator**: creates a copy alongside the original
- **Painter**: tags tokenes with color metadata

### Emergent Combos
- **Heater + Splitter**: heat softens, then splitter breaks. Without heater,
  high-integrity tokenes bounce off the splitter intact.
- **Cooler + Fuser**: cool hardens tokenes, fuser welds them together.
- **Filter + Collector**: selective absorption - only collect words matching "error".
- **Duplicator + Splitter**: clone then break = multiplication of information.
- **Painter + Filter**: paint red, then filter for red = tagging/routing system.

### Wild Transformer Ideas
- **Encryptor**: XORs tokene value with a key, changes it into "encrypted" encoding
- **Compressor**: combines repeated adjacent tokenes into one (run-length encoding)
- **Reverser**: reverses the tokene value (string reverse)
- **Hasher**: replaces value with its hash, irreversible transformation
- **Translator**: runs value through a translation API (tokene goes in English, comes out French)
- **Evaluator**: if tokene value is a valid expression, replaces with result ("2+2" -> "4")
- **Sampler**: probabilistically passes tokenes (50% pass rate = random filter)
- **Delay line**: holds tokenes for N ticks before releasing (creates timing patterns)
- **Mirror**: reflects tokene velocity (physics), creating bounce patterns
- **Gravity well**: like attractor but with proper inverse-square falloff
- **Merger**: combines N fine-grained tokenes into one coarser tokene
  (bytes -> word, words -> sentence). Inverse of splitter. See docs/collector-buffers.md.

---

## Visual Design Ideas

### Tokene Appearance by Encoding
| Encoding | Size   | Color       | Texture        | Feel          |
|----------|--------|-------------|----------------|---------------|
| bit      | 2px    | white/black | dot            | sand grain    |
| byte     | 6px    | cool blue   | square         | gravel        |
| rune     | 12px   | warm amber  | rounded rect   | pebble        |
| token    | 16px   | teal        | faceted rect   | cut stone     |
| ngram    | 14px   | cyan        | parallelogram  | tile          |
| word     | 24px   | green       | rounded rect   | brick         |
| phrase   | 40px   | orange      | wide rect      | plank         |
| sentence | 60px   | deep purple | large block    | boulder       |

### Integrity Visualization
- 1.0: solid, opaque, slight glow
- 0.7: hairline cracks visible
- 0.4: visible fractures, slightly transparent
- 0.1: heavily cracked, pulsing, about to shatter

### Node Visuals
- **Emitters**: upward-pointing funnel, glow pulses when firing,
  particles spray out with each tokene
- **Collectors**: downward-pointing funnel / open-top box,
  visible buffer slots that fill from left to right,
  pulse animation on absorb, flash on trigger
- **Transformers**: distinctive icons per type
  - Splitter: blade/wedge shape
  - Heater: flame icon, warm glow radius
  - Cooler: snowflake icon, cool glow radius
  - Filter: mesh/grid icon
- **Passives**: simple geometry with subtle material
  - Floors/walls: dark matte surfaces
  - Funnels: angled guides with metallic look
  - Attractors: pulsing circles with gravity well visual
  - Repellers: expanding rings, pushing visual

### Shader Ideas
- Distance field glow around force elements
- Particle trails on fast-moving tokenes
- Heat shimmer near heater zones
- Frost crystals near cooler zones
- Crack propagation shader for low-integrity tokenes

---

## Emitter Ideas

### Implemented
- **Shell**: runs a command, chunks stdout
- **Manual**: user text input, pass-through
- **Clock**: emits formatted time at intervals
- **Sequence**: emits items from a predefined list (e.g. A-Z)

### Planned
- **File**: reads a file, chunks contents
- **LLM**: streams from an LLM API, natural token boundaries

### Wild
- **Network**: listen on a port, emit packets as tokenes
- **Clipboard**: emit clipboard contents on paste
- **Microphone**: FFT analysis, emit frequency bands
- **Camera**: OCR on webcam feed, emit recognized text
- **RSS/Webhook**: emit incoming feed items
- **Git**: emit commit messages, diffs, file names
- **Process tree**: emit running process names/PIDs
- **Sensors**: temperature, CPU usage, disk I/O as tokenes
- **Music**: MIDI notes as tokenes, build a data-driven sequencer
- **Chaos emitter**: emits random bytes at random intervals
  (entropy source for the world)

---

## Collector Ideas

### Implemented
- **Echo**: returns buffer text as-is
- **Shell**: runs command with buffered text as argument
- **Reverse**: reverses buffer text
- **Upcase**: uppercases buffer text
- **Count**: returns character count
- **Display**: shows collected text (no processing)

### Planned
- **File**: writes to file on trigger
- **Concat**: reassembles into single tokene

### Wild
- **Sort**: reorders buffer before outputting (alphabetical, by size, by encoding)
- **Dedup**: only keeps unique tokene values
- **Accumulator**: concatenates forever, never triggers (display/log)
- **Threshold**: triggers when total byte_size exceeds a limit
- **Pattern**: triggers when buffer matches a regex
- **Validator**: checks if buffer is valid JSON/XML/YAML, only triggers if valid
- **Evaluator**: treats buffer as code, evaluates it (sandboxed!)
- **HTTP**: POSTs buffer contents to a URL on trigger
- **Clipboard**: copies to system clipboard
- **Speech**: text-to-speech on trigger (hear your data pipeline)
- **MIDI**: convert buffer bytes to MIDI notes (sonification)

---

## World Mechanics

### Implemented
- Configurable gravity vector {x, y}
- Pause/resume
- Node CRUD with PubSub broadcasting
- Floor, wall, ramp, funnel passives
- Drag-to-reposition nodes
- Hover context menus per node type

### Planned Passives
- **Attractor/Repeller**: force fields

### Wild World Ideas
- **Conveyor belts**: surfaces that apply lateral force to tokenes
- **Portals**: linked pairs that teleport tokenes between positions
- **Time zones**: regions where physics runs at different speeds
  (slow-mo zone for watching splits, fast-forward zone for throughput)
- **Magnets**: attract/repel by encoding type ("word magnet" pulls words,
  ignores bytes - creates automatic sorting)
- **Fluid zones**: areas with drag/viscosity, tokenes float instead of fall
- **Wind**: directional force field, like gravity but horizontal
  (configurable, animated, turbulent)
- **Bouncy zones**: high-restitution regions, tokenes bounce wildly
- **Vacuum zones**: zero gravity regions, tokenes drift
- **Conveyor networks**: linked conveyors create automated paths
- **Teleporter chains**: A->B->C->A creates a loop

---

## Architecture Ideas

### Server-Side Physics (Deterministic Simulation)

Currently physics runs client-side in Rapier WASM. This limits:
- No two clients see the same simulation
- Server can't reason about physical position
- Multiplayer requires physics state sync

**Proposal**: Run Rapier on the server via Rustler NIF (Rapier is Rust-native).
Server steps physics at fixed tick rate, broadcasts position snapshots. Client
becomes a pure renderer with interpolation.

- Server would know exactly which slot a tokene is in
- Enables deterministic replays and recording
- Hybrid option: server runs authoritative physics for game logic (collection,
  transformation), client runs visual interpolation from server snapshots.
  Like netcode in multiplayer games.
- Cost: bandwidth for position updates, latency on drag interactions

### Event Sourcing

Instead of mutable World GenServer state, make every action an event:

```elixir
{:emitted, emitter_id, tokenes, timestamp}
{:absorbed, collector_id, tokene_id, slot_index, timestamp}
{:transformed, transformer_id, old_id, new_ids, timestamp}
{:moved, node_id, old_pos, new_pos, timestamp}
```

Benefits:
- **Replay**: rewind and replay any world session
- **Undo**: pop events to reverse actions
- **Recording**: save sessions as recordings, play back for demos
- **Time travel**: scrub through world history with a timeline slider
- **Debugging**: full audit trail of everything that happened

Current GenServer state becomes a projection (fold over events). Natural
fit for Elixir/OTP. The World struct is just `Enum.reduce(events, %World{}, &apply/2)`.

### Pipes and Wiring (Explicit Data Flow)

Currently data flow is implicit — tokenes fall via gravity and happen to hit
collectors. This is the sandbox charm, but limits intentional pipeline design.

**Proposal**: Optional explicit pipes between nodes. An emitter output can be
wired to a collector input. Tokenes travel through the pipe (rendered as a
tube/channel) instead of free-falling.

- Pipes have physics too — tokenes slide along them, affected by angle
- Pipe junctions for splitting flow
- Pipe valves for gating flow
- Unwired nodes still use gravity (sandbox mode)
- Bridges "toy" and "tool" — build reliable pipelines OR chaotic sandboxes
- Essentially: Quantok as a visual dataflow language (see below)

### Quantok as a Dataflow Language

If you squint, Quantok is becoming a visual dataflow language:
- Emitters = sources
- Collectors = sinks
- Transformers = operators
- Passives = routing
- Pipes = edges

This is MAX/MSP or Pure Data for text/data instead of audio. Or LabVIEW for
information theory. The physics sandbox is the fun entry point, but the
underlying model is a legitimate dataflow graph.

The question: lean into this (formal graph semantics, deterministic execution,
export-to-code) or keep it as emergent behavior from physics. Both are valid.
Physics-first is more novel and fun. Graph-first is more useful as a tool.

Could support both: a "physics mode" (sandbox, gravity, chaos) and a "graph mode"
(wired, deterministic, no physics, data flows through edges at defined rates).
Same nodes, same transformers, different execution model.

---

## Information-Theoretic Physics

### Shannon Entropy as Temperature

`H(tokene) = -sum(p(c) * log2(p(c)))` over character frequency distribution.

- "hello" has low entropy (repeated 'l') → cold, settles easily
- Random bytes have high entropy → hot, moves faster, harder to contain
- Computed once on creation, stored in metadata
- Physics maps: entropy → linear velocity multiplier, or → restitution

### Kolmogorov Complexity as Density

Use `zlib.deflate(value).length / value.length` as compression ratio proxy.

- Highly compressible data is "fluffy" (low density, floats up)
- Incompressible data is "dense" (sinks fast, heavy)
- Creates natural stratification: compressed data settles, redundant floats
- Computed via `:zlib.compress/1` in Elixir, ratio stored as metadata

### Mutual Information as Attraction

Tokenes with similar content experience attractive force:
- Shared substrings, low edit distance → attraction
- Completely different content → no force
- Similar data physically clusters together — emergent sorting
- Could use Jaccard similarity on character bigrams (fast, no external deps)
- Force magnitude: `F = k * similarity(a, b) / distance^2`

### Token Probability as Weight (BPE-specific)

If we have access to a model's vocabulary frequencies:
- Common tokens (high frequency) are "light" — expected, ordinary
- Rare tokens (low frequency) are "heavy" — surprising, unusual
- Rare words literally weigh more in the physics simulation
- tiktokenex could expose token rank/frequency alongside encoding

---

## BPE Tokenization as First-Class Mechanic

tiktokenex already exists. BPE is the most interesting encoding because it's
how LLMs actually see text.

### Token ID Visualization
Show BPE token ID alongside text value. Token 15339 = "hello". Makes
tokenization tangible — see how LLMs see text.

### Vocabulary-Aware Collectors
A collector configured with a specific BPE vocabulary only accepts tokens
from that vocabulary. GPT-4 tokens vs Claude tokens vs Llama tokens —
different vocabularies, different physical shapes. Same text, different
tokenizations, different physics.

### Tokenization Comparison
Emit the same text through two emitters with different chunkers (word vs BPE
vs byte). Watch how the same sentence becomes different physical objects.
Side-by-side comparison of chunking strategies, made visceral.

### Sub-word Visualization
BPE tokens often split words at surprising boundaries. "unfortunately" might
become ["un", "fortunately"] or ["un", "for", "tun", "ately"]. Watching
these splits happen physically — splitter breaks a word, and the BPE
boundaries are where it fractures — is a powerful teaching tool.

---

## Tokene Lifecycle and Decay *(implemented)*

### Time-Based Decay *(implemented)*
Encoding-based half-lives: sentence 8s, phrase 15s, word 30s, token 45s,
rune 60s, byte 120s, bit infinite. Three config layers: world defaults →
emitter overrides → encoding base. Toggle decay globally from topbar.

Client computes integrity per-frame: `initial * 0.5^(elapsed/half_life)`.
Visual: color desaturation (lerp toward grey), opacity fade, pulse when
near death (< 15% integrity).

### Shatter Behaviors *(implemented)*
When integrity drops below 5%, tokene shatters with configured behavior:
- **:split** — rechunk at child encoding (sentence→phrases, word→tokens)
- **:dissolve** — vanish silently
- **:explode** — burst to byte fragments with random impulse
- **:fossilize** — freeze as static body, decay disabled

Bits are indestructible (always fossilize). Server-authoritative shatter logic.

### Future: Fossil Record
Shattered tokene remains (bits) accumulate at the bottom of the world.
Over time, layers build up like sediment. The world has a geological
history of data. Dig through layers to see what was emitted hours ago.

---

## World Templates and Circuits

Pre-built node arrangements that solve specific problems, loadable from
`priv/worlds/` as JSON snapshots:

### Teaching Templates
- **Word counter**: `emitter(word) → collector(word, action:count)`
- **Tokenizer demo**: same text through word/byte/BPE emitters side by side
- **Split cascade**: `emitter(sentence) → splitter → splitter → collector(byte)`

### Functional Circuits
- **Frequency analyzer**: `emitter(word) → duplicator → [N filter+collector pairs]`
  each collector filters for a different word, counts hits
- **Encryption pipeline**: `emitter → XOR transformer → collector`
- **Compression visualizer**: emit sentence, split to bytes, count = uncompressed
  size. Add compressor transformer, count output = compressed size. Ratio visible.
- **Sort pipeline**: emit words, collect into sorted buffer, re-emit in order

### Puzzle Templates
- "Route date output to echo collector using only 2 ramps"
- "Split this sentence to individual characters with minimal transformers"
- "Build a pipeline that reverses word order of a sentence"
- "Create a feedback loop: collector output feeds back into emitter"

---

## Scripting and Programmable Nodes

Let users define custom node behavior:

### Elixir Snippet Transformer
```elixir
# Custom transformer: ROT13
def transform(tokene) do
  new_value = String.to_charlist(tokene.value)
    |> Enum.map(&rot13_char/1)
    |> List.to_string()
  %{tokene | value: new_value}
end
```

### Expression Evaluator
Simple expression language for inline transforms:
- `value | upcase` — uppercase
- `value | reverse` — reverse string
- `value | take(3)` — first 3 characters
- `value | replace("a", "b")` — substitution
- Composable: `value | upcase | reverse | take(5)`

### Visual Programming
Wire up built-in operations as a custom composite node. A "macro node"
that contains a sub-graph of transformers. Collapse complexity.

---

## Rendering Upgrades

### Instanced Rendering (High Priority)
Each tokene is currently its own mesh + texture. With 500+ tokenes this tanks.
Three.js `InstancedMesh` renders thousands of similar objects in one draw call.

- Group by encoding type: all words = one instanced mesh
- Per-instance attributes: position, rotation, color tint, UV offset
- Texture atlas for text: pre-render unique texts into one atlas
- Target: 2000+ tokenes at 60fps (currently ~300)

### troika-three-text (High Priority)
SDF text rendering — crisp at any zoom, single draw call for all text.
Huge upgrade from canvas textures (blurry when zoomed, expensive to create).

### Post-Processing
- **Bloom/glow**: UnrealBloomPass for emitter glow, force field visuals.
  Few lines of Three.js code, dramatic visual improvement.
- **Particle systems**: THREE.Points for emit/absorb particle effects.
  GPU-accelerated, lightweight.

### Camera Controls
- Zoom in/out (mouse wheel → adjust ortho frustum)
- Pan (middle-click drag or shift+drag)
- Minimap for large worlds
- Focus-on-node (double-click node to center camera on it)

---

## Algorithms & Research

### BPE Optimization
- Current tiktokenex is correct but O(n^2) per chunk (finds min pair each pass)
- Research: use a priority queue (sorted set of pairs by rank) for O(n log n)
- Even better: tiktoken's actual algorithm uses a sorted merge approach
- For our use case (small inputs), current perf is fine. Optimize if needed.

### Physics Optimization
- **Spatial hashing** for collision broadphase (Rapier does this internally)
- **Sleep/wake**: Rapier can sleep static bodies, wake on contact
- **LOD system**: far-away tokenes rendered as colored dots, no text
- **Object pooling**: reuse Three.js meshes and Rapier bodies
- **Texture atlas**: batch all tokene text textures into one atlas

### Interesting Algorithm Directions
- **Information entropy visualization**: color tokenes by Shannon entropy
  of their value. High-entropy chunks glow differently than low-entropy ones.
- **Compression ratio as density**: compressed size / raw size determines
  how "dense" a tokene is. Dense tokenes sink faster, light ones float.
- **Kolmogorov complexity proxy**: use gzip ratio as a proxy for complexity.
  Complex tokenes could have different physical properties.
- **Edit distance fields**: tokenes near each other that have low edit distance
  experience mutual attraction (similar data clusters together).
- **Markov chain emitters**: instead of running a command, generate text from
  a Markov model trained on input. Infinite emitter.
- **Cellular automata**: tokene grid where rules determine splitting/fusing.
  Conway's Game of Life but with data.

### Rendering Research
- **SDF text rendering**: signed distance field fonts for crisp text at any zoom.
  Three.js has troika-three-text for this. Better than canvas textures.
- **Instanced rendering**: Three.js InstancedMesh for thousands of similar tokenes.
  One draw call for all byte-encoding tokenes, one for all word-encoding, etc.
- **Bloom/glow**: post-processing pass for emitter glow, force field visuals.
  Three.js EffectComposer + UnrealBloomPass.
- **Particle systems**: Three.js Points for emit/absorb particle effects.
  Lightweight, GPU-accelerated.

---

## Game/Puzzle Mode Ideas

### Puzzle Challenges
- "Route the output of `date` to the echo collector using only 2 ramps"
- "Split this sentence into individual characters using minimal transformers"
- "Filter out all numbers and collect only the letters"
- "Build a pipeline that reverses the word order of a sentence"
- "Create a feedback loop: collector output feeds back into an emitter"

### Sandbox Achievements
- First tokene collected
- 100 tokenes collected
- Build a 5-stage pipeline
- Use every transformer type in one world
- Create a tokene loop (output feeds input)
- Fill a 64-slot buffer
- Split a sentence all the way to bits

### Competitive (Multiplayer)
- Race to collect a target string from falling tokenes
- Build the most efficient pipeline (fewest nodes, fastest throughput)
- Sabotage opponent's pipeline with repellers/heaters
- Co-op: each player controls different node types

---

## Philosophical / Art Directions

### Data as Material
What if we took the metaphor further? Data isn't just physical, it has
material properties:
- **Conductivity**: some tokenes pass through filters easily
- **Magnetism**: data with similar content clusters together
- **Temperature**: recently created tokenes are "hot" (high energy, low integrity)
- **Age**: tokenes darken over time, old data looks weathered
- **Radioactive decay**: tokenes slowly lose integrity over time even without
  heaters. Entropy is the default direction.

### Information Archaeology
A world where ancient tokenes have been falling for hours. Layers of data
sediment. Dig through the layers. What did the system emit 3 hours ago?
The world becomes a geological record of computation.

### Data Sonification
Every collision, absorption, split, and emission makes a sound.
The world becomes a musical instrument. Different encodings have
different timbres. A busy pipeline is a symphony of data.

### Living Systems
What if tokenes could reproduce? A tokene that lands in a "growth zone"
duplicates with mutations. Over time, you get evolution of data.
Natural selection based on which tokenes survive the pipeline.
Genetic programming, but visible and physical.
