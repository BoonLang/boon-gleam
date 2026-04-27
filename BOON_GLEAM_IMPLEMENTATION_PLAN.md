# Boon-Gleam Architecture and Implementation Plan

Place this file at the root of the future `boon-gleam` repository as:

```text
AGENTS.md
```

or:

```text
BOON_GLEAM_IMPLEMENTATION_PLAN.md
```

This is a clean-slate plan for a Gleam implementation and codegen backend for Boon.

---

## 0. Executive summary

`boon-gleam` explores Boon as a typed, distributed, durable, full-stack reactive language on Gleam.

The goal is not to beat Zig/Pony/C/Rust at raw native rendering speed. The goal is to use Gleam and the BEAM runtime for:

```text
typed generated Boon state machines
actor-based app sessions
supervised runtime processes
durable event logs and snapshots
terminal playgrounds
playable terminal examples such as Pong and Arkanoid
HTTP/WebSocket backend sessions
optional web frontends through Gleam JavaScript + Lustre
```

The core model is:

```text
Boon source project
  -> Gleam Boon compiler frontend
  -> Boon IR
  -> generated Gleam core
  -> target adapter

Targets:
  terminal_tui_beam
  durable_backend_beam
  web_frontend_js
```

The core generated app must be pure and deterministic:

```text
init(context) -> State

update(state, event) -> #(State, List(Effect))

view(state) -> DocumentSnapshot | TerminalCanvasSnapshot | SceneSnapshot
```

The BEAM actor/runtime layers own:

```text
message ordering
timers
persistence
durability
supervision
backend client sessions
terminal event loops
```

The generated Boon core should not directly depend on OTP, HTTP, database, terminal, or browser packages unless that target adapter requires it.

---

## 1. Why Gleam?

Gleam is interesting for Boon because it targets both:

```text
Erlang/BEAM
JavaScript
```

This makes it a good candidate for a Boon backend that wants both:

```text
durable distributed server-side state
frontend/client-side rendering experiments
```

Gleam is statically typed and functional, while the BEAM target gives access to Erlang/OTP style actors, supervision, timers, distributed processes, and long-running fault-tolerant applications.

This fits Boon well:

```text
Boon LINK event        -> typed message/event
Boon HOLD state        -> actor/session state
Boon Timer/interval    -> scheduled message
Boon Router/go_to      -> route event/effect
Boon document snapshot -> view-model projection
Boon terminal canvas   -> TUI frame projection
Boon expected files    -> deterministic event script
```

The strongest motivation for `boon-gleam` is:

```text
Boon as a durable, distributed, reactive app language.
```

The second motivation is:

```text
Boon as a terminal/game playground on BEAM.
```

The third motivation is:

```text
Boon as a possible shared frontend/backend language through Gleam JS and Gleam BEAM targets.
```

---

## 2. Non-goals

Do not turn this repository into a graphics engine or native systems runtime.

Out of scope for this repository:

```text
Raybox
Sokol
SDL
raylib
WebGPU
WGSL
Slang
Dawn
wgpu-native
freestanding Wasm
3D rendering
3D printing
physical GPU rendering
native binary codegen
Pony codegen
Zig codegen
Rust codegen
```

`boon-gleam` may later talk to a renderer or frontend through snapshots and WebSockets, but it does not implement Raybox.

---

## 3. Fixed initial stack

Use this stack for the first implementation.

### Language and build

```text
Language:
  Gleam

Primary runtime:
  Erlang/BEAM

Secondary runtime:
  JavaScript target for web frontend experiments

Build tool:
  gleam
```

### Core dependencies

Use these as the initial dependencies:

```text
gleam_stdlib
gleam_erlang
gleam_otp
gleam_json
```

### Terminal frontend

Use this stack first:

```text
Etch:
  terminal event/output backend

gleam_community_ansi:
  fallback ANSI styling and debugging output
```

Do not start by using multiple TUI frameworks. Etch is the primary terminal backend for v0.

### Backend server

Use this stack first:

```text
Mist:
  HTTP/WebSocket server

gleam_otp:
  actors, supervisors, process messaging

gleam_json:
  protocol encoding/decoding
```

Do not start with a large web framework. Add Wisp only if direct Mist routing becomes painful.

### Durable storage

Use two storage implementations:

```text
Local development store:
  DETS/ETS-backed store, through shelf/slate/bravo if practical

Production durable store:
  PostgreSQL through pog
```

The store interface must be abstract. The first durable backend may use local DETS/ETS; the Postgres backend is required before declaring the distributed backend complete.

### Web frontend

Use:

```text
Lustre:
  Gleam web frontend framework
```

The Lustre target is optional for early terminal/backend milestones but part of the long-term architecture.

---

## 4. Repository layout

Use this layout:

```text
boon-gleam/
  AGENTS.md
  BOON_GLEAM_IMPLEMENTATION_PLAN.md
  README.md
  gleam.toml
  manifest.toml

  examples/
    upstream/
      minimal/
      hello_world/
      counter/
      todo_mvc/
      ...

    terminal/
      pong/
        pong.bn
        pong.expected
      arkanoid/
        arkanoid.bn
        arkanoid.expected

  fixtures/
    corpus_manifest.json
    expected_action_schema.json
    protocol_schema.json
    backend_api_schema.json

  src/
    boongleam.gleam

    cli/
      command.gleam
      args.gleam
      command_tui.gleam
      command_play.gleam
      command_compile.gleam
      command_codegen.gleam
      command_serve.gleam
      command_verify.gleam
      command_verify_all.gleam
      command_bench.gleam

    frontend/
      source_file.gleam
      span.gleam
      diagnostic.gleam
      token.gleam
      lexer.gleam
      parser.gleam
      ast.gleam

    project/
      project.gleam
      project_loader.gleam
      module_resolver.gleam
      virtual_file_system.gleam
      upstream_importer.gleam
      corpus_manifest.gleam

    lowering/
      resolver.gleam
      hir.gleam
      flow_ir.gleam
      type_facts.gleam
      dependency_graph.gleam

    codegen/
      gleam_writer.gleam
      name_mangle.gleam
      codegen_context.gleam
      generate_project.gleam
      generate_core_types.gleam
      generate_state.gleam
      generate_update.gleam
      generate_view.gleam
      generate_effects.gleam
      generate_encoders.gleam
      generate_terminal_target.gleam
      generate_backend_target.gleam
      generate_lustre_target.gleam

    runtime/
      boon_value.gleam
      document.gleam
      scene.gleam
      style.gleam
      event.gleam
      effect.gleam
      terminal_canvas.gleam
      semantic_tree.gleam
      encode.gleam
      decode.gleam
      virtual_clock.gleam
      metrics.gleam

    terminal/
      tui_app.gleam
      tui_model.gleam
      tui_update.gleam
      tui_view.gleam
      etch_backend.gleam
      terminal_canvas_renderer.gleam
      terminal_input.gleam
      terminal_diff.gleam
      keyboard.gleam
      game_loop.gleam
      frame_timer.gleam

    backend/
      server.gleam
      routes.gleam
      websocket.gleam
      protocol.gleam
      app_supervisor.gleam
      session_supervisor.gleam
      session_registry.gleam
      session_actor.gleam
      client_actor.gleam
      timer_actor.gleam
      pubsub.gleam
      event_log.gleam
      snapshot_store.gleam
      store.gleam
      store_memory.gleam
      store_local.gleam
      store_postgres.gleam

    web/
      lustre_app.gleam
      lustre_update.gleam
      lustre_view.gleam
      websocket_client.gleam

    verify/
      expected_parser.gleam
      expected_runner.gleam
      semantic_query.gleam
      terminal_frame_query.gleam
      backend_verify.gleam
      durability_verify.gleam
      verification_report.gleam

    bench/
      bench_runner.gleam
      bench_report.gleam

    support/
      json.gleam
      path.gleam
      stable_hash.gleam
      text_builder.gleam
      process.gleam
      time.gleam
      result.gleam

  generated/
    .gitkeep

  build/
    generated/
    reports/
    cache/
    state/
```

---

## 5. Required commands

The command-line tool is:

```text
boongleam
```

Because Gleam normally runs through `gleam run`, support these commands:

```bash
gleam run -- help
gleam run -- import-upstream --source ../boon --out examples/upstream
gleam run -- manifest

gleam run -- compile examples/upstream/counter
gleam run -- codegen examples/upstream/counter
gleam run -- verify examples/upstream/counter
gleam run -- verify-all

gleam run -- tui
gleam run -- play examples/terminal/pong
gleam run -- play examples/terminal/arkanoid

gleam run -- serve examples/upstream/todo_mvc --store local --port 8080
gleam run -- serve examples/upstream/todo_mvc --store postgres --port 8080

gleam run -- bench examples/terminal/pong
gleam test
```

The early product should be usable as:

```bash
gleam run -- play examples/terminal/pong
```

and:

```bash
gleam run -- serve examples/upstream/todo_mvc --store local
```

---

## 6. Source-of-truth corpus

Import examples from the upstream Boon repository:

```text
https://github.com/BoonLang/boon
```

Initial import path:

```text
playground/frontend/src/examples/
```

Also include terminal examples from `boon-zig` or create local Boon terminal examples if they are not present upstream:

```text
examples/terminal/pong
examples/terminal/arkanoid
```

The corpus manifest is immutable source metadata:

```text
fixtures/corpus_manifest.json
```

Verification reports are generated separately:

```text
build/reports/verify-all.json
build/reports/<example-name>.json
```

Manifest entry:

```json
{
  "name": "counter",
  "kind": "single_file",
  "entry_file": "counter.bn",
  "files": ["counter.bn"],
  "expected": "counter.expected",
  "targets": ["semantic", "terminal", "backend"],
  "phase": "events"
}
```

Terminal game entry:

```json
{
  "name": "pong",
  "kind": "single_file",
  "entry_file": "pong.bn",
  "files": ["pong.bn"],
  "expected": "pong.expected",
  "targets": ["terminal_canvas"],
  "phase": "terminal_games"
}
```

---

## 7. Compiler pipeline

The compiler pipeline is:

```text
ProjectLoader
  -> Lexer
  -> Parser
  -> AST
  -> ModuleResolver
  -> NameResolver
  -> HIR
  -> FlowIR
  -> TypeFacts
  -> GleamCodegen
```

### 7.1 Frontend

The frontend is implemented in Gleam.

It must produce diagnostics with:

```text
file path
line
column
span start
span end
message
optional help text
```

Compiler diagnostics must be usable by:

```text
terminal TUI
backend API
web frontend
verification reports
```

### 7.2 HIR

HIR is syntax-directed and close to Boon.

HIR keeps source information for diagnostics and generated-code comments.

### 7.3 FlowIR

FlowIR is the target-independent representation used for codegen.

FlowIR must make these concepts explicit:

```text
HOLD cells
LINK ports
timers
router reads/writes
persistence reads/writes
document root
scene root
terminal canvas root
event handlers
pure helper functions
list transformations
conditionals
pattern matching
module imports
build-file side effects
```

The generated Gleam code must not need to understand raw Boon syntax.

---

## 8. Generated Gleam architecture

Generate one Gleam package per Boon project.

Generated layout:

```text
build/generated/counter/
  gleam.toml
  src/
    generated_counter.gleam
    generated_counter/types.gleam
    generated_counter/state.gleam
    generated_counter/event.gleam
    generated_counter/effect.gleam
    generated_counter/update.gleam
    generated_counter/view.gleam
    generated_counter/encode.gleam
    generated_counter/decode.gleam
    generated_counter/terminal_target.gleam
    generated_counter/backend_target.gleam
    generated_counter/lustre_target.gleam
```

### 8.1 Generated core functions

Every generated app exports:

```gleam
pub fn init(context: InitContext) -> State

pub fn update(state: State, event: Event) -> #(State, List(Effect))

pub fn view(state: State) -> Snapshot
```

Where:

```gleam
pub type Snapshot {
  DocumentSnapshot(Document)
  SceneSnapshot(Scene)
  TerminalCanvasSnapshot(TerminalCanvas)
  SemanticSnapshot(SemanticTree)
}
```

### 8.2 Generated state

Prefer typed generated state.

Example:

```gleam
pub type State {
  State(
    count: Int,
    route: String,
    todos: List(Todo),
  )
}

pub type Todo {
  Todo(
    id: Int,
    title: String,
    completed: Bool,
    editing: Bool,
  )
}
```

Use dynamic fallback values only where the compiler cannot yet specialize.

### 8.3 Generated events

Generate typed events.

Example:

```gleam
pub type Event {
  Press(link_id: String)
  Click(link_id: String)
  ChangeText(link_id: String, text: String)
  KeyDown(link_id: String, key: Key)
  TimerTick(timer_id: String, now_ms: Int)
  RouteTo(path: String)
  TerminalKey(key: Key)
  TerminalResize(width: Int, height: Int)
}
```

Do not make all generated events a stringly typed map.

### 8.4 Generated effects

Effects are target-neutral.

```gleam
pub type Effect {
  PersistWrite(key: String, value: String)
  PersistDeletePrefix(prefix: String)
  StartTimer(id: String, interval_ms: Int)
  StopTimer(id: String)
  RouteTo(path: String)
  LogInfo(message: String)
  LogError(message: String)
}
```

Target adapters interpret effects.

The pure generated `update` function must not perform IO directly.

---

## 9. Runtime snapshot model

The shared runtime defines these snapshot types.

### 9.1 Semantic tree

```gleam
pub type SemanticNode {
  SemanticNode(
    id: String,
    role: Role,
    text: String,
    value: String,
    placeholder: String,
    visible: Bool,
    focused: Bool,
    hovered: Bool,
    checked: Option(Bool),
    disabled: Bool,
    selected: Bool,
    outline_visible: Bool,
    input_typeable: Bool,
    children: List(SemanticNode),
  )
}
```

Roles:

```text
document
scene
text
paragraph
container
stack
button
text_input
checkbox
select
slider
svg
svg_circle
terminal_canvas
terminal_cell
link
hidden_label
reference
debug_value
```

### 9.2 Terminal canvas

```gleam
pub type TerminalCanvas {
  TerminalCanvas(
    width: Int,
    height: Int,
    cells: List(TerminalCell),
  )
}

pub type TerminalCell {
  TerminalCell(
    x: Int,
    y: Int,
    text: String,
    fg: Colour,
    bg: Colour,
    bold: Bool,
  )
}
```

Terminal game examples render through `TerminalCanvas`.

### 9.3 Document and scene

Documents and scenes are semantic snapshots, not pixel renderings.

```gleam
pub type Document {
  Document(root: SemanticNode)
}

pub type Scene {
  Scene(
    root: SemanticNode,
    lights: List(LightSummary),
    geometry: GeometrySummary,
  )
}
```

`Scene` exists so examples like physical TodoMVC can be represented semantically. Visual physical rendering is not part of this repo.

---

## 10. Terminal TUI architecture

The terminal TUI is a first-class frontend.

### 10.1 Modes

Support these modes:

```text
boongleam tui
  full playground interface with sidebar, source, preview, logs

boongleam play examples/terminal/pong
  direct full-screen game mode

boongleam play examples/terminal/arkanoid
  direct full-screen game mode
```

### 10.2 Full playground layout

The full TUI playground has panes:

```text
┌──────────────────────────────────────────────────────────┐
│ boon-gleam | example: counter | target: terminal/backend │
├───────────────┬─────────────────────────┬────────────────┤
│ Examples      │ Source / Generated IR   │ Preview        │
│               │                         │                │
│ minimal       │ counter.bn              │ semantic tree  │
│ counter       │                         │ or canvas      │
│ pong          │                         │                │
│ arkanoid      │                         │                │
├───────────────┴─────────────────────────┴────────────────┤
│ log / diagnostics / metrics                               │
└──────────────────────────────────────────────────────────┘
```

Keyboard shortcuts:

```text
q          quit
r          run/reload
b          build/codegen
e          run expected
p          play preview if terminal canvas
tab        switch panes
enter      activate selected item
f          focus filter/search
?          help
```

### 10.3 Direct play mode

Direct play mode hides compiler UI and runs the generated app:

```bash
gleam run -- play examples/terminal/pong
```

Requirements:

```text
full-screen terminal
raw/cbreak key input through Etch
frame timer
ANSI diff rendering
terminal restored on exit
headless mode for verification
```

### 10.4 Terminal game event loop

For Pong/Arkanoid:

```text
keyboard event
  -> Event.TerminalKey
timer tick
  -> Event.TimerTick
resize
  -> Event.TerminalResize

state + event
  -> generated update
  -> new state + effects
  -> generated view
  -> TerminalCanvas
  -> Etch renderer
```

Do not use an actor per ball/brick/paddle. Use one app session actor or process state machine.

---

## 11. Distributed durable backend architecture

The backend target runs on BEAM.

### 11.1 Supervision tree

Use this supervision shape:

```text
BoonGleamAppSupervisor
  ├─ StoreSupervisor
  │   ├─ EventLogStore
  │   └─ SnapshotStore
  ├─ SessionRegistry
  ├─ SessionSupervisor
  │   ├─ SessionActor(project_id, session_id)
  │   ├─ SessionActor(project_id, session_id)
  │   └─ ...
  ├─ ClientSupervisor
  │   ├─ WebSocketClientActor
  │   └─ ...
  ├─ TimerSupervisor
  │   └─ TimerActor
  └─ WebServer
```

### 11.2 Session actor

Each app session has a single actor.

State:

```text
project_id
session_id
revision
generated app State
route
timers
connected clients
last snapshot
store handle
metrics
```

Messages:

```gleam
pub type SessionMessage {
  ApplyEvent(event_id: String, event: Event, reply_to: Subject(SessionReply))
  GetSnapshot(reply_to: Subject(SessionReply))
  Subscribe(client: Subject(ServerToClient))
  Unsubscribe(client_id: String)
  TimerDue(timer_id: String, now_ms: Int)
  Restore(reply_to: Subject(SessionReply))
  Stop
}
```

### 11.3 Event-sourced durability

Use event sourcing.

For each accepted UI/runtime event:

```text
1. Receive event with unique event_id and expected revision.
2. Validate expected revision or reject/conflict.
3. Append event to durable event log.
4. Apply generated update(state, event).
5. Interpret effects.
6. Save snapshot if snapshot interval is reached.
7. Increment revision.
8. Broadcast snapshot to subscribers.
```

Crash recovery:

```text
1. Load latest snapshot.
2. Load events after snapshot revision.
3. Replay events through generated update.
4. Restore timers/routes.
5. Resume session actor.
```

Idempotency:

```text
event_id must be unique per session.
duplicate event_id returns previous result or duplicate diagnostic.
```

### 11.4 Stores

Define a store behavior/interface:

```gleam
pub type Store {
  Store(
    append_event: fn(SessionId, StoredEvent) -> Result(Nil, StoreError),
    load_events_after: fn(SessionId, Int) -> Result(List(StoredEvent), StoreError),
    save_snapshot: fn(SessionId, StoredSnapshot) -> Result(Nil, StoreError),
    load_latest_snapshot: fn(SessionId) -> Result(Option(StoredSnapshot), StoreError),
    mark_event_result: fn(SessionId, String, EventResult) -> Result(Nil, StoreError),
  )
}
```

Implementations:

```text
store_memory:
  tests only

store_local:
  DETS/ETS-backed local dev store

store_postgres:
  production durable store through pog
```

### 11.5 PostgreSQL schema

Initial schema:

```sql
create table boon_sessions (
  project_id text not null,
  session_id text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  current_revision bigint not null,
  primary key (project_id, session_id)
);

create table boon_events (
  project_id text not null,
  session_id text not null,
  revision bigint not null,
  event_id text not null,
  event_json jsonb not null,
  created_at timestamptz not null,
  primary key (project_id, session_id, revision),
  unique (project_id, session_id, event_id)
);

create table boon_snapshots (
  project_id text not null,
  session_id text not null,
  revision bigint not null,
  snapshot_json jsonb not null,
  created_at timestamptz not null,
  primary key (project_id, session_id, revision)
);
```

---

## 12. HTTP and WebSocket API

Use JSON protocols first.

### 12.1 HTTP endpoints

```text
GET  /health
GET  /projects
POST /projects
GET  /projects/:project_id
POST /projects/:project_id/compile
POST /projects/:project_id/sessions
GET  /projects/:project_id/sessions/:session_id/snapshot
GET  /projects/:project_id/sessions/:session_id/events
POST /projects/:project_id/sessions/:session_id/clear
```

### 12.2 WebSocket protocol

Path:

```text
/ws/projects/:project_id/sessions/:session_id
```

Client to server:

```json
{"type":"subscribe"}
{"type":"event","event_id":"uuid","expected_revision":12,"event":{"type":"click","link_id":"todo.add"}}
{"type":"get_snapshot"}
{"type":"ping"}
```

Server to client:

```json
{"type":"snapshot","revision":13,"snapshot":{...}}
{"type":"event_ack","event_id":"uuid","revision":13}
{"type":"event_reject","event_id":"uuid","reason":"revision_conflict"}
{"type":"diagnostic","diagnostic":{...}}
{"type":"pong"}
```

Rules:

```text
One session actor is the source of truth.
All clients for a session receive snapshots after accepted events.
The server never trusts client-side state.
The server may reject stale expected_revision.
```

---

## 13. Web frontend architecture

The web frontend target uses Gleam JavaScript + Lustre.

### 13.1 Two modes

Support two web modes eventually.

#### Local JS mode

```text
Generated Gleam JS runs update/view locally.
No durable backend.
Useful for demos and simple examples.
```

#### Durable client mode

```text
Lustre frontend connects to BEAM backend WebSocket.
Backend session actor is authoritative.
Frontend sends events and renders snapshots.
```

The durable client mode is more important.

### 13.2 Shared generated code

Shared target-neutral generated modules:

```text
types.gleam
event.gleam
snapshot.gleam
encode.gleam
decode.gleam
view_model.gleam
```

BEAM-only modules must not be imported by JS target.

Backend-only modules:

```text
backend_target.gleam
session_actor.gleam
store adapters
```

Frontend-only modules:

```text
lustre_target.gleam
lustre_view.gleam
websocket_client.gleam
```

---

## 14. Terminal/backend/frontend target split

The generated app has target adapters.

```text
generated core:
  State
  Event
  Effect
  update
  view
  encode/decode

terminal adapter:
  terminal event loop
  keyboard mapping
  terminal canvas renderer
  local persistence

backend adapter:
  session actor
  durable event log
  timers
  websocket protocol

web adapter:
  Lustre model/update/view
  websocket client
```

No target adapter may modify Boon semantics.

All targets call the same generated `update` and `view`.

---

## 15. Expected runner

Parse upstream `.expected` files.

Generate:

```text
fixtures/expected_action_schema.json
```

If an unknown expected action appears, fail with:

```text
example name
line number
unknown action name
original line
```

Initial actions:

```text
assert_contains
assert_not_contains
assert_focused
assert_input_typeable
assert_input_empty
assert_input_placeholder
assert_checkbox_count
assert_checkbox_checked
assert_checkbox_unchecked
assert_button_has_outline

click_button
click_text
click_checkbox
click_button_near_text
dblclick_text
hover_text
focus_input
type
key
wait
run
clear_states
```

Target-specific expected runners:

```text
semantic runner:
  queries SemanticTree directly

terminal runner:
  queries TerminalCanvas and SemanticTree

backend runner:
  sends WebSocket events and queries snapshots

web runner:
  optional; uses browser automation later
```

No OCR. No screenshots required for `boon-gleam`.

---

## 16. Verification plan

### 16.1 Unit tests

```text
lexer tests
parser tests
module resolver tests
name mangling tests
HIR lowering tests
FlowIR tests
codegen golden tests
runtime update tests
JSON protocol tests
store tests
terminal canvas diff tests
```

Command:

```bash
gleam test
```

### 16.2 Static example verification

Examples:

```text
minimal
hello_world
layers
```

Required:

```text
compile
codegen
semantic snapshot
assert_contains
```

### 16.3 Event/state verification

Examples:

```text
counter
counter_hold
complex_counter
shopping_list
todo_mvc
```

Required:

```text
HOLD state
LINK events
input
checkbox
focus
hover
double click
persistence
```

### 16.4 Terminal game verification

Examples:

```text
pong
arkanoid
```

Use headless terminal canvas verification.

For Pong:

```text
initial frame contains paddles, ball, score
press up/down moves player paddle
tick advances ball
ball bounces from walls
score changes after miss
1000 ticks completes without crash
headless frame hash is deterministic
```

For Arkanoid:

```text
initial frame contains paddle, ball, bricks
left/right keys move paddle
tick advances ball
ball bounces
brick collision removes brick
score increases
level can be completed or remains stable
1000 ticks completes without crash
headless frame hash is deterministic
```

### 16.5 Backend durability verification

Required tests:

```text
session can be created
event append creates revision 1
snapshot can be fetched
session actor restart recovers from event log
duplicate event_id is idempotent or rejected deterministically
stale expected_revision is rejected
two clients receive same snapshot after event
clear session deletes local durable state
Postgres backend passes same tests as local store
```

### 16.6 WebSocket verification

Required tests:

```text
connect websocket
subscribe
send click event
receive event_ack
receive snapshot
disconnect
reconnect
receive latest snapshot
```

### 16.7 Distributed verification

Start with single-node verification.

Later distributed tests:

```text
two BEAM nodes
session registry can locate session
client connects to one node and session actor lives on another
events route to owning session actor
node failure produces explicit diagnostic or supervised recovery
```

Distributed tests are not part of v0.

---

## 17. Performance plan

Measure these from day one:

```text
parse_ms
lower_ms
codegen_ms
generated source size
BEAM app startup_ms
terminal frame render_ms
terminal frame diff cell count
events_per_second for generated update
session actor event latency
backend websocket roundtrip_ms
event log append_ms
snapshot save_ms
snapshot replay_ms
memory usage where available
```

Benchmark commands:

```bash
gleam run -- bench examples/upstream/counter --events 100000
gleam run -- bench examples/terminal/pong --ticks 10000
gleam run -- bench-backend examples/upstream/todo_mvc --events 10000 --store local
gleam run -- bench-backend examples/upstream/todo_mvc --events 10000 --store postgres
```

Performance reports:

```text
build/reports/perf/<example>.json
```

Do not claim C/Zig/Pony-level native speed. The goal is:

```text
interactive terminal performance
stable server latency
durable replay performance
large-session reliability
```

---

## 18. Implementation phases

### Phase 0 — Project skeleton

Deliver:

```text
gleam.toml
basic CLI
README
AGENTS.md
empty module structure
gleam test passes
```

Acceptance:

```bash
gleam test
gleam run -- help
```

### Phase 1 — Boon frontend minimum

Deliver:

```text
lexer
parser
AST
diagnostics
minimal project loader
```

Examples:

```text
minimal
hello_world
```

Acceptance:

```bash
gleam run -- compile examples/upstream/minimal
gleam run -- compile examples/upstream/hello_world
```

### Phase 2 — HIR/FlowIR and core codegen

Deliver:

```text
HIR
FlowIR
generated Gleam core modules
State/Event/Effect
update/view
semantic snapshot
```

Examples:

```text
minimal
hello_world
counter initial view
```

Acceptance:

```bash
gleam run -- verify examples/upstream/minimal
gleam run -- verify examples/upstream/hello_world
```

### Phase 3 — Events and HOLD state

Deliver:

```text
HOLD cells
LINK ports
button events
generated typed AppState
semantic tree queries
expected runner
```

Examples:

```text
counter
counter_hold
complex_counter
```

Acceptance:

```bash
gleam run -- verify examples/upstream/counter
gleam run -- verify examples/upstream/counter_hold
```

### Phase 4 — Real terminal TUI

Deliver:

```text
Etch terminal backend
full-screen playground shell
direct play mode
terminal canvas snapshot
keyboard input
frame timer
ANSI diff renderer
```

Examples:

```text
pong
arkanoid
```

Acceptance:

```bash
gleam run -- play examples/terminal/pong
gleam run -- verify examples/terminal/pong
gleam run -- play examples/terminal/arkanoid
gleam run -- verify examples/terminal/arkanoid
```

### Phase 5 — Forms/lists/TodoMVC semantic support

Deliver:

```text
text input
checkbox
select
slider
focus
hover
double click
lists
records
persistence effects
```

Examples:

```text
shopping_list
todo_mvc
temperature_converter
crud
```

Acceptance:

```bash
gleam run -- verify examples/upstream/shopping_list
gleam run -- verify examples/upstream/todo_mvc
```

### Phase 6 — Backend session actor

Deliver:

```text
Mist server
session actor
in-memory store
WebSocket protocol
event dispatch
snapshot broadcast
```

Acceptance:

```bash
gleam run -- serve examples/upstream/counter --store memory --port 8080
gleam run -- verify-backend examples/upstream/counter --store memory
```

### Phase 7 — Local durable store

Deliver:

```text
DETS/ETS local store
event log
snapshots
session recovery
duplicate event handling
```

Acceptance:

```bash
gleam run -- verify-backend examples/upstream/todo_mvc --store local
gleam run -- verify-durability examples/upstream/todo_mvc --store local
```

### Phase 8 — PostgreSQL durable store

Deliver:

```text
pog-based Postgres store
schema migrations or setup command
event log transactions
snapshot storage
replay tests
```

Acceptance:

```bash
gleam run -- store setup-postgres
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- verify-durability examples/upstream/todo_mvc --store postgres
```

### Phase 9 — Lustre web frontend

Deliver:

```text
generated Lustre target
websocket client
snapshot rendering
event sending
counter/todo_mvc web client
```

Acceptance:

```bash
gleam run -- web examples/upstream/counter
gleam run -- serve examples/upstream/counter --store local
```

The backend remains authoritative in durable client mode.

### Phase 10 — Multi-file and physical semantic support

Deliver:

```text
multi-file project loader
BUILD.bn support if needed
Scene semantic tree
physical TodoMVC semantic verification
theme/mode interactions
```

Acceptance:

```bash
gleam run -- verify examples/upstream/todo_mvc_physical
gleam run -- verify-backend examples/upstream/todo_mvc_physical --store local
```

No visual physical renderer is required.

---

## 19. Multi-file and BUILD.bn support

All examples are projects.

```gleam
pub type Project {
  Project(
    name: String,
    entry_file: String,
    files: List(ProjectFile),
    assets_root: Option(String),
  )
}

pub type ProjectFile {
  ProjectFile(
    path: String,
    contents: String,
    generated: Bool,
  )
}
```

Module rules:

```text
Entry file is not imported as a normal module.
BUILD.bn is a build script, not an app module.
Every other .bn file is importable.
Module name is basename without .bn.
Module names must be unique.
Relative paths are preserved.
```

If a project has `BUILD.bn`, run it before compiling the entry file.

Required build-host builtins for physical TodoMVC:

```text
Directory/entries(path)
File/read_text(path)
File/write_text(path, text)
Url/encode(text)
Text/join_lines(list)
List/retain(list, fn)
List/sort_by(list, fn)
List/map(list, fn)
List/count(list)
Log/info(text)
Log/error(text)
Build/succeed()
Build/fail(message)
FLUSH
FLUSHED
```

Build output is written to the project virtual filesystem.

---

## 20. Terminal games: Pong and Arkanoid

Pong and Arkanoid are important because they force the implementation to support:

```text
real keyboard input
timer ticks
stateful updates
terminal canvas rendering
fast redraw
headless verification
manual play
benchmarking
```

### 20.1 Boon terminal primitives

Support these Boon concepts:

```text
Terminal/key_down
Terminal/key_up
Terminal/resize
Terminal/canvas
Canvas/rect
Canvas/text
Canvas/cell
Timer/interval
```

Exact names may follow the current Boon/Boon-Zig convention. If names differ, document them in:

```text
fixtures/terminal_builtin_mapping.json
```

### 20.2 Pong acceptance

Manual:

```bash
gleam run -- play examples/terminal/pong
```

Required behavior:

```text
paddle responds to keyboard
ball moves at timer tick rate
ball bounces
score updates
quit key exits and restores terminal
```

Headless verification:

```bash
gleam run -- verify examples/terminal/pong
```

Required assertions:

```text
initial canvas has two paddles and a ball
after 10 ticks, ball position changed
after player movement key, paddle position changed
after forced miss, score changes
1000 ticks produces deterministic final hash
```

### 20.3 Arkanoid acceptance

Manual:

```bash
gleam run -- play examples/terminal/arkanoid
```

Required behavior:

```text
paddle responds to keyboard
ball moves
bricks render
brick collision removes brick
score updates
quit key exits and restores terminal
```

Headless verification:

```bash
gleam run -- verify examples/terminal/arkanoid
```

Required assertions:

```text
initial canvas has bricks, paddle, ball
after movement key, paddle position changed
after tick sequence, ball position changed
brick collision removes at least one brick
score increases
1000 ticks produces deterministic final hash
```

---

## 21. Durable backend scenarios

### 21.1 Counter

Scenario:

```text
start server
create session
connect client A
client A clicks +
client A receives revision 1
stop session actor
restart session actor
fetch snapshot
counter is still 1
```

### 21.2 TodoMVC

Scenario:

```text
start server
create session
connect clients A and B
A adds "Buy milk"
B receives snapshot containing "Buy milk"
B toggles checkbox
A receives checked state
stop/restart session actor
snapshot still has checked todo
event log replay reconstructs same state
```

### 21.3 Duplicate and stale events

Scenario:

```text
send event_id X at revision 1
send event_id X again
result is idempotent or rejected as duplicate

send event with expected_revision too old
server rejects with revision_conflict
```

---

## 22. Generated web frontend scenarios

### 22.1 Counter web client

```text
Lustre app connects to backend session
renders snapshot
click + sends event over WebSocket
receives updated snapshot
renders new count
```

### 22.2 TodoMVC web client

```text
renders todo list
typing creates local input event
submit sends event to backend
backend stores event
snapshot returns
list updates
```

The backend is source of truth.

---

## 23. Error handling

Every layer must produce clear diagnostics.

Examples:

```text
Compiler parse error:
  file, line, column, message, source excerpt

Module collision:
  two module paths and shared module name

Codegen error:
  FlowIR node type and source span

Terminal error:
  unsupported terminal capability or Etch error

Backend error:
  session id, event id, revision, store error

Store error:
  operation, key/session, message

Protocol error:
  raw JSON, expected schema, decoded problem
```

No silent failures.

---

## 24. No fake pass rule

A verification pass is invalid if achieved by:

```text
skipping examples
hiding examples
ignoring .expected files
hardcoding output for a named example
returning empty snapshots
ignoring LINK events
treating unsupported syntax as successful
silently dropping modules
silently dropping unsupported elements
accepting events without updating state
pretending durability without writing event logs
pretending distributed behavior without session ownership
```

Unsupported features must produce explicit failing diagnostics.

---

## 25. Definition of done: v0

v0 is complete when:

```text
Gleam project builds.
Compiler can parse and lower minimal, hello_world, counter.
Generated core update/view exists.
Semantic expected runner works.
Counter events work.
Terminal TUI can launch.
Pong can be played manually in terminal.
Pong can be verified headlessly.
No non-Gleam implementation code is required.
```

Commands:

```bash
gleam test
gleam run -- verify examples/upstream/minimal
gleam run -- verify examples/upstream/hello_world
gleam run -- verify examples/upstream/counter
gleam run -- play examples/terminal/pong
gleam run -- verify examples/terminal/pong
```

---

## 26. Definition of done: v1

v1 is complete when:

```text
Arkanoid is playable and verified.
TodoMVC semantic example passes.
Terminal TUI playground is comfortable for manual use.
Backend server can run counter with memory store.
WebSocket client can receive snapshots and send events.
Durability local store passes restart/replay tests.
```

Commands:

```bash
gleam run -- play examples/terminal/arkanoid
gleam run -- verify examples/terminal/arkanoid
gleam run -- verify examples/upstream/todo_mvc
gleam run -- serve examples/upstream/counter --store memory --port 8080
gleam run -- verify-backend examples/upstream/counter --store memory
gleam run -- verify-durability examples/upstream/counter --store local
```

---

## 27. Definition of done: durable backend

The durable backend is complete when:

```text
Postgres store is implemented.
Event log append is transactional.
Snapshots are saved and loaded.
Session actor restart replays state correctly.
Duplicate event ids are handled.
Stale revisions are rejected.
Two WebSocket clients receive consistent snapshots.
TodoMVC passes backend verification with Postgres.
```

Commands:

```bash
gleam run -- store setup-postgres
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- verify-durability examples/upstream/todo_mvc --store postgres
```

---

## 28. Definition of done: full-stack experiment

The full-stack experiment is complete when:

```text
Terminal TUI works.
Backend server works.
Lustre web client works.
The same generated Boon core drives all targets.
Counter and TodoMVC run through terminal, backend, and web-client targets.
Durability and replay tests pass.
```

Commands:

```bash
gleam run -- verify-all
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- web examples/upstream/todo_mvc
```

---

## 29. Codex implementation prompt

Use this prompt when asking Codex to create the repository.

```text
Create a new repository named boon-gleam using this AGENTS.md / implementation plan.

Implement the project in Gleam.

Do not add Zig, Rust, Pony, Raybox, Sokol, SDL, WebGPU, Slang, or browser/Wasm tooling.

Start with:
1. gleam.toml and basic CLI.
2. lexer/parser for minimal Boon syntax needed by minimal, hello_world, and counter.
3. HIR/FlowIR.
4. generated Gleam core functions: init, update, view.
5. semantic tree runtime.
6. expected runner for assert_contains and click_button.
7. counter example verification.
8. Etch-based terminal TUI skeleton.
9. direct playable Pong terminal target.

Keep all targets going through the same generated update/view core.
Do not hardcode example output.
Do not fake passing tests.
Unsupported syntax must fail with explicit diagnostics.
```

---

## 30. Reference links

Gleam language:

```text
https://gleam.run/
https://gleam.run/frequently-asked-questions/
```

Gleam OTP:

```text
https://hexdocs.pm/gleam_otp/index.html
https://hexdocs.pm/gleam_otp/gleam/otp/actor.html
```

Terminal/TUI:

```text
https://hexdocs.pm/etch/index.html
https://github.com/bgwdotdev/shore
https://hexdocs.pm/gleam_community_ansi/gleam_community/ansi.html
```

Web/frontend/backend:

```text
https://hexdocs.pm/lustre/index.html
https://hexdocs.pm/mist/index.html
https://gleam-wisp.github.io/wisp/
```

Durability:

```text
https://hexdocs.pm/pog/pog.html
https://hexdocs.pm/gleam_pgo/gleam/pgo.html
https://hexdocs.pm/shelf/index.html
https://hexdocs.pm/slate/index.html
https://www.erlang.org/doc/apps/mnesia/mnesia.html
```

Boon:

```text
https://github.com/BoonLang/boon
```
