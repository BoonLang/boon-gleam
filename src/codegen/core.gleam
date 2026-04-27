import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import lowering/flowir.{
  type FlowButton, type FlowProgram, FlowButton, NumericText, ShoppingList,
  StaticText, TodoList,
}
import support/file

pub fn write(
  example_path: String,
  flow: FlowProgram,
) -> Result(String, List(Diagnostic)) {
  let name = safe_name(flow.name)
  let root = "build/generated/" <> name
  let module_dir = root <> "/src/generated_" <> name

  case file.make_dir_all(module_dir) {
    Ok(_) -> {
      use _ <- result_try(write_file(
        root <> "/gleam.toml",
        generated_toml(name),
      ))
      use _ <- result_try(write_file(
        root <> "/src/generated_" <> name <> ".gleam",
        root_module(name),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/types.gleam",
        types_module(),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/state.gleam",
        state_module(name, flow),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/event.gleam",
        event_module(flow),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/effect.gleam",
        effect_module(),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/update.gleam",
        update_module(name, flow),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/view.gleam",
        view_module(name, flow),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/encode.gleam",
        empty_module("encode"),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/decode.gleam",
        empty_module("decode"),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/terminal_adapter.gleam",
        empty_module("terminal_adapter"),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/backend_adapter.gleam",
        empty_module("backend_adapter"),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/lustre_adapter.gleam",
        empty_module("lustre_adapter"),
      ))
      Ok(root)
    }
    Error(message) ->
      Error([io_error(example_path, "generated_dir_failed", message)])
  }
}

fn write_file(path: String, contents: String) -> Result(Nil, List(Diagnostic)) {
  case file.write_text_file(path, contents) {
    Ok(value) -> Ok(value)
    Error(message) -> Error([io_error(path, "generated_write_failed", message)])
  }
}

fn io_error(path: String, code: String, message: String) -> Diagnostic {
  error(
    code: code,
    path: path,
    line: 1,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: message,
    help: "generated outputs are written under build/generated",
  )
}

fn generated_toml(name: String) -> String {
  "name = \"generated_"
  <> name
  <> "\"\n"
  <> "version = \"0.1.0\"\n"
  <> "target = \"erlang\"\n\n"
  <> "[dependencies]\n"
  <> "gleam_stdlib = \"1.0.0\"\n"
  <> "gleam_json = \"3.1.0\"\n"
}

fn root_module(name: String) -> String {
  "import generated_"
  <> name
  <> "/state\n"
  <> "import generated_"
  <> name
  <> "/update\n"
  <> "import generated_"
  <> name
  <> "/view\n\n"
  <> "pub fn init(context) { state.init(context) }\n"
  <> "pub fn update(state, event) { update.update(state, event) }\n"
  <> "pub fn view(state) { view.view(state) }\n"
}

fn types_module() -> String {
  "pub type InitContext { InitContext(seed: Int) }\n\n"
  <> "pub type Snapshot { Snapshot(text: String) }\n"
}

fn state_module(name: String, flow: FlowProgram) -> String {
  case flow.core {
    StaticText ->
      "import generated_"
      <> name
      <> "/types.{type InitContext, type Snapshot, Snapshot}\n\n"
      <> "pub type State { State(snapshot: Snapshot) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(snapshot: view_snapshot()) }\n\n"
      <> "fn view_snapshot() { Snapshot(text: \""
      <> escape_string(flow.snapshot_text)
      <> "\") }\n"
    NumericText(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(count: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(count: 0) }\n"
    ShoppingList(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(input: String, items: List(String)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(input: \"\", items: []) }\n"
    TodoList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type TodoItem { TodoItem(title: String, completed: Bool) }\n\n"
      <> "pub type State { State(input: String, todos: List(TodoItem), filter: String, editing: String, theme: String, dark: Bool, view_style: String) }\n\n"
      <> "pub fn init(_context: InitContext) -> State {\n"
      <> "  State(input: \"\", todos: "
      <> generated_todo_items(spec.initial_titles)
      <> ", filter: \"all\", editing: \"\", theme: \""
      <> escape_string(spec.initial_theme)
      <> "\", dark: False, view_style: \""
      <> escape_string(spec.view_style)
      <> "\")\n"
      <> "}\n"
  }
}

fn event_module(flow: FlowProgram) -> String {
  case flow.core {
    StaticText -> "pub type Event { NoEvent }\n"
    NumericText(_) -> "pub type Event { NoEvent ClickButton(index: Int) }\n"
    ShoppingList(_) ->
      "pub type Event { NoEvent ChangeText(link_id: String, text: String) KeyDown(link_id: String, key: String) ClickText(text: String) }\n"
    TodoList(_) ->
      "pub type Event { NoEvent ChangeText(link_id: String, text: String) KeyDown(link_id: String, key: String) ClickText(text: String) ClickCheckbox(index: Int) ClickCheckboxNearText(text: String) DblClickText(text: String) ClickButtonNearText(text: String, label: String) }\n"
  }
}

fn effect_module() -> String {
  "pub type Effect { NoEffect }\n"
}

fn update_module(name: String, flow: FlowProgram) -> String {
  let imports =
    "import generated_"
    <> name
    <> "/effect.{type Effect}\n"
    <> "import generated_"
    <> name
    <> "/event.{type Event"
  case flow.core {
    StaticText ->
      imports
      <> "}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n\n"
      <> "pub fn update(state: State, _event: Event) -> #(State, List(Effect)) { #(state, []) }\n"
    NumericText(buttons) ->
      imports
      <> ", ClickButton, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickButton(index) -> #(State(count: state.count + button_delta(index)), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> button_delta_function(buttons)
    ShoppingList(_) ->
      imports
      <> ", ChangeText, ClickText, KeyDown, NoEvent}\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ChangeText(_, text) -> #(State(..state, input: state.input <> text), [])\n"
      <> "    KeyDown(_, \"Enter\") -> append_item(state)\n"
      <> "    KeyDown(_, _) -> #(state, [])\n"
      <> "    ClickText(\"Clear\") -> #(State(input: \"\", items: []), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn append_item(state: State) -> #(State, List(Effect)) {\n"
      <> "  let text = string.trim(state.input)\n"
      <> "  case string.is_empty(text) {\n"
      <> "    True -> #(state, [])\n"
      <> "    False -> #(State(input: \"\", items: list.append(state.items, [text])), [])\n"
      <> "  }\n"
      <> "}\n"
    TodoList(_) ->
      imports
      <> ", ChangeText, ClickButtonNearText, ClickCheckbox, ClickCheckboxNearText, ClickText, DblClickText, KeyDown, NoEvent}\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem, State, TodoItem}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ChangeText(_, text) -> change_text(state, text)\n"
      <> "    KeyDown(_, \"Enter\") -> enter_text(state)\n"
      <> "    KeyDown(_, \"Escape\") -> #(State(..state, editing: \"\"), [])\n"
      <> "    KeyDown(_, _) -> #(state, [])\n"
      <> "    ClickText(\"All\") -> #(State(..state, filter: \"all\"), [])\n"
      <> "    ClickText(\"Active\") -> #(State(..state, filter: \"active\"), [])\n"
      <> "    ClickText(\"Completed\") -> #(State(..state, filter: \"completed\"), [])\n"
      <> "    ClickText(\"Clear completed\") -> #(State(..state, todos: list.filter(state.todos, fn(item) { !item.completed })), [])\n"
      <> "    ClickText(\"Dark mode\") -> #(State(..state, dark: True), [])\n"
      <> "    ClickText(\"Light mode\") -> #(State(..state, dark: False), [])\n"
      <> "    ClickText(\"Glass\") -> #(State(..state, theme: \"Glass\"), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "    ClickCheckboxNearText(\"Toggle all\") -> toggle_all(state)\n"
      <> "    ClickCheckboxNearText(text) -> #(State(..state, todos: toggle_title(state.todos, text)), [])\n"
      <> "    ClickCheckbox(index) -> toggle_index(state, index)\n"
      <> "    DblClickText(text) -> #(State(..state, editing: text), [])\n"
      <> "    ClickButtonNearText(text, _) -> #(State(..state, todos: list.filter(state.todos, fn(item) { item.title != text })), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> todo_update_helpers()
  }
}

fn view_module(name: String, flow: FlowProgram) -> String {
  case flow.core {
    StaticText ->
      "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { state.snapshot }\n"
    NumericText(buttons) ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_count(state.count)) }\n\n"
      <> render_count_function(buttons)
    ShoppingList(_) ->
      "import gleam/int\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_items(state.items)) }\n\n"
      <> "fn render_items(items: List(String)) -> String {\n"
      <> "  \"Shopping List\\n\" <> string.join(items, with: \"\\n\") <> \"\\n\" <> int.to_string(list.length(items)) <> \" items\\nClear\"\n"
      <> "}\n"
    TodoList(_) ->
      "import gleam/int\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_tasks(state.todos, state.filter, state.editing, state.theme, state.dark, state.view_style)) }\n\n"
      <> todo_view_helpers()
  }
}

fn generated_todo_items(titles: List(String)) -> String {
  "["
  <> string.join(
    list.map(titles, fn(title) {
      "TodoItem(title: \"" <> escape_string(title) <> "\", completed: False)"
    }),
    with: ", ",
  )
  <> "]"
}

fn todo_update_helpers() -> String {
  "fn change_text(state: State, text: String) -> #(State, List(Effect)) {\n"
  <> "  case state.editing == \"\" || !has_title(state.todos, state.editing) {\n"
  <> "    True -> #(State(..state, input: state.input <> text), [])\n"
  <> "    False -> #(State(..state, todos: edit_title(state.todos, state.editing, fn(title) { title <> text })), [])\n"
  <> "  }\n"
  <> "}\n\n"
  <> "fn enter_text(state: State) -> #(State, List(Effect)) {\n"
  <> "  case state.editing == \"\" || !has_title(state.todos, state.editing) {\n"
  <> "    True -> {\n"
  <> "      let text = string.trim(state.input)\n"
  <> "      case string.is_empty(text) {\n"
  <> "        True -> #(state, [])\n"
  <> "        False -> #(State(..state, input: \"\", todos: list.append(state.todos, [TodoItem(title: text, completed: False)]), editing: \"\"), [])\n"
  <> "      }\n"
  <> "    }\n"
  <> "    False -> #(State(..state, editing: \"\"), [])\n"
  <> "  }\n"
  <> "}\n\n"
  <> "fn toggle_all(state: State) -> #(State, List(Effect)) {\n"
  <> "  let all_completed = state.todos != [] && list.all(state.todos, fn(item) { item.completed })\n"
  <> "  #(State(..state, todos: list.map(state.todos, fn(item) { TodoItem(..item, completed: !all_completed) })), [])\n"
  <> "}\n\n"
  <> "fn toggle_index(state: State, index: Int) -> #(State, List(Effect)) {\n"
  <> "  case index {\n"
  <> "    0 -> toggle_all(state)\n"
  <> "    _ -> #(State(..state, todos: toggle_at(state.todos, index - 1)), [])\n"
  <> "  }\n"
  <> "}\n\n"
  <> "fn toggle_title(todos: List(TodoItem), title: String) -> List(TodoItem) {\n"
  <> "  list.map(todos, fn(item) { case item.title == title { True -> TodoItem(..item, completed: !item.completed) False -> item } })\n"
  <> "}\n\n"
  <> "fn toggle_at(todos: List(TodoItem), index: Int) -> List(TodoItem) {\n"
  <> "  case todos { [] -> [] [item, ..rest] if index == 0 -> [TodoItem(..item, completed: !item.completed), ..rest] [item, ..rest] -> [item, ..toggle_at(rest, index - 1)] }\n"
  <> "}\n\n"
  <> "fn has_title(todos: List(TodoItem), title: String) -> Bool { list.any(todos, fn(item) { item.title == title }) }\n\n"
  <> "fn edit_title(todos: List(TodoItem), title: String, change: fn(String) -> String) -> List(TodoItem) {\n"
  <> "  list.map(todos, fn(item) { case item.title == title { True -> TodoItem(..item, title: change(item.title)) False -> item } })\n"
  <> "}\n"
}

fn todo_view_helpers() -> String {
  "fn render_tasks(todos: List(TodoItem), filter: String, editing: String, theme: String, dark: Bool, view_style: String) -> String {\n"
  <> "  let visible = list.filter(todos, fn(item) { case filter { \"active\" -> !item.completed \"completed\" -> item.completed _ -> True } })\n"
  <> "  let active_count = list.count(todos, fn(item) { !item.completed })\n"
  <> "  let count_word = case active_count == 1 { True -> \" item left\" False -> \" items left\" }\n"
  <> "  let visible_text = string.join(list.map(visible, fn(item) { item.title }), with: \"\\n\")\n"
  <> "  case view_style {\n"
  <> "    \"physical\" -> theme <> \"\\n\" <> visible_text <> \"\\n\" <> int.to_string(active_count) <> count_word <> \"\\nAll\\nActive\\nCompleted\\nClear completed\\nGlass\\n\" <> case dark { True -> \"Light mode\" False -> \"Dark mode\" }\n"
  <> "    _ -> \"todos\\n\" <> visible_text <> \"\\n\" <> int.to_string(active_count) <> count_word <> \"\\nAll\\nActive\\nCompleted\\nClear completed\\nDouble-click to edit a todo\\nCreated by Martin Kavík\\nPart of TodoMVC\\n×\\n\" <> editing\n"
  <> "  }\n"
  <> "}\n"
}

fn button_delta_function(buttons: List(FlowButton)) -> String {
  "fn button_delta(index: Int) -> Int {\n"
  <> "  case index {\n"
  <> button_delta_cases(buttons, 0)
  <> "    _ -> 0\n"
  <> "  }\n"
  <> "}\n"
}

fn button_delta_cases(buttons: List(FlowButton), index: Int) -> String {
  case buttons {
    [] -> ""
    [FlowButton(_, delta), ..rest] ->
      "    "
      <> int.to_string(index)
      <> " -> "
      <> int.to_string(delta)
      <> "\n"
      <> button_delta_cases(rest, index + 1)
  }
}

fn render_count_function(buttons: List(FlowButton)) -> String {
  case buttons {
    [FlowButton("-", _), FlowButton("+", _), ..] ->
      "fn render_count(count: Int) -> String { \"-\" <> int.to_string(count) <> \"+\" }\n"
    [FlowButton("+", _), ..] ->
      "fn render_count(count: Int) -> String { int.to_string(count) <> \"+\" }\n"
    _ -> "fn render_count(count: Int) -> String { int.to_string(count) }\n"
  }
}

fn empty_module(_name: String) -> String {
  "pub fn marker() { Nil }\n"
}

fn safe_name(name: String) -> String {
  name
  |> string.replace(each: "-", with: "_")
  |> string.replace(each: "/", with: "_")
}

fn escape_string(value: String) -> String {
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\"", with: "\\\"")
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
