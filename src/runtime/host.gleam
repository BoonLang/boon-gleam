import codegen/core as core_codegen
import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import lowering/flowir.{
  type FlowButton, type FlowListItem, type FlowProgram, FlowButton, FlowListItem,
  NumericText, StableList, StaticDocument,
}
import lowering/pipeline
import project/loader
import project/project.{type Project}
import runtime/core.{
  type Effect, type Event, type InitContext, type Snapshot, type State,
  type TodoItem, ClickButton, ClickButtonNearText, ClickCheckbox, ClickText,
  HoverText, InitContext, NoEffect, NoEvent, SemanticNode, Snapshot, State,
  TodoItem,
}

pub type AppCore {
  AppCore(
    init: fn(InitContext) -> State,
    update: fn(State, Event) -> #(State, List(Effect)),
    view: fn(State) -> Snapshot,
  )
}

pub type BoonGleamRuntimeHost {
  BoonGleamRuntimeHost(core: AppCore)
}

pub type CompiledProject {
  CompiledProject(project: Project, flow: FlowProgram)
}

pub type Target {
  Core
  Terminal
  Backend
  Web
}

pub type GeneratedProject {
  GeneratedProject(
    project: Project,
    flow: FlowProgram,
    target: Target,
    output_path: String,
  )
}

pub type TimeSource {
  Virtual(now_ms: Int)
  Realtime
}

pub type RuntimeSession {
  RuntimeSession(
    generated: GeneratedProject,
    host: BoonGleamRuntimeHost,
    state: State,
    clock: TimeSource,
    stopped: Bool,
  )
}

pub type EventEnvelope {
  EventEnvelope(event_id: String, expected_revision: Int, event: Event)
}

pub type EventResult {
  EventResult(event_id: String, revision: Int, effects: List(Effect))
}

pub type SnapshotEnvelope {
  SnapshotEnvelope(revision: Int, snapshot: Snapshot)
}

pub fn load_project(path: String) -> Result(Project, Diagnostic) {
  loader.load(path) |> first_diagnostic
}

pub fn compile_project(
  project: Project,
) -> Result(CompiledProject, Diagnostic) {
  use program <- result_try(loader.parse_project(project) |> first_diagnostic)
  use flow <- result_try(
    pipeline.lower(project.name, project.entry_file.path, program)
    |> first_diagnostic,
  )
  Ok(CompiledProject(project: project, flow: flow))
}

pub fn codegen_project(
  compiled: CompiledProject,
  target: Target,
) -> Result(GeneratedProject, Diagnostic) {
  let CompiledProject(project: project, flow: flow) = compiled
  use output_path <- result_try(
    core_codegen.write(project.root, flow) |> first_diagnostic,
  )
  Ok(GeneratedProject(
    project: project,
    flow: flow,
    target: target,
    output_path: output_path,
  ))
}

pub fn start_session(
  generated: GeneratedProject,
  clock: TimeSource,
) -> Result(RuntimeSession, Diagnostic) {
  let host = from_flow(generated.flow)
  Ok(RuntimeSession(
    generated: generated,
    host: host,
    state: init(host, InitContext(seed: 0)),
    clock: clock,
    stopped: False,
  ))
}

pub fn dispatch(
  session: RuntimeSession,
  envelope: EventEnvelope,
) -> Result(EventResult, Diagnostic) {
  case session.stopped {
    True ->
      Error(runtime_error("runtime_session_stopped", "session is stopped"))
    False -> {
      let #(next_state, effects) =
        update(session.host, session.state, envelope.event)
      Ok(EventResult(
        event_id: envelope.event_id,
        revision: envelope.expected_revision + 1,
        effects: effects,
      ))
      |> result_map(fn(result) {
        let _next_session = RuntimeSession(..session, state: next_state)
        result
      })
    }
  }
}

pub fn advance_time(
  session: RuntimeSession,
  by_ms: Int,
) -> Result(RuntimeSession, Diagnostic) {
  case session.clock {
    Virtual(now_ms) ->
      Ok(RuntimeSession(..session, clock: Virtual(now_ms + by_ms)))
    Realtime -> Ok(session)
  }
}

pub fn wait_until_quiescent(
  session: RuntimeSession,
  max_steps: Int,
) -> Result(RuntimeSession, Diagnostic) {
  case max_steps < 0 {
    True ->
      Error(runtime_error(
        "runtime_not_quiescent",
        "max_steps was exhausted before the runtime became quiescent",
      ))
    False -> Ok(session)
  }
}

pub fn snapshot(
  session: RuntimeSession,
) -> Result(SnapshotEnvelope, Diagnostic) {
  Ok(SnapshotEnvelope(revision: 0, snapshot: view(session.host, session.state)))
}

pub fn stop_session(_session: RuntimeSession) -> Nil {
  Nil
}

pub fn init(host: BoonGleamRuntimeHost, context: InitContext) -> State {
  host.core.init(context)
}

pub fn update(
  host: BoonGleamRuntimeHost,
  state: State,
  event: Event,
) -> #(State, List(Effect)) {
  host.core.update(state, event)
}

pub fn view(host: BoonGleamRuntimeHost, state: State) -> Snapshot {
  host.core.view(state)
}

pub fn from_flow(flow: FlowProgram) -> BoonGleamRuntimeHost {
  BoonGleamRuntimeHost(
    core: AppCore(
      init: fn(_context) { initial_state(flow) },
      update: fn(state, event) { update_flow(flow, state, event) },
      view: fn(state) { state.snapshot },
    ),
  )
}

fn initial_state(flow: FlowProgram) -> State {
  case flow.core {
    NumericText(_) ->
      State(
        count: 0,
        input: "",
        items: [],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "",
        snapshot: numeric_snapshot(flow.name, 0),
      )
    StableList(spec) -> {
      let todos =
        list.map(spec.initial_items, fn(item) {
          TodoItem(title: stable_item_title(item), completed: False)
        })
      State(
        count: spec.next_id,
        input: "",
        items: [],
        todos: todos,
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "stable_list",
        snapshot: stable_list_snapshot(flow.name, spec.title, todos),
      )
    }
    _ ->
      State(
        count: 0,
        input: "",
        items: [],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "",
        snapshot: Snapshot(text: flow.snapshot_text, semantic_nodes: []),
      )
  }
}

fn update_flow(
  flow: FlowProgram,
  state: State,
  event: Event,
) -> #(State, List(Effect)) {
  case flow.core, event {
    StaticDocument(_), HoverText(text) -> #(State(..state, hovered: text), [
      NoEffect,
    ])
    NumericText(buttons), ClickButton(index) -> {
      let next_count = state.count + button_delta(buttons, index)
      #(
        State(
          ..state,
          count: next_count,
          snapshot: numeric_snapshot(flow.name, next_count),
        ),
        [NoEffect],
      )
    }
    StableList(spec), ClickText(label) if label == spec.add_label -> {
      let item =
        TodoItem(
          title: "New Item (id=" <> int.to_string(state.count) <> ")",
          completed: False,
        )
      let todos = list.append(state.todos, [item])
      #(
        State(
          ..state,
          count: state.count + 1,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [NoEffect],
      )
    }
    StableList(spec), ClickText(label) if label == spec.clear_completed_label -> {
      let todos = list.filter(state.todos, fn(item) { !item.completed })
      #(
        State(
          ..state,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [NoEffect],
      )
    }
    StableList(spec), ClickCheckbox(index) -> {
      let todos = toggle_todo_at(state.todos, index)
      #(
        State(
          ..state,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [NoEffect],
      )
    }
    StableList(spec), ClickButtonNearText(text, _) -> {
      let todos = list.filter(state.todos, fn(item) { item.title != text })
      #(
        State(
          ..state,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [NoEffect],
      )
    }
    _, NoEvent -> #(state, [])
    _, _ -> #(state, [NoEffect])
  }
}

fn button_delta(buttons: List(FlowButton), index: Int) -> Int {
  case buttons, index {
    [], _ -> 0
    [FlowButton(_, delta), ..], 0 -> delta
    [_button, ..rest], _ -> button_delta(rest, index - 1)
  }
}

fn numeric_snapshot(name: String, count: Int) -> Snapshot {
  Snapshot(text: int.to_string(count) <> "+", semantic_nodes: [
    SemanticNode(id: name <> "-count", path: "text", text: int.to_string(count)),
    SemanticNode(id: name <> "-button-0", path: "button", text: "+"),
  ])
}

fn stable_list_snapshot(
  name: String,
  title: String,
  todos: List(TodoItem),
) -> Snapshot {
  let active_count = list.count(todos, fn(item) { !item.completed })
  let completed_count = list.count(todos, fn(item) { item.completed })
  let rows =
    todos
    |> list.map(fn(item) {
      item.title
      <> case item.completed {
        True -> " [X]"
        False -> " [ ]"
      }
    })
    |> string_join("\n")
  let text =
    title
    <> "\nAdd Item\n"
    <> case completed_count > 0 {
      True -> "Clear completed\n"
      False -> ""
    }
    <> rows
    <> "\nActive: "
    <> int.to_string(active_count)
    <> ", Completed: "
    <> int.to_string(completed_count)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn stable_item_title(item: FlowListItem) -> String {
  let FlowListItem(id, name) = item
  name <> " (id=" <> int.to_string(id) <> ")"
}

fn toggle_todo_at(todos: List(TodoItem), index: Int) -> List(TodoItem) {
  case todos {
    [] -> []
    [item, ..rest] if index == 0 -> [
      TodoItem(..item, completed: !item.completed),
      ..rest
    ]
    [item, ..rest] -> [item, ..toggle_todo_at(rest, index - 1)]
  }
}

fn string_join(values: List(String), separator: String) -> String {
  case values {
    [] -> ""
    [first, ..rest] -> string_join_loop(rest, separator, first)
  }
}

fn string_join_loop(
  values: List(String),
  separator: String,
  acc: String,
) -> String {
  case values {
    [] -> acc
    [value, ..rest] ->
      string_join_loop(rest, separator, acc <> separator <> value)
  }
}

fn runtime_error(code: String, message: String) -> Diagnostic {
  error(
    code: code,
    path: "BoonGleamRuntimeHost",
    line: 1,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: message,
    help: "runtime host sessions must be active and quiescent",
  )
}

fn first_diagnostic(
  result: Result(a, List(Diagnostic)),
) -> Result(a, Diagnostic) {
  case result {
    Ok(value) -> Ok(value)
    Error([]) ->
      Error(runtime_error(
        "diagnostic_missing",
        "operation failed without diagnostics",
      ))
    Error([diagnostic, ..]) -> Error(diagnostic)
  }
}

fn result_try(
  result: Result(a, Diagnostic),
  next: fn(a) -> Result(b, Diagnostic),
) -> Result(b, Diagnostic) {
  case result {
    Ok(value) -> next(value)
    Error(diagnostic) -> Error(diagnostic)
  }
}

fn result_map(result: Result(a, e), transform: fn(a) -> b) -> Result(b, e) {
  case result {
    Ok(value) -> Ok(transform(value))
    Error(error) -> Error(error)
  }
}
