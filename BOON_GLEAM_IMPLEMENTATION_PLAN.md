# Boon-Gleam Implementation Contract

This file is the canonical implementation contract for `boon-gleam`.
Keep it at the repository root as `BOON_GLEAM_IMPLEMENTATION_PLAN.md`.
If an `AGENTS.md` file is added later, it must point to this file instead of
duplicating or weakening it.

`boon-gleam` exists to build a Gleam implementation and codegen backend for
Boon:

```text
Boon source project
  -> Gleam Boon frontend
  -> HIR
  -> SourceShape
  -> FlowIR
  -> generated Gleam core
  -> terminal, backend, or web adapter
```

The required outcome is a deterministic generated Boon core plus adapters for:

```text
terminal_tui_beam
durable_backend_beam
web_frontend_js
```

The generated app core is pure:

```gleam
pub fn init(context: InitContext) -> State
pub fn update(state: State, event: Event) -> #(State, List(Effect))
pub fn view(state: State) -> Snapshot
```

The BEAM/runtime layers own process scheduling, timers, persistence,
durability, supervision, terminal event loops, and backend client sessions.
The generated core must not import OTP, HTTP, database, terminal, browser,
filesystem, or wall-clock APIs.

No passing result may be produced by skipping examples, hiding examples,
hardcoding named outputs, returning empty snapshots, accepting unsupported
syntax, ignoring expected files, accepting events without state updates,
rewriting Boon semantics in adapters, or pretending durability without a real
event log. Unsupported features must fail with named diagnostics.

---

## 1. Scope And Non-Goals

`boon-gleam` targets typed, distributed, durable, full-stack reactive Boon on
Gleam. The first complete track is terminal and BEAM backend behavior. Gleam JS
and Lustre are allowed only for the web-client target.

In scope:

```text
typed generated Boon state machines
actor-based app sessions
supervised runtime processes
durable event logs and snapshots
terminal playground
playable terminal Pong in v0
playable terminal Arkanoid in v1
HTTP/WebSocket backend sessions
Gleam JS + Lustre client experiments
```

Out of scope:

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
native GPU rendering
3D rendering
3D printing
freestanding Wasm runtime work
native binary codegen
Pony codegen
Zig codegen
Rust codegen
```

The phrase "no browser tooling" must not be used in this repo. It conflicts
with the selected Gleam JS + Lustre web-client target. The actual prohibition is
no WebGPU, no native/browser renderer experiment, and no separate Wasm runtime
outside the Gleam JS target.

---

## 2. Version Pins And Preconditions

These pins were checked on 2026-04-27. Update them only in a dedicated
dependency-pin change with a short note explaining why.

```text
Toolchain:
  Gleam: 1.16.0
  Erlang/OTP: 28.5

Required local preflight:
  gleam --version
  erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

Current machine note:
  On 2026-04-27, both `gleam` and `erl` were missing from PATH in this repo.
  Phase 0 must install or expose them before any build gate can pass.
```

Initial Hex dependencies:

```toml
[dependencies]
gleam_stdlib = "1.0.0"
gleam_erlang = "1.3.0"
gleam_otp = "1.2.0"
gleam_json = "3.1.0"
etch = "1.3.3"
mist = "6.0.3"
shelf = "1.0.0"
pog = "4.1.0"

[dev-dependencies]
lustre = "5.6.0"
```

Dependency rules:

```text
Etch is the only terminal backend for v0.
Mist is the only HTTP/WebSocket server for v0/v1.
Shelf is the only local DETS/ETS-backed store for v1.
Pog is the only PostgreSQL client for the durable backend milestone.
Lustre is allowed only for the web-client target.
Do not add Wisp unless a later plan changes the backend routing contract.
Do not add gleam_community_ansi for v0; use Etch and minimal ANSI output.
```

Pinned source repositories:

```text
Boon corpus:
  repo: https://github.com/BoonLang/boon
  commit: 34251e2938a73f05de14997e167630bb0124ef48
  source root: playground/frontend/src/examples/

boon-zig terminal behavior reference:
  repo: https://github.com/BoonLang/boon-zig
  commit: c083ddc2adc4af92d9a1a585a81d5c7af395efb2
  use: terminal Pong/Arkanoid behavior and terminal verification inspiration
```

---

## 3. Repository Layout

Use this layout. Add files as their phase requires them; do not create empty
placeholders except `.gitkeep` files needed to preserve directories.

```text
boon-gleam/
  BOON_GLEAM_IMPLEMENTATION_PLAN.md
  README.md
  gleam.toml
  manifest.toml

  examples/
    upstream/
    terminal/
      pong/
      arkanoid/

  fixtures/
    corpus_manifest.json
    expected_action_schema.json
    protocol_schema.json
    backend_api_schema.json
    snapshot_schema.json
    terminal_builtin_mapping.json

  src/
    boongleam.gleam
    cli/
    frontend/
    project/
    lowering/
    codegen/
    runtime/
    terminal/
    backend/
    web/
    verify/
    bench/
    support/

  generated/
    .gitkeep

  build/
    generated/
    reports/
    cache/
    state/
```

`build/` is generated output. Verification commands may write reports there,
but must never mutate `fixtures/corpus_manifest.json`.

---

## 4. Source Corpus Contract

Import examples from the pinned Boon corpus root. The importer must preserve
source file contents byte-for-byte except for line ending normalization to LF.
Do not silently import unrelated directories.

The v0/v1 imported upstream examples are:

```text
minimal
hello_world
counter
counter_hold
complex_counter
interval
interval_hold
layers
shopping_list
todo_mvc
cells
cells_dynamic
```

The later corpus expansion includes the remaining registered examples from the
pinned upstream root, including:

```text
pages
temperature_converter
crud
timer
flight_booker
circle_drawer
latest
text_interpolation_update
then
when
while
list_retain_reactive
list_map_external_dep
list_map_block
list_retain_count
list_object_state
list_retain_remove
filter_checkbox_bug
checkbox_test
chained_list_remove_bug
while_function_call
button_hover_test
button_hover_to_click_test
switch_hold_test
todo_mvc_physical
```

Import rules:

```text
Copy each example's `.bn` files.
Copy each example's `.expected` file.
Copy reference images, metadata JSON, docs, helper scripts, and asset
directories as source metadata.
Record ignored upstream paths in the manifest with an explicit reason.
Do not mutate source examples to make them pass.
Do not use source file names to special-case lowering or runtime behavior.
```

`fixtures/corpus_manifest.json` is immutable source metadata. It must contain:

```json
{
  "schema_version": 1,
  "generated_at_utc": "2026-04-27T00:00:00Z",
  "sources": [
    {
      "name": "boon",
      "repo": "https://github.com/BoonLang/boon",
      "commit": "34251e2938a73f05de14997e167630bb0124ef48",
      "source_root": "playground/frontend/src/examples"
    }
  ],
  "examples": [
    {
      "name": "counter",
      "kind": "single_file",
      "source_repo": "boon",
      "source_commit": "34251e2938a73f05de14997e167630bb0124ef48",
      "source_path": "counter",
      "local_path": "examples/upstream/counter",
      "entry_file": "counter.bn",
      "files": ["counter.bn", "counter.expected"],
      "assets": [],
      "docs": [],
      "scripts": [],
      "expected": "counter.expected",
      "targets": ["semantic", "terminal", "backend"],
      "phase": "events",
      "ignored": false,
      "ignored_reason": ""
    }
  ],
  "ignored": [
    {
      "path": "hw_examples/",
      "source_repo": "boon",
      "source_commit": "34251e2938a73f05de14997e167630bb0124ef48",
      "ignored": true,
      "ignored_reason": "not part of the v0/v1 Boon reactive app corpus"
    }
  ]
}
```

Verification reports go under:

```text
build/reports/verify/<example>.json
build/reports/verify-all.json
build/reports/backend/<example>.json
build/reports/durability/<example>.json
build/reports/perf/<example>.json
```

---

## 5. CLI Contract

The executable command is `boongleam`. During development it is invoked through
`gleam run -- <subcommand>`.

Every command exits `0` on success and non-zero on failure. Commands that write
reports must write the report before exiting non-zero when failure details are
available.

```text
help
  Print subcommands, flags, and examples.

import-upstream --source PATH --out examples/upstream
  Import pinned corpus files and write fixtures/corpus_manifest.json.

manifest
  Validate fixtures/corpus_manifest.json and print summary.

compile EXAMPLE_PATH
  Load project, lex, parse, resolve modules, lower through HIR/SourceShape.

codegen EXAMPLE_PATH [--target core|terminal|backend|web]
  Generate Gleam package output under build/generated/<example>/.

verify EXAMPLE_PATH [--target semantic|terminal] [--report PATH]
  Run .expected verification through BoonGleamRuntimeHost.

verify-all [--phase PHASE] [--report build/reports/verify-all.json]
  Run every non-ignored manifest example whose phase is <= PHASE.

verify-backend EXAMPLE_PATH --store memory|local|postgres [--report PATH]
  Start bounded backend session verification and stop all spawned processes.

verify-durability EXAMPLE_PATH --store local|postgres [--report PATH]
  Verify restart/replay/idempotency/conflict behavior.

tui
  Launch interactive terminal playground.

play EXAMPLE_PATH
  Launch direct interactive full-screen terminal mode.

play-smoke EXAMPLE_PATH --ticks N --keys PATH --timeout-ms N
  Run bounded terminal mode without human input and write a report.

serve EXAMPLE_PATH --store memory|local|postgres --port N
  Run long-lived backend server until interrupted.

serve-smoke EXAMPLE_PATH --store memory|local|postgres --port N --timeout-ms N
  Start backend, run health/session/snapshot smoke checks, stop backend.

web EXAMPLE_PATH --mode durable-client|local-js
  Build or run the Lustre/Gleam JS client for the selected target.

store setup-postgres --database-url URL
  Apply the PostgreSQL schema if missing. Must be idempotent.

bench EXAMPLE_PATH --events N|--ticks N [--report PATH]
  Run bounded local performance measurement.

bench-backend EXAMPLE_PATH --events N --store local|postgres [--report PATH]
  Run bounded backend performance measurement.
```

Required smoke commands:

```bash
gleam test
gleam run -- help
gleam run -- manifest
gleam run -- verify examples/upstream/counter
gleam run -- play-smoke examples/terminal/pong --ticks 1000 --timeout-ms 5000
gleam run -- serve-smoke examples/upstream/counter --store memory --port 8080 --timeout-ms 5000
```

Long-running commands such as `play` and `serve` are never the only CI gate.
Every long-running command must have a bounded smoke command.

---

## 6. Compiler Frontend And Syntax Matrix

The compiler is implemented in Gleam. It must emit diagnostics with:

```text
code
severity
file path
line
column
span start
span end
message
help
```

Pipeline:

```text
ProjectLoader
  -> Lexer
  -> Parser
  -> AST
  -> ModuleResolver
  -> NameResolver
  -> HIR
  -> SourceShape
  -> FlowIR
  -> TypeFacts
  -> GleamCodegen
```

Phase-gated syntax:

```text
Phase 1:
  identifiers
  integer/string/bool/text literals
  lists
  records
  field access
  named definitions
  function calls
  pipe calls
  basic Document/Text/Element output needed by minimal and hello_world

Phase 2:
  helper functions
  blocks
  semantic snapshot roots
  generated typed State/Event/Effect shell

Phase 3:
  HOLD
  LINK
  THEN
  LATEST
  button press
  text input change/key_down
  expected runner actions for counter/counter_hold/complex_counter

Phase 4:
  Terminal/canvas
  Terminal/key_down
  Terminal/key_up
  Terminal/resize
  Timer/interval
  Canvas/rect
  Canvas/text
  Canvas/cell

Phase 5:
  WHEN
  WHILE
  PASS:
  PASSED
  list map/retain/count/remove
  records in mapped scopes
  checkbox, select, slider, hover, focus, double-click

Phase 10:
  multi-file project loading
  BUILD.bn
  Scene semantic snapshots
```

`LINK` is the canonical runnable source marker for this repo because the pinned
Boon corpus uses `LINK`. `SOURCE` is not canonical for `boon-gleam` v0/v1. If a
runnable source file contains `SOURCE`, fail with:

```text
code: unsupported_source_marker
message: SOURCE is not accepted by boon-gleam v0/v1; use LINK for the pinned corpus
```

SourceShape is required before FlowIR. It records:

```text
source slot id
semantic path
payload type
source span
binding target path
function instance id
mapped scope id
list item identity input
PASS/PASSED normalized context path
```

SourceShape diagnostics:

```text
duplicate_link_path
link_used_as_normal_value
incompatible_link_binding
dynamic_link_shape
unsupported_source_marker
unsupported_syntax
module_collision
```

Stable identity rules:

```text
Function instance identity is derived from function name, callsite span, and
stable parent scope id.

Mapped list item identity is derived from explicit item id when present. If no
explicit id exists, use source list identity plus zero-based index and mark the
node as index-keyed in the semantic tree.

Retained semantic node id is derived from source span, semantic path, function
instance id, mapped scope id, and item identity.

Focus, hover, input value, and checkbox state must survive re-render when the
retained semantic id is unchanged.

Equal timestamp/source conflicts break by stable source order: file path, span
start, then span end.
```

FlowIR must make these concepts explicit:

```text
HOLD cells
LINK slots and binding operations
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

Generated Gleam code must not need raw Boon syntax.

---

## 7. Generated Package Contract

Generate one build directory per Boon project:

```text
build/generated/<example>/
  gleam.toml
  src/generated_<example>.gleam
  src/generated_<example>/types.gleam
  src/generated_<example>/state.gleam
  src/generated_<example>/event.gleam
  src/generated_<example>/effect.gleam
  src/generated_<example>/update.gleam
  src/generated_<example>/view.gleam
  src/generated_<example>/encode.gleam
  src/generated_<example>/decode.gleam
  src/generated_<example>/terminal_adapter.gleam
  src/generated_<example>/backend_adapter.gleam
  src/generated_<example>/lustre_adapter.gleam
```

Package boundaries:

```text
boon_gleam_runtime:
  shared runtime package from this repo
  contains semantic tree, terminal canvas, events/effects, diagnostics, JSON
  codecs, verification host types

generated core package:
  imports only gleam_stdlib, gleam_json, and boon_gleam_runtime
  exports typed State, Event, Effect, init, update, view, encode, decode

BEAM adapter modules:
  may import gleam_erlang, gleam_otp, mist, shelf, pog
  must never be imported by JS target modules

JS/Lustre adapter modules:
  may import lustre
  must never import gleam_erlang, gleam_otp, mist, shelf, or pog
```

Generated core functions:

```gleam
pub fn init(context: InitContext) -> State
pub fn update(state: State, event: Event) -> #(State, List(Effect))
pub fn view(state: State) -> Snapshot
```

Generated events must be typed. Do not use a stringly map as the primary
generated event representation.

```gleam
pub type Event {
  Press(link_id: String)
  Click(link_id: String)
  ChangeText(link_id: String, text: String)
  KeyDown(link_id: String, key: Key)
  KeyUp(link_id: String, key: Key)
  TimerTick(timer_id: String, now_ms: Int)
  RouteTo(path: String)
  TerminalKeyDown(key: Key)
  TerminalKeyUp(key: Key)
  TerminalResize(width: Int, height: Int)
}
```

Effects are target-neutral:

```gleam
pub type Effect {
  PersistWrite(key: String, value_json: String)
  PersistDeletePrefix(prefix: String)
  StartTimer(id: String, interval_ms: Int)
  StopTimer(id: String)
  RouteTo(path: String)
  LogInfo(message: String)
  LogError(message: String)
}
```

---

## 8. Runtime Snapshot And Schema Contract

All snapshots must encode to JSON matching `fixtures/snapshot_schema.json`.

```gleam
pub type Snapshot {
  DocumentSnapshot(Document)
  SceneSnapshot(Scene)
  TerminalCanvasSnapshot(TerminalCanvas)
  SemanticSnapshot(SemanticTree)
}

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
    source_path: String,
    children: List(SemanticNode),
  )
}

pub type TerminalCanvas {
  TerminalCanvas(width: Int, height: Int, cells: List(TerminalCell))
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

pub type Colour {
  Indexed(Int)
  Rgb(red: Int, green: Int, blue: Int)
  Default
}
```

Allowed semantic roles:

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

`Scene` is semantic only. No Raybox or physical renderer is implemented here.

Schema files are normative:

```text
fixtures/snapshot_schema.json:
  Snapshot, SemanticNode, TerminalCanvas, TerminalCell, Colour, Diagnostic

fixtures/protocol_schema.json:
  WebSocket client/server messages, event JSON, snapshot JSON, errors

fixtures/backend_api_schema.json:
  HTTP requests, responses, status codes, error bodies

fixtures/expected_action_schema.json:
  .expected action names and argument types
```

---

## 9. BoonGleamRuntimeHost

All verifiers, backend smoke tests, and terminal smoke tests must go through
`BoonGleamRuntimeHost`. This facade is the public runtime/testing contract.

Required capabilities:

```gleam
pub type BoonGleamRuntimeHost

pub fn load_project(path: String) -> Result(Project, Diagnostic)
pub fn compile_project(project: Project) -> Result(CompiledProject, Diagnostic)
pub fn codegen_project(compiled: CompiledProject, target: Target) -> Result(GeneratedProject, Diagnostic)
pub fn start_session(generated: GeneratedProject, clock: TimeSource) -> Result(RuntimeSession, Diagnostic)
pub fn dispatch(session: RuntimeSession, event: EventEnvelope) -> Result<EventResult, Diagnostic)
pub fn advance_time(session: RuntimeSession, by_ms: Int) -> Result(RuntimeSession, Diagnostic)
pub fn wait_until_quiescent(session: RuntimeSession, max_steps: Int) -> Result(RuntimeSession, Diagnostic)
pub fn snapshot(session: RuntimeSession) -> Result(SnapshotEnvelope, Diagnostic)
pub fn stop_session(session: RuntimeSession) -> Nil
```

Time sources:

```gleam
pub type TimeSource {
  Virtual(now_ms: Int)
  Realtime
}
```

Verification uses `Virtual` only. Interactive `play`, `tui`, and `serve` may use
`Realtime`. `wait` actions advance virtual time; they never sleep.

Quiescence:

```text
The runtime is quiescent when no immediate generated events, due timers, or
pending effect interpretations remain.

If max_steps is exhausted, fail with diagnostic code runtime_not_quiescent.
```

---

## 10. Expected Runner Contract

Parse upstream `.expected` files as TOML. Do not invent a new format.

Supported sections and fields:

```text
[test]
category
description
only_engines
skip_engines

[output]
text
match

[timing]
timeout
initial_delay
poll_interval

[[sequence]]
description
actions
expect
expect_match

[[persistence]]
description
actions
expect
expect_match
```

`skip_engines` is informational unless it explicitly names `boon-gleam`.
Unsupported actions fail during expected parsing, not halfway through a run.

Action names:

```text
assert_button_disabled
assert_button_enabled
assert_button_has_outline
assert_cells_cell_text
assert_cells_row_visible
assert_checkbox_checked
assert_checkbox_count
assert_checkbox_unchecked
assert_contains
assert_focused
assert_focused_input_value
assert_input_empty
assert_input_not_typeable
assert_input_placeholder
assert_input_typeable
assert_input_value
assert_not_contains
assert_not_focused
assert_toggle_all_darker
assert_url

clear_states
click_button
click_button_near_text
click_checkbox
click_checkbox_near_text
click_text
dblclick_cells_cell
dblclick_text
dblclick_text_nth
focus_input
hover_text
key
run
select_option
set_focused_input_value
set_input_value
set_slider_value
type
wait
```

Action semantics:

```text
Text matching uses visible SemanticTree text, not source text.
Index-based controls use zero-based indexes.
Cells row/column actions use the corpus convention: one-based row/column.
set_* actions replace the control value and emit the corresponding change event.
type appends text to the focused input and emits deterministic change events.
key emits key_down with the current focused input value when applicable.
wait advances virtual time by the requested duration.
run starts or restarts through BoonGleamRuntimeHost.
clear_states clears runtime, memory store, local store for the selected example,
and terminal verifier state.
```

Unknown action diagnostics must include:

```text
example name
expected file path
line/span
unknown action name
original TOML action row
fixtures/expected_action_schema.json path
```

Verification report shape:

```json
{
  "schema_version": 1,
  "command": "verify",
  "example": "counter",
  "target": "semantic",
  "status": "pass",
  "started_at_utc": "2026-04-27T00:00:00Z",
  "duration_ms": 12,
  "source_commit": "34251e2938a73f05de14997e167630bb0124ef48",
  "actions_total": 3,
  "actions_passed": 3,
  "snapshot_hash": "sha256:...",
  "terminal_frame_hash": null,
  "diagnostics": [],
  "failure": null,
  "reproduce": "gleam run -- verify examples/upstream/counter"
}
```

Failure reports set `status` to `fail` and include:

```json
{
  "example": "todo_mvc",
  "sequence_index": 1,
  "action_index": 4,
  "action": ["click_button_near_text", "Buy milk"],
  "expected": "Buy milk",
  "actual": "visible semantic tree text...",
  "semantic_tree_dump": "...",
  "terminal_frame_dump": null,
  "diagnostics": []
}
```

---

## 11. Terminal TUI And Games

Terminal builtins are defined in `fixtures/terminal_builtin_mapping.json` before
Phase 4 implementation starts.

Required v0 terminal builtins:

```text
Terminal/key_down -> Event.TerminalKeyDown
Terminal/key_up -> Event.TerminalKeyUp
Terminal/resize -> Event.TerminalResize
Terminal/canvas -> TerminalCanvasSnapshot
Canvas/rect -> TerminalCanvas cells
Canvas/text -> TerminalCanvas cells
Canvas/cell -> TerminalCanvas cell
Timer/interval -> Effect.StartTimer
```

Headless terminal defaults:

```text
viewport: 80 columns x 24 rows
tick cadence: 16 ms
initial virtual time: 0 ms
random seed: 0
final hash input: viewport, sorted cells, app state JSON, revision, virtual time
```

Modes:

```text
boongleam tui
  full playground with examples, source/IR, preview, logs, diagnostics

boongleam play examples/terminal/pong
  full-screen direct play mode

boongleam play-smoke examples/terminal/pong --ticks 1000 --timeout-ms 5000
  bounded CI-safe smoke mode
```

Direct play requirements:

```text
full-screen terminal
raw/cbreak key input through Etch
frame timer
ANSI diff rendering
terminal restored on exit
q exits
bounded headless mode for CI
```

Pong v0 acceptance:

```text
initial frame contains two paddles, ball, and score
up/down keys move player paddle
tick advances ball
ball bounces from walls
forced miss changes score
1000 ticks produces deterministic final hash
manual quit restores terminal
```

Arkanoid is v1, not v0:

```text
initial frame contains bricks, paddle, ball, and score
left/right keys move paddle
tick advances ball
brick collision removes brick
score increases
1000 ticks produces deterministic final hash
manual quit restores terminal
```

Terminal playground verification:

```text
play-smoke proves bounded game behavior.
tui-smoke, when added, must select every tab/pane and run at least one
meaningful action per milestone example.
Manual tmux/PTTY proof is required before claiming the interactive TUI is ready
for user handoff.
```

---

## 12. Backend Session And Durability

Backend target runs on BEAM with one session actor per app session.

Supervision shape:

```text
BoonGleamAppSupervisor
  StoreSupervisor
    EventLogStore
    SnapshotStore
  SessionRegistry
  SessionSupervisor
    SessionActor(project_id, session_id)
  ClientSupervisor
    WebSocketClientActor
  TimerSupervisor
    TimerActor
  WebServer
```

Session state:

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

Use `ProjectSessionId` everywhere:

```gleam
pub type ProjectSessionId {
  ProjectSessionId(project_id: String, session_id: String)
}
```

Store API:

```gleam
pub type Store {
  Store(
    append_if_revision: fn(ProjectSessionId, expected_revision: Int, StoredEvent) -> Result(AppendedEvent, StoreError),
    load_events_after: fn(ProjectSessionId, revision: Int) -> Result(List(StoredEvent), StoreError),
    load_event_result: fn(ProjectSessionId, event_id: String) -> Result(Option(EventResult), StoreError),
    save_event_result: fn(ProjectSessionId, event_id: String, result: EventResult) -> Result(Nil, StoreError),
    save_snapshot_tx: fn(ProjectSessionId, StoredSnapshot) -> Result(Nil, StoreError),
    load_latest_snapshot: fn(ProjectSessionId) -> Result(Option(StoredSnapshot), StoreError),
    clear_session: fn(ProjectSessionId) -> Result(Nil, StoreError),
  )
}
```

Event acceptance transaction:

```text
1. Receive event_id, expected_revision, and event.
2. If event_id already has a stored result, return that result unchanged.
3. Check expected_revision against session current revision.
4. Allocate accepted_revision = current_revision + 1.
5. Append event with accepted_revision.
6. Apply generated update(state, event).
7. Interpret target effects.
8. Persist EventResult for event_id.
9. Update current_revision to accepted_revision.
10. Save snapshot when snapshot policy says so.
11. Broadcast snapshot to subscribers.
```

Effect failure:

```text
If effect interpretation fails before current_revision update, reject the event
with event_reject and do not broadcast a new snapshot.

If persistence fails after event append, stop the session actor with an explicit
store_error diagnostic. Recovery must replay the appended event or return the
stored event result; it must not silently lose the event.
```

PostgreSQL schema:

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

create table boon_event_results (
  project_id text not null,
  session_id text not null,
  event_id text not null,
  revision bigint not null,
  result_json jsonb not null,
  created_at timestamptz not null,
  primary key (project_id, session_id, event_id)
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

## 13. HTTP And WebSocket API

All HTTP request/response bodies are defined in
`fixtures/backend_api_schema.json`. All WebSocket messages are defined in
`fixtures/protocol_schema.json`.

HTTP endpoints:

```text
GET  /health
  200 {"status":"ok"}

GET  /projects
  200 {"projects":[{"project_id":"counter","entry":"counter.bn"}]}

POST /projects
  body {"project_id":"counter","source_path":"examples/upstream/counter"}
  201 {"project_id":"counter"}

GET /projects/:project_id
  200 {"project_id":"counter","compiled":true,"diagnostics":[]}
  404 {"error":{"code":"project_not_found","message":"..."}}

POST /projects/:project_id/compile
  200 {"project_id":"counter","diagnostics":[]}

POST /projects/:project_id/sessions
  body {"session_id":"optional-client-id"}
  201 {"project_id":"counter","session_id":"...","revision":0}

GET /projects/:project_id/sessions/:session_id/snapshot
  200 {"revision":N,"snapshot":{...}}

GET /projects/:project_id/sessions/:session_id/events
  200 {"events":[...]}

POST /projects/:project_id/sessions/:session_id/clear
  200 {"cleared":true}
```

WebSocket path:

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
{"type":"snapshot","revision":13,"snapshot":{}}
{"type":"event_ack","event_id":"uuid","revision":13}
{"type":"event_reject","event_id":"uuid","reason":"revision_conflict","current_revision":13}
{"type":"diagnostic","diagnostic":{}}
{"type":"pong"}
```

Ordering:

```text
For an accepted event, send event_ack before or in the same mailbox turn as the
resulting snapshot. All subscribed clients receive the same revision snapshot.
The server never trusts client-side state. Stale expected_revision is rejected.
```

---

## 14. Web Frontend Target

The web frontend uses Gleam JavaScript + Lustre.

Two modes are allowed:

```text
durable-client:
  Lustre frontend connects to BEAM backend WebSocket.
  Backend session actor is authoritative.
  Frontend sends events and renders snapshots.

local-js:
  Generated Gleam JS runs update/view locally.
  No durable backend.
  Demo-only until a later plan makes it a milestone.
```

Durable client mode is the priority. JS/Lustre modules must never import
BEAM-only modules.

Acceptance for web milestones must include a bounded command. A long-lived
browser window alone is not a pass.

---

## 15. BUILD.bn And Multi-File Projects

All examples are projects:

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
Module names must be unique within a project.
Relative paths are preserved.
```

Phase 10 requires `BUILD.bn`; it is not conditional.

VFS rules:

```text
Each project has a sandboxed virtual root.
BUILD.bn can read only files in that project root.
BUILD.bn can write only generated files under that project root.
Directory entries are sorted bytewise by normalized relative path.
Writes are staged and committed only if BUILD.bn ends with Build/succeed().
Build/fail(message) discards staged writes and fails compilation.
FLUSH commits current staged writes and continues.
FLUSHED reports the last committed generated file set.
```

Required build-host builtins:

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

BUILD report fields:

```text
project
build_file
inputs
generated_files
diagnostics
status
```

---

## 16. Performance And Metrics

Correctness reports and performance reports are separate. Correctness must pass
before any performance pass is meaningful.

Measure:

```text
parse_ms
lower_ms
source_shape_ms
flow_ir_ms
codegen_ms
generated_source_size
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

Initial budgets are warning thresholds, not hard release gates, until v1:

```text
counter verify: p95 event latency <= 25 ms
todo_mvc semantic verify: p95 event latency <= 50 ms
pong terminal frame render: p95 <= 16 ms for 80x24
backend counter memory-store roundtrip: p95 <= 50 ms
local replay 1000 events: <= 1000 ms
```

Performance reports go under `build/reports/perf/` and include command,
example, target, samples, p50, p95, max, and environment summary.

---

## 17. Implementation Phases

### Phase 0 - Toolchain And Skeleton

Deliver:

```text
Gleam and Erlang/OTP preflight documented
gleam.toml with pinned dependencies
basic CLI
README
module skeleton needed by Phase 1 only
```

Acceptance:

```bash
gleam --version
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
gleam test
gleam run -- help
```

### Phase 1 - Boon Frontend Minimum

Deliver:

```text
lexer
parser
AST
diagnostics
minimal project loader
Phase 1 syntax matrix support
```

Acceptance:

```bash
gleam run -- compile examples/upstream/minimal
gleam run -- compile examples/upstream/hello_world
```

### Phase 2 - HIR, SourceShape, FlowIR, Core Codegen

Deliver:

```text
HIR
SourceShape
FlowIR
generated Gleam core modules
typed State/Event/Effect
semantic snapshot runtime
```

Acceptance:

```bash
gleam run -- verify examples/upstream/minimal
gleam run -- verify examples/upstream/hello_world
```

### Phase 3 - Events And HOLD State

Deliver:

```text
HOLD cells
LINK slots and bindings
THEN
LATEST
button/input events
BoonGleamRuntimeHost
expected runner core actions
semantic tree queries
```

Acceptance:

```bash
gleam run -- verify examples/upstream/counter
gleam run -- verify examples/upstream/counter_hold
gleam run -- verify examples/upstream/complex_counter
```

### Phase 4 - Pong Terminal V0

Deliver:

```text
Etch terminal backend
direct play mode
play-smoke mode
terminal canvas snapshot
keyboard input
virtual frame timer
ANSI diff renderer
Pong
```

Acceptance:

```bash
gleam run -- play-smoke examples/terminal/pong --ticks 1000 --timeout-ms 5000
gleam run -- verify examples/terminal/pong --target terminal
```

Manual handoff proof before claiming interactive readiness:

```bash
gleam run -- play examples/terminal/pong
```

### Phase 5 - Forms, Lists, TodoMVC Semantics

Deliver:

```text
WHEN/WHILE
PASS/PASSED
text input
checkbox
select
slider
focus
hover
double click
lists and records
persistence effects
stable identity rules
```

Acceptance:

```bash
gleam run -- verify examples/upstream/shopping_list
gleam run -- verify examples/upstream/todo_mvc
```

### Phase 6 - Backend Session Actor

Deliver:

```text
Mist server
session actor
in-memory store
WebSocket protocol
event dispatch
snapshot broadcast
serve-smoke
```

Acceptance:

```bash
gleam run -- serve-smoke examples/upstream/counter --store memory --port 8080 --timeout-ms 5000
gleam run -- verify-backend examples/upstream/counter --store memory
```

### Phase 7 - Local Durable Store

Deliver:

```text
Shelf local store
event log
snapshots
session recovery
duplicate event handling
stale revision rejection
```

Acceptance:

```bash
gleam run -- verify-backend examples/upstream/todo_mvc --store local
gleam run -- verify-durability examples/upstream/todo_mvc --store local
```

### Phase 8 - Arkanoid And Game Complexity

Deliver:

```text
Arkanoid terminal example
brick collision
score
deterministic terminal hash
bounded smoke verification
```

Acceptance:

```bash
gleam run -- play-smoke examples/terminal/arkanoid --ticks 1000 --timeout-ms 5000
gleam run -- verify examples/terminal/arkanoid --target terminal
```

### Phase 9 - PostgreSQL Durable Store

Deliver:

```text
pog-based Postgres store
idempotent schema setup
event log transactions
snapshot storage
replay tests
```

Acceptance:

```bash
gleam run -- store setup-postgres --database-url "$DATABASE_URL"
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- verify-durability examples/upstream/todo_mvc --store postgres
```

### Phase 10 - Lustre Durable Client

Deliver:

```text
generated Lustre target
websocket client
snapshot rendering
event sending
counter durable client
todo_mvc durable client
```

Acceptance:

```bash
gleam run -- web examples/upstream/counter --mode durable-client
gleam run -- serve-smoke examples/upstream/counter --store local --port 8080 --timeout-ms 5000
```

### Phase 11 - Multi-File And BUILD.bn

Deliver:

```text
multi-file project loader
BUILD.bn execution
VFS sandbox
generated-file manifest
Scene semantic tree
todo_mvc_physical semantic verification
```

Acceptance:

```bash
gleam run -- verify examples/upstream/todo_mvc_physical
gleam run -- verify-backend examples/upstream/todo_mvc_physical --store local
```

---

## 18. Definitions Of Done

Any false item means the milestone is incomplete.

### v0

```text
Gleam project builds and tests.
Compiler parses and lowers minimal, hello_world, counter.
Generated core update/view exists and is pure.
BoonGleamRuntimeHost exists.
Semantic expected runner works.
Counter events work.
Pong terminal play-smoke passes.
Pong verifies headlessly.
No non-Gleam implementation code is required.
```

Commands:

```bash
gleam test
gleam run -- verify examples/upstream/minimal
gleam run -- verify examples/upstream/hello_world
gleam run -- verify examples/upstream/counter
gleam run -- play-smoke examples/terminal/pong --ticks 1000 --timeout-ms 5000
gleam run -- verify examples/terminal/pong --target terminal
```

### v1

```text
TodoMVC semantic example passes.
Arkanoid play-smoke passes.
Terminal TUI has bounded smoke coverage and manual tmux/PTTY proof.
Backend server runs counter with memory store.
WebSocket client receives snapshots and sends events.
Local durability passes restart/replay tests.
```

Commands:

```bash
gleam run -- verify examples/upstream/todo_mvc
gleam run -- play-smoke examples/terminal/arkanoid --ticks 1000 --timeout-ms 5000
gleam run -- verify examples/terminal/arkanoid --target terminal
gleam run -- serve-smoke examples/upstream/counter --store memory --port 8080 --timeout-ms 5000
gleam run -- verify-backend examples/upstream/counter --store memory
gleam run -- verify-durability examples/upstream/counter --store local
```

### Durable Backend

```text
Postgres store is implemented.
Event log append is transactional.
Snapshots are saved and loaded.
Session actor restart replays state correctly.
Duplicate event ids return deterministic results.
Stale revisions are rejected.
Two WebSocket clients receive consistent snapshots.
TodoMVC passes backend verification with Postgres.
```

Commands:

```bash
gleam run -- store setup-postgres --database-url "$DATABASE_URL"
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- verify-durability examples/upstream/todo_mvc --store postgres
```

### Full-Stack Experiment

```text
Terminal target works.
Backend target works.
Lustre durable client works.
The same generated Boon core drives all targets.
Counter and TodoMVC run through terminal, backend, and web-client targets.
Durability and replay tests pass.
Structural guardrails pass.
```

Commands:

```bash
gleam run -- verify-all
gleam run -- verify-backend examples/upstream/todo_mvc --store postgres
gleam run -- web examples/upstream/todo_mvc --mode durable-client
```

---

## 19. Structural Guardrails

These searches are required before claiming a milestone complete. Update exact
patterns as the file layout evolves, but keep the intent.

```bash
# Generated core must not import IO/runtime adapters.
rg -n "gleam_erlang|gleam_otp|mist|shelf|pog|etch|lustre|File|Process|Timer" build/generated/*/src/generated_*/ \
  && exit 1 || true

# Verifiers must not use wall-clock sleeps.
rg -n "sleep|set_timeout|timer.sleep|process.sleep" src/verify src/terminal \
  && exit 1 || true

# Generated events must not collapse to untyped maps.
rg -n "Dict\\(String|Map\\(String|event_json.*Dict" build/generated \
  && exit 1 || true

# No hidden pass-through skips.
rg -n "TODO.*pass|fake pass|hardcode|skip.*example|empty snapshot" src \
  && exit 1 || true

# No source-name special casing in compiler/runtime.
rg -n "counter|todo_mvc|pong|arkanoid|cells" src/lowering src/runtime src/codegen \
  && exit 1 || true
```

If a guardrail has a legitimate false positive, add a narrow allowlist comment
near the code and include it in the verification report.

---

## 20. Codex Implementation Prompt

Use this prompt when asking Codex to create or continue the repository:

```text
Implement boon-gleam from BOON_GLEAM_IMPLEMENTATION_PLAN.md.

Do not add Zig, Rust, Pony, Raybox, Sokol, SDL, WebGPU, Slang, native renderer
work, or a custom Wasm runtime. Gleam JS + Lustre is allowed only for the web
target defined in the plan.

Start with Phase 0, then proceed phase by phase. Do not skip a phase acceptance
gate. Keep all targets going through the same generated init/update/view core.

Use BoonGleamRuntimeHost for verification. Use virtual time in all verifiers.
Do not hardcode example output. Do not fake passing tests. Unsupported syntax
must fail with named diagnostics and source spans.

When a phase is complete, produce the exact command outputs and report paths
listed in the plan before claiming completion.
```

---

## 21. Reference Links

```text
Gleam:
  https://gleam.run/
  https://gleam.run/news/

Erlang/OTP:
  https://www.erlang.org/news

Hex packages:
  https://hex.pm/packages/gleam_stdlib
  https://hex.pm/packages/gleam_erlang
  https://hex.pm/packages/gleam_otp
  https://hex.pm/packages/gleam_json
  https://hex.pm/packages/etch
  https://hex.pm/packages/mist
  https://hex.pm/packages/shelf
  https://hex.pm/packages/pog
  https://hex.pm/packages/lustre

Boon:
  https://github.com/BoonLang/boon
  https://github.com/BoonLang/boon-zig
```
