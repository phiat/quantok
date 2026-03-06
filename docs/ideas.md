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

### Planned
- **File**: reads a file, chunks contents
- **Clock**: emits formatted time at intervals
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

### Planned
- **Display**: shows collected text in a panel (no action)
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

### Planned Passives
- **Floor/Wall/Ramp/Funnel**: static collision geometry
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
