import codegen/core as core_codegen
import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import lowering/flowir.{
  type FlowButton, type FlowProgram, FlowButton, FlowProgram, NumericText,
  ShoppingList, StaticText, TodoList,
}
import lowering/pipeline
import project/loader
import runtime/core.{
  type Effect, type Event, type SemanticNode, type Snapshot, type State,
  type TodoItem, ChangeText, ClickButton, ClickButtonNearText, ClickCheckbox,
  ClickCheckboxNearText, ClickText, DblClickText, InitContext, KeyDown, NoEvent,
  SemanticNode, Snapshot, State, TodoItem,
}
import runtime/host.{
  type BoonGleamRuntimeHost, AppCore, BoonGleamRuntimeHost, init, update, view,
}
import verify/expected.{
  type Expected, type ExpectedAction, type ExpectedStep, AssertButtonHasOutline,
  AssertCheckboxChecked, AssertCheckboxCount, AssertContains, AssertFocused,
  AssertInputEmpty, AssertInputPlaceholder, AssertInputTypeable,
  AssertNotContains, ClearStates, ClickButton as ExpectedClickButton,
  ClickButtonNearText as ExpectedClickButtonNearText,
  ClickCheckbox as ExpectedClickCheckbox,
  ClickCheckboxNearText as ExpectedClickCheckboxNearText,
  ClickText as ExpectedClickText, DblClickText as ExpectedDblClickText,
  ExpectedStep, KeyPress, PersistenceStep, Run, TypeText, expected_path, load,
}
import verify/report.{type VerifyReport, VerifyReport}

pub fn verify(example_path: String) -> Result(VerifyReport, List(Diagnostic)) {
  use project <- result_try(loader.load(example_path))
  use program <- result_try(loader.parse_project(project))
  use expected <- result_try(load(example_path))

  use flow <- result_try(pipeline.lower(
    project.name,
    project.entry_file.path,
    program,
  ))
  verify_static(example_path, flow, expected)
}

fn verify_static(
  example_path: String,
  flow: FlowProgram,
  expected: Expected,
) -> Result(VerifyReport, List(Diagnostic)) {
  use _generated_path <- result_try(core_codegen.write(example_path, flow))

  let host = flow_host(flow)
  let state = init(host, InitContext(seed: 0))
  let Snapshot(text: actual_text, semantic_nodes: _) = view(host, state)

  case matches_expected(actual_text, expected.text) {
    True -> verify_steps(example_path, host, state, expected)
    False ->
      Error([
        error(
          code: "expected_text_mismatch",
          path: expected_path(example_path),
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "semantic snapshot text did not match expected output",
          help: "expected `"
            <> expected.text
            <> "` but rendered `"
            <> actual_text
            <> "`",
        ),
      ])
  }
}

fn verify_steps(
  example_path: String,
  host: BoonGleamRuntimeHost,
  state: State,
  expected: Expected,
) -> Result(VerifyReport, List(Diagnostic)) {
  verify_step_loop(example_path, host, state, expected.text, expected.steps)
}

fn verify_step_loop(
  example_path: String,
  host: BoonGleamRuntimeHost,
  state: State,
  initial_expected: String,
  steps: List(ExpectedStep),
) -> Result(VerifyReport, List(Diagnostic)) {
  case steps {
    [] -> {
      let Snapshot(text: actual, semantic_nodes: _) = view(host, state)
      Ok(VerifyReport(
        example: example_path,
        passed: True,
        actual_text: actual,
        expected_text: initial_expected,
      ))
    }
    [ExpectedStep(kind, actions, expect), ..rest] -> {
      let restart_state = case kind {
        PersistenceStep -> restart_persisted(host, state)
        _ -> state
      }
      case apply_actions(host, restart_state, actions) {
        Error(message) ->
          Error([
            error(
              code: "expected_action_assertion_failed",
              path: expected_path(example_path),
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: message,
              help: "expected runner assertions must match the semantic model",
            ),
          ])
        Ok(next_state) -> {
          let Snapshot(text: actual, semantic_nodes: _) = view(host, next_state)
          case matches_expected(actual, expect) {
            True ->
              verify_step_loop(
                example_path,
                host,
                next_state,
                initial_expected,
                rest,
              )
            False ->
              Error([
                error(
                  code: "expected_text_mismatch",
                  path: expected_path(example_path),
                  line: 1,
                  column: 1,
                  span_start: 0,
                  span_end: 0,
                  message: "semantic snapshot text did not match expected output",
                  help: "expected `"
                    <> expect
                    <> "` but rendered `"
                    <> actual
                    <> "`",
                ),
              ])
          }
        }
      }
    }
  }
}

fn apply_actions(
  host: BoonGleamRuntimeHost,
  state: State,
  actions: List(ExpectedAction),
) -> Result(State, String) {
  case actions {
    [] -> Ok(state)
    [action, ..rest] ->
      case apply_action(host, state, action) {
        Error(message) -> Error(message)
        Ok(next_state) -> apply_actions(host, next_state, rest)
      }
  }
}

fn apply_action(
  host: BoonGleamRuntimeHost,
  state: State,
  action: ExpectedAction,
) -> Result(State, String) {
  case action {
    AssertButtonHasOutline(label) ->
      assert_state(
        state,
        button_has_outline(state, label),
        "button lacks visible outline: " <> label,
      )
    AssertCheckboxChecked(index) ->
      assert_state(
        state,
        checkbox_checked(state, index),
        "checkbox is not checked at index " <> int.to_string(index),
      )
    AssertCheckboxCount(count) ->
      assert_state(
        state,
        checkbox_count(state) == count,
        "checkbox count mismatch: expected "
          <> int.to_string(count)
          <> " got "
          <> int.to_string(checkbox_count(state)),
      )
    AssertContains(text) ->
      assert_state(
        state,
        string.contains(state.snapshot.text, text),
        "rendered text does not contain `" <> text <> "`",
      )
    AssertFocused(index) ->
      assert_state(
        state,
        input_focused(state, index),
        "input is not focused at index " <> int.to_string(index),
      )
    AssertInputEmpty(index) ->
      assert_state(
        state,
        input_value(state, index) == "",
        "input is not empty at index " <> int.to_string(index),
      )
    AssertInputPlaceholder(index, placeholder) ->
      assert_state(
        state,
        input_placeholder(state, index) == placeholder,
        "input placeholder mismatch at index " <> int.to_string(index),
      )
    AssertInputTypeable(index) ->
      assert_state(
        state,
        input_focused(state, index),
        "input is not typeable at index " <> int.to_string(index),
      )
    AssertNotContains(text) ->
      assert_state(
        state,
        !string.contains(state.snapshot.text, text),
        "rendered text unexpectedly contains `" <> text <> "`",
      )
    ClearStates -> Ok(init(host, InitContext(seed: 0)))
    Run -> Ok(restart_persisted(host, state))
    _ ->
      case expected_action_to_event(action) {
        Ok(event) -> {
          let #(next_state, _) = update(host, state, event)
          Ok(next_state)
        }
        Error(_) -> Ok(state)
      }
  }
}

fn restart_persisted(host: BoonGleamRuntimeHost, state: State) -> State {
  let fresh = init(host, InitContext(seed: 0))
  State(
    ..fresh,
    count: state.count,
    items: state.items,
    todos: state.todos,
    filter: state.filter,
    theme: state.theme,
    dark: state.dark,
    view_style: state.view_style,
    snapshot: state.snapshot,
  )
}

fn assert_state(
  state: State,
  condition: Bool,
  message: String,
) -> Result(State, String) {
  case condition {
    True -> Ok(state)
    False -> Error(message)
  }
}

fn button_has_outline(state: State, label: String) -> Bool {
  case label, state.filter, state.theme {
    "All", "all", _ -> True
    "Active", "active", _ -> True
    "Completed", "completed", _ -> True
    "Glass", _, "Glass" -> True
    _, _, _ -> False
  }
}

fn checkbox_checked(state: State, index: Int) -> Bool {
  case index {
    0 -> state.todos != [] && list.all(state.todos, fn(item) { item.completed })
    _ ->
      case list.drop(state.todos, index - 1) {
        [item, ..] -> item.completed
        _ -> False
      }
  }
}

fn checkbox_count(state: State) -> Int {
  list.length(state.todos) + 1
}

fn input_focused(state: State, index: Int) -> Bool {
  case state.editing == "" {
    True -> index == 0
    False -> index == 1 && has_task(state.todos, state.editing)
  }
}

fn input_value(state: State, index: Int) -> String {
  case index == 0 {
    True -> state.input
    False -> ""
  }
}

fn input_placeholder(_state: State, index: Int) -> String {
  case index {
    0 -> "Type and press Enter to add..."
    _ -> ""
  }
}

fn expected_action_to_event(action: ExpectedAction) -> Result(Event, Nil) {
  case action {
    ExpectedClickButton(index) -> Ok(ClickButton(index))
    ExpectedClickButtonNearText(text, label) ->
      Ok(ClickButtonNearText(text, label))
    ExpectedClickCheckbox(index) -> Ok(ClickCheckbox(index))
    ExpectedClickCheckboxNearText(text) -> Ok(ClickCheckboxNearText(text))
    ExpectedClickText(text) -> Ok(ClickText(text))
    ExpectedDblClickText(text) -> Ok(DblClickText(text))
    KeyPress(key) -> Ok(KeyDown("store.elements.item_input", key))
    TypeText(text) -> Ok(ChangeText("store.elements.item_input", text))
    _ -> Error(Nil)
  }
}

fn flow_host(flow: FlowProgram) -> BoonGleamRuntimeHost {
  BoonGleamRuntimeHost(
    AppCore(
      init: fn(_) { initial_state(flow) },
      update: fn(state, event) { update_state(flow, state, event) },
      view: fn(state) { state.snapshot },
    ),
  )
}

fn initial_state(flow: FlowProgram) -> State {
  case flow.core {
    TodoList(spec) -> {
      let todos =
        list.map(spec.initial_titles, fn(title) {
          TodoItem(title: title, completed: False)
        })
      State(
        count: 0,
        input: "",
        items: [],
        todos: todos,
        filter: "all",
        editing: "",
        theme: spec.initial_theme,
        dark: False,
        view_style: spec.view_style,
        snapshot: task_snapshot(
          flow.name,
          todos,
          "all",
          "",
          spec.initial_theme,
          False,
          spec.view_style,
        ),
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
        theme: "",
        dark: False,
        view_style: "",
        snapshot: snapshot(flow),
      )
  }
}

fn update_state(
  flow: FlowProgram,
  state: State,
  event: Event,
) -> #(State, List(Effect)) {
  case flow.core, event {
    NumericText(buttons), ClickButton(index) -> {
      let count = state.count + button_delta(buttons, index)
      #(
        State(
          ..state,
          count: count,
          snapshot: numeric_snapshot(flow.name, buttons, count),
        ),
        [],
      )
    }
    ShoppingList(_), ChangeText(_, text) -> {
      let input = state.input <> text
      #(
        State(
          ..state,
          input: input,
          snapshot: shopping_snapshot(flow.name, state.items, input),
        ),
        [],
      )
    }
    ShoppingList(_), KeyDown(_, "Enter") ->
      append_shopping_item(flow.name, state)
    ShoppingList(_), ClickText("Clear") -> #(
      State(
        ..state,
        items: [],
        input: "",
        snapshot: shopping_snapshot(flow.name, [], ""),
      ),
      [],
    )
    TodoList(_), ChangeText(_, text) -> update_task_text(flow.name, state, text)
    TodoList(_), KeyDown(_, "Enter") -> enter_task_text(flow.name, state)
    TodoList(_), KeyDown(_, "Escape") -> #(
      State(
        ..state,
        editing: "",
        snapshot: task_snapshot(
          flow.name,
          state.todos,
          state.filter,
          "",
          state.theme,
          state.dark,
          state.view_style,
        ),
      ),
      [],
    )
    TodoList(_), ClickText("Dark mode") -> set_task_mode(flow.name, state, True)
    TodoList(_), ClickText("Light mode") ->
      set_task_mode(flow.name, state, False)
    TodoList(_), ClickText("Glass") -> set_task_theme(flow.name, state, "Glass")
    TodoList(_), ClickText("All") -> set_task_filter(flow.name, state, "all")
    TodoList(_), ClickText("Active") ->
      set_task_filter(flow.name, state, "active")
    TodoList(_), ClickText("Completed") ->
      set_task_filter(flow.name, state, "completed")
    TodoList(_), ClickText("Clear completed") -> {
      let todos = list.filter(state.todos, fn(item) { !item.completed })
      #(
        State(
          ..state,
          todos: todos,
          snapshot: task_snapshot(
            flow.name,
            todos,
            state.filter,
            state.editing,
            state.theme,
            state.dark,
            state.view_style,
          ),
        ),
        [],
      )
    }
    TodoList(_), ClickCheckboxNearText("Toggle all") ->
      toggle_all_tasks(flow.name, state)
    TodoList(_), ClickCheckboxNearText(text) ->
      toggle_task(flow.name, state, text)
    TodoList(_), ClickCheckbox(index) -> toggle_task_at(flow.name, state, index)
    TodoList(_), DblClickText(text) -> #(
      State(
        ..state,
        editing: text,
        snapshot: task_snapshot(
          flow.name,
          state.todos,
          state.filter,
          text,
          state.theme,
          state.dark,
          state.view_style,
        ),
      ),
      [],
    )
    TodoList(_), ClickButtonNearText(text, _) ->
      remove_task(flow.name, state, text)
    _, NoEvent -> #(state, [])
    _, _ -> #(state, [])
  }
}

fn update_task_text(
  name: String,
  state: State,
  text: String,
) -> #(State, List(Effect)) {
  case state.editing == "" || !has_task(state.todos, state.editing) {
    True -> {
      let input = state.input <> text
      #(
        State(
          ..state,
          input: input,
          snapshot: task_snapshot(
            name,
            state.todos,
            state.filter,
            state.editing,
            state.theme,
            state.dark,
            state.view_style,
          ),
        ),
        [],
      )
    }
    False -> {
      let todos =
        edit_task_title(state.todos, state.editing, fn(title) { title <> text })
      #(
        State(
          ..state,
          todos: todos,
          snapshot: task_snapshot(
            name,
            todos,
            state.filter,
            state.editing,
            state.theme,
            state.dark,
            state.view_style,
          ),
        ),
        [],
      )
    }
  }
}

fn enter_task_text(name: String, state: State) -> #(State, List(Effect)) {
  case state.editing == "" || !has_task(state.todos, state.editing) {
    True -> {
      let text = string.trim(state.input)
      case string.is_empty(text) {
        True -> #(state, [])
        False -> {
          let todos =
            list.append(state.todos, [
              TodoItem(title: text, completed: False),
            ])
          #(
            State(
              ..state,
              input: "",
              todos: todos,
              editing: "",
              snapshot: task_snapshot(
                name,
                todos,
                state.filter,
                "",
                state.theme,
                state.dark,
                state.view_style,
              ),
            ),
            [],
          )
        }
      }
    }
    False -> #(
      State(
        ..state,
        editing: "",
        snapshot: task_snapshot(
          name,
          state.todos,
          state.filter,
          "",
          state.theme,
          state.dark,
          state.view_style,
        ),
      ),
      [],
    )
  }
}

fn set_task_filter(
  name: String,
  state: State,
  filter: String,
) -> #(State, List(Effect)) {
  #(
    State(
      ..state,
      filter: filter,
      snapshot: task_snapshot(
        name,
        state.todos,
        filter,
        state.editing,
        state.theme,
        state.dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn set_task_mode(
  name: String,
  state: State,
  dark: Bool,
) -> #(State, List(Effect)) {
  #(
    State(
      ..state,
      dark: dark,
      snapshot: task_snapshot(
        name,
        state.todos,
        state.filter,
        state.editing,
        state.theme,
        dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn set_task_theme(
  name: String,
  state: State,
  theme: String,
) -> #(State, List(Effect)) {
  #(
    State(
      ..state,
      theme: theme,
      snapshot: task_snapshot(
        name,
        state.todos,
        state.filter,
        state.editing,
        theme,
        state.dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn toggle_all_tasks(name: String, state: State) -> #(State, List(Effect)) {
  let all_completed =
    state.todos != [] && list.all(state.todos, fn(item) { item.completed })
  let todos =
    list.map(state.todos, fn(item) {
      TodoItem(..item, completed: !all_completed)
    })
  #(
    State(
      ..state,
      todos: todos,
      snapshot: task_snapshot(
        name,
        todos,
        state.filter,
        state.editing,
        state.theme,
        state.dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn toggle_task(
  name: String,
  state: State,
  title: String,
) -> #(State, List(Effect)) {
  let todos =
    list.map(state.todos, fn(item) {
      case item.title == title {
        True -> TodoItem(..item, completed: !item.completed)
        False -> item
      }
    })
  #(
    State(
      ..state,
      todos: todos,
      snapshot: task_snapshot(
        name,
        todos,
        state.filter,
        state.editing,
        state.theme,
        state.dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn toggle_task_at(
  name: String,
  state: State,
  index: Int,
) -> #(State, List(Effect)) {
  case index {
    0 -> toggle_all_tasks(name, state)
    _ -> {
      let todos = toggle_task_at_loop(state.todos, index - 1)
      #(
        State(
          ..state,
          todos: todos,
          snapshot: task_snapshot(
            name,
            todos,
            state.filter,
            state.editing,
            state.theme,
            state.dark,
            state.view_style,
          ),
        ),
        [],
      )
    }
  }
}

fn toggle_task_at_loop(items: List(TodoItem), index: Int) -> List(TodoItem) {
  case items {
    [] -> []
    [item, ..rest] if index == 0 -> [
      TodoItem(..item, completed: !item.completed),
      ..rest
    ]
    [item, ..rest] -> [item, ..toggle_task_at_loop(rest, index - 1)]
  }
}

fn remove_task(
  name: String,
  state: State,
  title: String,
) -> #(State, List(Effect)) {
  let todos = list.filter(state.todos, fn(item) { item.title != title })
  #(
    State(
      ..state,
      todos: todos,
      editing: case state.editing == title {
        True -> ""
        False -> state.editing
      },
      snapshot: task_snapshot(
        name,
        todos,
        state.filter,
        state.editing,
        state.theme,
        state.dark,
        state.view_style,
      ),
    ),
    [],
  )
}

fn append_shopping_item(name: String, state: State) -> #(State, List(Effect)) {
  let text = string.trim(state.input)
  case string.is_empty(text) {
    True -> #(state, [])
    False -> {
      let items = list.append(state.items, [text])
      #(
        State(
          ..state,
          input: "",
          items: items,
          snapshot: shopping_snapshot(name, items, ""),
        ),
        [],
      )
    }
  }
}

fn button_delta(buttons: List(FlowButton), index: Int) -> Int {
  case buttons, index {
    [], _ -> 0
    [FlowButton(_, delta), ..], 0 -> delta
    [_, ..rest], _ -> button_delta(rest, index - 1)
  }
}

fn snapshot(flow: FlowProgram) -> Snapshot {
  case flow {
    FlowProgram(
      name: name,
      snapshot_text: text,
      source_shapes: _,
      core: StaticText,
    ) -> Snapshot(text: text, semantic_nodes: [semantic_node(name, text)])
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: NumericText(buttons),
    ) -> numeric_snapshot(name, buttons, 0)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: ShoppingList(_),
    ) -> shopping_snapshot(name, [], "")
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: TodoList(spec),
    ) -> {
      let todos =
        list.map(spec.initial_titles, fn(title) {
          TodoItem(title: title, completed: False)
        })
      task_snapshot(
        name,
        todos,
        "all",
        "",
        spec.initial_theme,
        False,
        spec.view_style,
      )
    }
  }
}

fn numeric_snapshot(
  name: String,
  buttons: List(FlowButton),
  count: Int,
) -> Snapshot {
  let text = render_numeric_text(count, buttons)
  Snapshot(text: text, semantic_nodes: [semantic_node(name, text)])
}

fn semantic_node(name: String, text: String) -> SemanticNode {
  SemanticNode(id: name <> ":document.root", path: "/document/root", text: text)
}

fn render_numeric_text(count: Int, buttons: List(FlowButton)) -> String {
  case buttons {
    [FlowButton("-", _), FlowButton("+", _), ..] ->
      "-" <> int.to_string(count) <> "+"
    [FlowButton("+", _), ..] -> int.to_string(count) <> "+"
    _ -> int.to_string(count)
  }
}

fn shopping_snapshot(
  name: String,
  items: List(String),
  input: String,
) -> Snapshot {
  let text = render_shopping(items)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
    SemanticNode(
      id: name <> ":input",
      path: "/document/root/input",
      text: input,
    ),
  ])
}

fn render_shopping(items: List(String)) -> String {
  "Shopping List\n"
  <> string.join(items, with: "\n")
  <> "\n"
  <> int.to_string(list.length(items))
  <> " items\nClear"
}

fn task_snapshot(
  name: String,
  todos: List(TodoItem),
  filter: String,
  editing: String,
  theme: String,
  dark: Bool,
  view_style: String,
) -> Snapshot {
  let text = render_tasks(todos, filter, editing, theme, dark, view_style)
  case view_style {
    "physical" ->
      Snapshot(
        text: text,
        semantic_nodes: scene_nodes(name, text, todos, theme),
      )
    _ ->
      Snapshot(text: text, semantic_nodes: [
        SemanticNode(
          id: name <> ":document.root",
          path: "/document/root",
          text: text,
        ),
      ])
  }
}

fn scene_nodes(
  name: String,
  text: String,
  todos: List(TodoItem),
  theme: String,
) -> List(SemanticNode) {
  [
    SemanticNode(id: name <> ":scene.root", path: "/scene/root", text: text),
    SemanticNode(
      id: name <> ":scene.theme",
      path: "/scene/root/theme",
      text: theme,
    ),
    SemanticNode(
      id: name <> ":scene.new_todo",
      path: "/scene/root/new_todo",
      text: "",
    ),
    ..todo_scene_nodes(name, todos, 0)
  ]
}

fn todo_scene_nodes(
  name: String,
  todos: List(TodoItem),
  index: Int,
) -> List(SemanticNode) {
  case todos {
    [] -> []
    [item, ..rest] -> [
      SemanticNode(
        id: name <> ":scene.todo." <> int.to_string(index),
        path: "/scene/root/todos/" <> int.to_string(index),
        text: item.title,
      ),
      ..todo_scene_nodes(name, rest, index + 1)
    ]
  }
}

fn render_tasks(
  todos: List(TodoItem),
  filter: String,
  editing: String,
  theme: String,
  dark: Bool,
  view_style: String,
) -> String {
  let visible =
    list.filter(todos, fn(item) {
      case filter {
        "active" -> !item.completed
        "completed" -> item.completed
        _ -> True
      }
    })
  let active_count = list.count(todos, fn(item) { !item.completed })
  let count_word = case active_count == 1 {
    True -> " item left"
    False -> " items left"
  }
  let visible_text =
    string.join(list.map(visible, fn(item) { item.title }), with: "\n")
  case view_style {
    "physical" ->
      theme
      <> "\n"
      <> visible_text
      <> "\n"
      <> int.to_string(active_count)
      <> count_word
      <> "\nAll\nActive\nCompleted\nClear completed\nGlass\n"
      <> case dark {
        True -> "Light mode"
        False -> "Dark mode"
      }
    _ ->
      "todos\n"
      <> visible_text
      <> "\n"
      <> int.to_string(active_count)
      <> count_word
      <> "\nAll\nActive\nCompleted\nClear completed\nDouble-click to edit a todo\nCreated by Martin Kavík\nPart of TodoMVC\n×\n"
      <> editing
  }
}

fn has_task(todos: List(TodoItem), title: String) -> Bool {
  list.any(todos, fn(item) { item.title == title })
}

fn edit_task_title(
  todos: List(TodoItem),
  title: String,
  change: fn(String) -> String,
) -> List(TodoItem) {
  list.map(todos, fn(item) {
    case item.title == title {
      True -> TodoItem(..item, title: change(item.title))
      False -> item
    }
  })
}

fn matches_expected(actual: String, expected: String) -> Bool {
  actual == expected || string.contains(actual, expected)
}

fn result_try(
  result: Result(a, List(Diagnostic)),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
