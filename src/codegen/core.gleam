import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import lowering/flowir.{
  type FlowButton, type FlowListItem, type FlowPerson, type FlowProgram,
  type FlowStaticButton, type RouterPagesSpec, type TimerWidgetSpec,
  AppendTextList, CheckboxList, CountList, CrudList, FlightBooker, FlowButton,
  FlowListItem, FlowPerson, FlowStaticButton, IntervalAccumulator, LatestValue,
  NumericText, RepeatedButtonList, RouterPages, ShoppingList, StableList,
  StaticDocument, StaticText, SwitchHold, TemperatureConverter, TimerOperation,
  TimerWidget, TodoList, ToggleText,
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
        encode_module(name, flow),
      ))
      use _ <- result_try(write_file(
        module_dir <> "/decode.gleam",
        decode_module(name),
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
    StaticDocument(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext, type Snapshot, Snapshot}\n\n"
      <> "pub type State { State(snapshot: Snapshot, hovered: String, clicked: List(String)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(snapshot: view_snapshot(), hovered: \"\", clicked: []) }\n\n"
      <> "fn view_snapshot() { Snapshot(text: \""
      <> escape_string(flow.snapshot_text)
      <> "\") }\n"
    NumericText(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(count: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(count: 0) }\n"
    AppendTextList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(input: String, items: List(String)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(input: \"\", items: "
      <> generated_string_list(spec.initial_items)
      <> ") }\n"
    ShoppingList(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(input: String, items: List(String)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(input: \"\", items: []) }\n"
    CheckboxList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type TodoItem { TodoItem(title: String, completed: Bool) }\n\n"
      <> "pub type State { State(todos: List(TodoItem), filter: String) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(todos: "
      <> generated_checkbox_items(spec.initial_labels)
      <> ", filter: \"all\") }\n"
    CountList(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(count: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(count: 0) }\n"
    CrudList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type TodoItem { TodoItem(title: String, completed: Bool) }\n\n"
      <> "pub type State { State(input: String, selected: String, name_input: String, surname_input: String, todos: List(TodoItem)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(input: \"\", selected: \"\", name_input: \"\", surname_input: \"\", todos: "
      <> generated_people(spec.initial_people)
      <> ") }\n"
    FlightBooker ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(flight_type: String, departure: String, return_date: String, booked: String) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(flight_type: \"one-way\", departure: \"2026-03-03\", return_date: \"2026-03-03\", booked: \"\") }\n"
    IntervalAccumulator ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(count: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(count: 0) }\n"
    LatestValue ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(value: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(value: 3) }\n"
    ToggleText(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext, type Snapshot, Snapshot}\n\n"
      <> "pub type State { State(enabled: Bool, snapshot: Snapshot) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(enabled: False, snapshot: Snapshot(text: \""
      <> escape_string(spec.off_text)
      <> "\")) }\n"
    RepeatedButtonList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(items: List(Int)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(items: "
      <> generated_zero_ints(spec.item_count)
      <> ") }\n"
    RouterPages(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(path: String) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(path: \"/\") }\n"
    SwitchHold ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(showing_b: Bool, counts: List(Int)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(showing_b: False, counts: [0, 0]) }\n"
    TemperatureConverter ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(celsius: String, fahrenheit: String, focus: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(celsius: \"\", fahrenheit: \"\", focus: 0) }\n"
    TimerOperation(_) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(elapsed: Int, result: String, operation: String) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(elapsed: 0, result: \"\", operation: \"\") }\n"
    TimerWidget(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type State { State(elapsed: Int, duration: Int) }\n\n"
      <> "pub fn init(_context: InitContext) -> State { State(elapsed: 0, duration: "
      <> int.to_string(spec.initial_duration)
      <> ") }\n"
    StableList(spec) ->
      "import generated_"
      <> name
      <> "/types.{type InitContext}\n\n"
      <> "pub type TodoItem { TodoItem(title: String, completed: Bool) }\n\n"
      <> "pub type State { State(count: Int, todos: List(TodoItem)) }\n\n"
      <> "pub fn init(_context: InitContext) -> State {\n"
      <> "  State(count: "
      <> int.to_string(spec.next_id)
      <> ", todos: "
      <> generated_stable_items(spec.initial_items)
      <> ")\n"
      <> "}\n"
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
    StaticDocument(_) ->
      "pub type Event { NoEvent HoverText(text: String) ClickButton(index: Int) }\n"
    NumericText(_) -> "pub type Event { NoEvent ClickButton(index: Int) }\n"
    AppendTextList(_) ->
      "pub type Event { NoEvent ChangeText(link_id: String, text: String) KeyDown(link_id: String, key: String) }\n"
    ShoppingList(_) ->
      "pub type Event { NoEvent ChangeText(link_id: String, text: String) KeyDown(link_id: String, key: String) ClickText(text: String) }\n"
    CheckboxList(_) ->
      "pub type Event { NoEvent ClickButton(index: Int) ClickText(text: String) ClickCheckbox(index: Int) }\n"
    CountList(_) -> "pub type Event { NoEvent ClickText(text: String) }\n"
    CrudList(_) ->
      "pub type Event { NoEvent ChangeText(index: Int, text: String) ClickText(text: String) }\n"
    FlightBooker ->
      "pub type Event { NoEvent SelectOption(value: String) ChangeText(index: Int, text: String) ClickButton(index: Int) }\n"
    IntervalAccumulator ->
      "pub type Event { NoEvent AdvanceTime(milliseconds: Int) }\n"
    LatestValue -> "pub type Event { NoEvent ClickButton(index: Int) }\n"
    ToggleText(_) -> "pub type Event { NoEvent ClickButton(index: Int) }\n"
    RepeatedButtonList(_) ->
      "pub type Event { NoEvent ClickButton(index: Int) }\n"
    RouterPages(_) -> "pub type Event { NoEvent ClickText(text: String) }\n"
    SwitchHold -> "pub type Event { NoEvent ClickButton(index: Int) }\n"
    TemperatureConverter ->
      "pub type Event { NoEvent ChangeText(index: Int, text: String) KeyDown(index: Int, key: String) }\n"
    TimerOperation(_) ->
      "pub type Event { NoEvent ClickButton(index: Int) AdvanceTime(milliseconds: Int) }\n"
    TimerWidget(_) ->
      "pub type Event { NoEvent AdvanceTime(milliseconds: Int) ClickText(text: String) SetSlider(index: Int, value: Int) }\n"
    StableList(_) ->
      "pub type Event { NoEvent ClickText(text: String) ClickCheckbox(index: Int) ClickButtonNearText(text: String, label: String) }\n"
    TodoList(_) ->
      "pub type Event { NoEvent ChangeText(link_id: String, text: String) KeyDown(link_id: String, key: String) ClickText(text: String) ClickCheckbox(index: Int) ClickCheckboxNearText(text: String) DblClickText(text: String) ClickButtonNearText(text: String, label: String) }\n"
  }
}

fn effect_module() -> String {
  "pub type Effect { NoEffect }\n"
}

fn encode_module(name: String, flow: FlowProgram) -> String {
  let state_encoder = case flow.core {
    StaticText ->
      "pub fn encode_state(state: State) -> String { \"{\\\"snapshot\\\":\\\"\" <> escape_json(state.snapshot.text) <> \"\\\"}\" }\n"
    StaticDocument(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"snapshot\\\":\\\"\" <> escape_json(state.snapshot.text) <> \"\\\",\\\"hovered\\\":\\\"\" <> escape_json(state.hovered) <> \"\\\",\\\"clicked\\\":\" <> int.to_string(list.length(state.clicked)) <> \"}\" }\n"
    NumericText(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"count\\\":\" <> int.to_string(state.count) <> \"}\" }\n"
    AppendTextList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"items\\\":\" <> int.to_string(list.length(state.items)) <> \"}\" }\n"
    ShoppingList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"input\\\":\\\"\" <> escape_json(state.input) <> \"\\\",\\\"items\\\":\" <> int.to_string(list.length(state.items)) <> \"}\" }\n"
    CheckboxList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"items\\\":\" <> int.to_string(list.length(state.todos)) <> \",\\\"filter\\\":\\\"\" <> state.filter <> \"\\\"}\" }\n"
    CountList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"count\\\":\" <> int.to_string(state.count) <> \"}\" }\n"
    CrudList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"people\\\":\" <> int.to_string(list.length(state.todos)) <> \"}\" }\n"
    FlightBooker ->
      "pub fn encode_state(state: State) -> String { \"{\\\"flight_type\\\":\\\"\" <> state.flight_type <> \"\\\"}\" }\n"
    IntervalAccumulator ->
      "pub fn encode_state(state: State) -> String { \"{\\\"count\\\":\" <> int.to_string(state.count) <> \"}\" }\n"
    LatestValue ->
      "pub fn encode_state(state: State) -> String { \"{\\\"value\\\":\" <> int.to_string(state.value) <> \"}\" }\n"
    ToggleText(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"enabled\\\":\\\"\" <> case state.enabled { True -> \"true\" False -> \"false\" } <> \"\\\"}\" }\n"
    RepeatedButtonList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"items\\\":\" <> int.to_string(list.length(state.items)) <> \"}\" }\n"
    RouterPages(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"path\\\":\\\"\" <> escape_json(state.path) <> \"\\\"}\" }\n"
    SwitchHold ->
      "pub fn encode_state(state: State) -> String { \"{\\\"showing_b\\\":\\\"\" <> case state.showing_b { True -> \"true\" False -> \"false\" } <> \"\\\",\\\"counts\\\":\" <> int.to_string(list.length(state.counts)) <> \"}\" }\n"
    TemperatureConverter ->
      "pub fn encode_state(state: State) -> String { \"{\\\"celsius\\\":\\\"\" <> escape_json(state.celsius) <> \"\\\",\\\"fahrenheit\\\":\\\"\" <> escape_json(state.fahrenheit) <> \"\\\"}\" }\n"
    TimerOperation(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"elapsed\\\":\" <> int.to_string(state.elapsed) <> \",\\\"result\\\":\\\"\" <> escape_json(state.result) <> \"\\\"}\" }\n"
    TimerWidget(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"elapsed\\\":\" <> int.to_string(state.elapsed) <> \",\\\"duration\\\":\" <> int.to_string(state.duration) <> \"}\" }\n"
    StableList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"next_id\\\":\" <> int.to_string(state.count) <> \",\\\"items\\\":\" <> int.to_string(list.length(state.todos)) <> \"}\" }\n"
    TodoList(_) ->
      "pub fn encode_state(state: State) -> String { \"{\\\"input\\\":\\\"\" <> escape_json(state.input) <> \"\\\",\\\"todos\\\":\" <> int.to_string(list.length(state.todos)) <> \",\\\"filter\\\":\\\"\" <> escape_json(state.filter) <> \"\\\"}\" }\n"
  }
  let list_import = case flow.core {
    StaticDocument(_)
    | AppendTextList(_)
    | ShoppingList(_)
    | CheckboxList(_)
    | CrudList(_)
    | RepeatedButtonList(_)
    | SwitchHold
    | StableList(_)
    | TodoList(_) -> "import gleam/list\n"
    _ -> ""
  }
  let string_import = case flow.core {
    NumericText(_)
    | AppendTextList(_)
    | CheckboxList(_)
    | CountList(_)
    | CrudList(_)
    | FlightBooker
    | LatestValue
    | RepeatedButtonList(_)
    | SwitchHold
    | TimerWidget(_)
    | IntervalAccumulator
    | ToggleText(_)
    | StableList(_) -> ""
    _ -> "import gleam/string\n"
  }
  let escape_helper = case flow.core {
    AppendTextList(_)
    | NumericText(_)
    | CheckboxList(_)
    | CountList(_)
    | CrudList(_)
    | FlightBooker
    | LatestValue
    | RepeatedButtonList(_)
    | SwitchHold
    | TimerWidget(_)
    | IntervalAccumulator
    | ToggleText(_)
    | StableList(_) -> ""
    _ ->
      "\nfn escape_json(value: String) -> String {\n"
      <> "  value\n"
      <> "  |> string.replace(each: \"\\\\\", with: \"\\\\\\\\\")\n"
      <> "  |> string.replace(each: \"\\\"\", with: \"\\\\\\\"\")\n"
      <> "  |> string.replace(each: \"\\n\", with: \"\\\\n\")\n"
      <> "}\n"
  }

  int_import(flow)
  <> string_import
  <> list_import
  <> "import generated_"
  <> name
  <> "/event.{type Event}\n"
  <> "import generated_"
  <> name
  <> "/state.{type State}\n\n"
  <> state_encoder
  <> "\n"
  <> "pub fn encode_event(_event: Event) -> String { \"{\\\"event\\\":\\\"typed\\\"}\" }\n\n"
  <> escape_helper
}

fn int_import(flow: FlowProgram) -> String {
  case flow.core {
    StaticText -> ""
    FlightBooker -> ""
    RouterPages(_) -> ""
    SwitchHold -> "import gleam/int\n"
    TemperatureConverter -> ""
    ToggleText(_) -> ""
    StaticDocument(_) -> "import gleam/int\n"
    _ -> "import gleam/int\n"
  }
}

fn decode_module(name: String) -> String {
  "import generated_"
  <> name
  <> "/state\n"
  <> "import generated_"
  <> name
  <> "/types.{type InitContext}\n\n"
  <> "pub fn decode_state(_json: String, context: InitContext) -> state.State { state.init(context) }\n"
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
      <> static_event_imports(flow)
      <> "}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "  }\n"
      <> "}\n\n"
    StaticDocument(_) ->
      imports
      <> static_event_imports(flow)
      <> "}\n"
      <> static_update_imports(flow)
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> static_hover_update_case(flow)
      <> "  }\n"
      <> "}\n\n"
      <> static_update_helpers(flow)
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
    AppendTextList(_) ->
      imports
      <> ", ChangeText, KeyDown, NoEvent}\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ChangeText(_, text) -> #(State(..state, input: state.input <> text), [])\n"
      <> "    KeyDown(_, \"Enter\") -> { let text = string.trim(state.input) #(State(input: \"\", items: case string.is_empty(text) { True -> state.items False -> list.append(state.items, [text]) }), []) }\n"
      <> "    KeyDown(_, _) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n"
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
    CheckboxList(spec) ->
      imports
      <> ", ClickButton, ClickCheckbox, ClickText, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem, State, TodoItem}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> checkbox_filter_update_cases(spec.filterable)
      <> "    ClickCheckbox(index) -> #(State(..state, todos: toggle_at(state.todos, index)), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> stable_list_update_helpers()
    CountList(spec) ->
      imports
      <> ", ClickText, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickText(\""
      <> escape_string(spec.undo_label)
      <> "\") -> #(State(count: case state.count > 0 { True -> state.count - 1 False -> 0 }), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n"
    CrudList(_) ->
      imports
      <> ", ChangeText, ClickText, NoEvent}\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem, State, TodoItem}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ChangeText(0, text) -> #(State(..state, input: text), [])\n"
      <> "    ChangeText(1, text) -> #(State(..state, name_input: text), [])\n"
      <> "    ChangeText(2, text) -> #(State(..state, surname_input: text), [])\n"
      <> "    ChangeText(_, _) -> #(state, [])\n"
      <> "    ClickText(\"Create\") -> #(State(..state, name_input: \"\", surname_input: \"\", todos: list.append(state.todos, [TodoItem(title: state.surname_input <> \", \" <> state.name_input, completed: False)])), [])\n"
      <> "    ClickText(\"Update\") -> update_selected(state)\n"
      <> "    ClickText(\"Delete\") -> #(State(..state, selected: \"\", todos: list.filter(state.todos, fn(item) { item.title != state.selected })), [])\n"
      <> "    ClickText(text) -> #(State(..state, selected: find_title(state.todos, text, state.selected)), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> crud_update_helpers()
    FlightBooker ->
      imports
      <> ", ChangeText, ClickButton, NoEvent, SelectOption}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    SelectOption(value) -> #(State(..state, flight_type: value), [])\n"
      <> "    ChangeText(0, text) -> #(State(..state, departure: text), [])\n"
      <> "    ChangeText(1, text) -> #(State(..state, return_date: text), [])\n"
      <> "    ChangeText(_, _) -> #(state, [])\n"
      <> "    ClickButton(_) -> #(State(..state, booked: case state.flight_type { \"return\" -> \"Booked return flight: \" <> state.departure <> \" to \" <> state.return_date _ -> \"Booked one-way flight on \" <> state.departure }), [])\n"
      <> "  }\n"
      <> "}\n"
    IntervalAccumulator ->
      imports
      <> ", AdvanceTime, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    AdvanceTime(milliseconds) -> #(State(count: state.count + milliseconds / 1000), [])\n"
      <> "  }\n"
      <> "}\n"
    LatestValue ->
      imports
      <> ", ClickButton, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickButton(0) -> #(State(value: 1), [])\n"
      <> "    ClickButton(1) -> #(State(value: 2), [])\n"
      <> "    ClickButton(_) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n"
    ToggleText(spec) ->
      imports
      <> ", ClickButton, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n"
      <> "import generated_"
      <> name
      <> "/types.{Snapshot}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickButton(_) -> { let enabled = !state.enabled #(State(enabled: enabled, snapshot: Snapshot(text: case enabled { True -> \""
      <> escape_string(spec.on_text)
      <> "\" False -> \""
      <> escape_string(spec.off_text)
      <> "\" })), []) }\n"
      <> "  }\n"
      <> "}\n"
    RepeatedButtonList(_) ->
      imports
      <> ", ClickButton, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickButton(index) -> #(State(items: increment_at(state.items, index)), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn increment_at(items: List(Int), index: Int) -> List(Int) { case items { [] -> [] [item, ..rest] if index == 0 -> [item + 1, ..rest] [item, ..rest] -> [item, ..increment_at(rest, index - 1)] } }\n"
    RouterPages(_) ->
      imports
      <> ", ClickText, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickText(\"About\") -> #(State(path: \"/about\"), [])\n"
      <> "    ClickText(\"Contact\") -> #(State(path: \"/contact\"), [])\n"
      <> "    ClickText(\"Home\") -> #(State(path: \"/\"), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n"
    SwitchHold ->
      imports
      <> ", ClickButton, NoEvent}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickButton(0) -> #(State(..state, showing_b: !state.showing_b), [])\n"
      <> "    ClickButton(1) -> #(State(..state, counts: increment_at(state.counts, case state.showing_b { True -> 1 False -> 0 })), [])\n"
      <> "    ClickButton(_) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn increment_at(items: List(Int), index: Int) -> List(Int) { case items { [] -> [] [item, ..rest] if index == 0 -> [item + 1, ..rest] [item, ..rest] -> [item, ..increment_at(rest, index - 1)] } }\n"
    TemperatureConverter ->
      imports
      <> ", ChangeText, KeyDown, NoEvent}\n"
      <> "import gleam/int\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ChangeText(index, text) -> set_value(state, index, current_value(state, index) <> text)\n"
      <> "    KeyDown(index, \"Backspace\") -> set_value(state, index, string.drop_end(current_value(state, index), up_to: 1))\n"
      <> "    KeyDown(_, _) -> #(state, [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn current_value(state: State, index: Int) -> String { case index { 1 -> state.fahrenheit _ -> state.celsius } }\n\n"
      <> "fn set_value(_state: State, index: Int, value: String) -> #(State, List(Effect)) { case index { 1 -> #(State(celsius: to_celsius(value), fahrenheit: value, focus: 1), []) _ -> #(State(celsius: value, fahrenheit: to_fahrenheit(value), focus: 0), []) } }\n\n"
      <> "fn to_fahrenheit(value: String) -> String { case int.parse(value) { Ok(number) -> int.to_string(number * 9 / 5 + 32) Error(_) -> \"\" } }\n\n"
      <> "fn to_celsius(value: String) -> String { case int.parse(value) { Ok(number) -> int.to_string({ number - 32 } * 5 / 9) Error(_) -> \"\" } }\n"
    TimerOperation(_) ->
      imports
      <> ", AdvanceTime, ClickButton, NoEvent}\n"
      <> "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    AdvanceTime(milliseconds) -> { let elapsed = state.elapsed + milliseconds #(State(..state, elapsed: elapsed, result: live_result(elapsed, state.operation, state.result)), []) }\n"
      <> "    ClickButton(index) -> { let operation = case index { 1 -> \"sub\" _ -> \"add\" } #(State(..state, operation: operation, result: calculate(state.elapsed, operation)), []) }\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn live_result(elapsed: Int, operation: String, current: String) -> String { case operation { \"add\" | \"sub\" -> calculate(elapsed, operation) _ -> current } }\n\n"
      <> "fn calculate(elapsed: Int, operation: String) -> String { let a = elapsed / 500 let b = elapsed / 1000 * 10 case operation { \"sub\" -> int.to_string(a - b) _ -> int.to_string(a + b) } }\n"
    TimerWidget(_) ->
      imports
      <> ", AdvanceTime, ClickText, NoEvent, SetSlider}\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, State}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    AdvanceTime(milliseconds) -> #(State(..state, elapsed: state.elapsed + milliseconds), [])\n"
      <> "    ClickText(\"Reset\") -> #(State(..state, elapsed: 0), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "    SetSlider(_, value) -> #(State(..state, duration: value), [])\n"
      <> "  }\n"
      <> "}\n"
    StableList(spec) ->
      imports
      <> ", ClickButtonNearText, ClickCheckbox, ClickText, NoEvent}\n"
      <> "import gleam/int\n"
      <> "import gleam/list\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem, State, TodoItem}\n\n"
      <> "pub fn update(state: State, event: Event) -> #(State, List(Effect)) {\n"
      <> "  case event {\n"
      <> "    NoEvent -> #(state, [])\n"
      <> "    ClickText(\""
      <> escape_string(spec.add_label)
      <> "\") -> #(State(count: state.count + 1, todos: list.append(state.todos, [TodoItem(title: \"New Item (id=\" <> int.to_string(state.count) <> \")\", completed: False)])), [])\n"
      <> "    ClickText(\""
      <> escape_string(spec.clear_completed_label)
      <> "\") -> #(State(..state, todos: list.filter(state.todos, fn(item) { !item.completed })), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
      <> "    ClickCheckbox(index) -> #(State(..state, todos: toggle_at(state.todos, index)), [])\n"
      <> "    ClickButtonNearText(text, _) -> #(State(..state, todos: list.filter(state.todos, fn(item) { item.title != text })), [])\n"
      <> "  }\n"
      <> "}\n\n"
      <> stable_list_update_helpers()
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

fn static_event_imports(flow: FlowProgram) -> String {
  case flow.core {
    StaticDocument(_) -> ", ClickButton, HoverText, NoEvent"
    _ -> ", NoEvent"
  }
}

fn static_hover_update_case(flow: FlowProgram) -> String {
  case flow.core {
    StaticDocument(_) ->
      "    HoverText(text) -> #(State(..state, hovered: text), [])\n"
      <> "    ClickButton(index) -> #(State(..state, clicked: toggle(state.clicked, key_for(index))), [])\n"
    _ -> ""
  }
}

fn static_update_imports(flow: FlowProgram) -> String {
  case flow.core {
    StaticDocument(_) -> "import gleam/list\n"
    _ -> ""
  }
}

fn static_update_helpers(flow: FlowProgram) -> String {
  case flow.core {
    StaticDocument(buttons) ->
      "fn key_for(index: Int) -> String {\n"
      <> "  case index {\n"
      <> static_button_key_cases(buttons, 0)
      <> "    _ -> \"\"\n"
      <> "  }\n"
      <> "}\n\n"
      <> "fn toggle(items: List(String), item: String) -> List(String) {\n"
      <> "  case item == \"\" {\n"
      <> "    True -> items\n"
      <> "    False -> case list.contains(items, item) {\n"
      <> "      True -> list.filter(items, fn(existing) { existing != item })\n"
      <> "      False -> [item, ..items]\n"
      <> "    }\n"
      <> "  }\n"
      <> "}\n"
    _ -> ""
  }
}

fn static_button_key_cases(
  buttons: List(FlowStaticButton),
  index: Int,
) -> String {
  case buttons {
    [] -> ""
    [FlowStaticButton(label), ..rest] ->
      "    "
      <> int.to_string(index)
      <> " -> \""
      <> escape_string(static_button_key(label))
      <> "\"\n"
      <> static_button_key_cases(rest, index + 1)
  }
}

fn static_button_key(label: String) -> String {
  case string.split_once(label, "Button ") {
    Ok(#(_, key)) -> key
    Error(_) -> label
  }
}

fn view_module(name: String, flow: FlowProgram) -> String {
  case flow.core {
    StaticText | StaticDocument(_) ->
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
    AppendTextList(spec) ->
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
      <> append_text_list_view_helpers(spec.render_mode)
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
    CheckboxList(spec) ->
      "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_items(state.todos, state.filter)) }\n\n"
      <> checkbox_list_view_helpers(spec.filterable, spec.instructions)
    CountList(spec) ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: \""
      <> escape_string(spec.title)
      <> "\\n"
      <> escape_string(spec.undo_label)
      <> "\\n"
      <> escape_string(spec.count_label)
      <> ": \" <> int.to_string(state.count)) }\n"
    CrudList(_) ->
      "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_crud(state.todos, state.input, state.selected)) }\n\n"
      <> crud_view_helpers()
    FlightBooker ->
      "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: \"Flight Booker\\nOne-way flight\\nReturn flight\\n\" <> state.departure <> \"\\n\" <> state.return_date <> \"\\nBook\\n\" <> state.booked) }\n"
    IntervalAccumulator ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: case state.count { 0 -> \"\" _ -> int.to_string(state.count) }) }\n"
    LatestValue ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { let value = int.to_string(state.value) Snapshot(text: \"Send 1Send 2\" <> value <> \"Sum: \" <> value) }\n"
    ToggleText(_) ->
      "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { state.snapshot }\n"
    RepeatedButtonList(spec) ->
      "import gleam/int\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: \""
      <> escape_string(spec.title)
      <> "\" <> string.join(list.map(state.items, fn(value) { \""
      <> escape_string(spec.button_label <> spec.count_label <> " ")
      <> "\" <> int.to_string(value) }), with: \"\")) }\n"
    RouterPages(spec) ->
      "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: router_text(state.path)) }\n\n"
      <> router_pages_view_helpers(spec)
    SwitchHold ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: switch_text(state.showing_b, state.counts)) }\n\n"
      <> switch_hold_view_helpers()
    TemperatureConverter ->
      "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(_state: State) -> Snapshot { Snapshot(text: \"Temperature ConverterCelsius=Fahrenheit\") }\n"
    TimerOperation(spec) ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: timer_text(state.elapsed, state.result)) }\n\n"
      <> timer_operation_view_helpers(spec.mode)
    TimerWidget(spec) ->
      "import gleam/int\n"
      <> "import generated_"
      <> name
      <> "/state.{type State}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: timer_widget_text(state.elapsed, state.duration)) }\n\n"
      <> timer_widget_view_helpers(spec)
    StableList(spec) ->
      "import gleam/int\n"
      <> "import gleam/list\n"
      <> "import gleam/string\n"
      <> "import generated_"
      <> name
      <> "/state.{type State, type TodoItem}\n"
      <> "import generated_"
      <> name
      <> "/types.{type Snapshot, Snapshot}\n\n"
      <> "pub fn view(state: State) -> Snapshot { Snapshot(text: render_items(state.todos)) }\n\n"
      <> stable_list_view_helpers(spec.title)
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

fn generated_checkbox_items(labels: List(String)) -> String {
  "["
  <> string.join(
    list.map(labels, fn(label) {
      "TodoItem(title: \"" <> escape_string(label) <> "\", completed: False)"
    }),
    with: ", ",
  )
  <> "]"
}

fn generated_string_list(items: List(String)) -> String {
  "["
  <> string.join(
    list.map(items, fn(item) { "\"" <> escape_string(item) <> "\"" }),
    with: ", ",
  )
  <> "]"
}

fn generated_zero_ints(count: Int) -> String {
  "[" <> string.join(generated_zero_ints_loop(count), with: ", ") <> "]"
}

fn generated_zero_ints_loop(count: Int) -> List(String) {
  case count <= 0 {
    True -> []
    False -> ["0", ..generated_zero_ints_loop(count - 1)]
  }
}

fn generated_people(people: List(FlowPerson)) -> String {
  "["
  <> string.join(
    list.map(people, fn(person) {
      let FlowPerson(name, surname) = person
      "TodoItem(title: \""
      <> escape_string(surname <> ", " <> name)
      <> "\", completed: False)"
    }),
    with: ", ",
  )
  <> "]"
}

fn generated_stable_items(items: List(FlowListItem)) -> String {
  "["
  <> string.join(
    list.map(items, fn(item) {
      let FlowListItem(id, item_name) = item
      "TodoItem(title: \""
      <> escape_string(item_name <> " (id=" <> int.to_string(id) <> ")")
      <> "\", completed: False)"
    }),
    with: ", ",
  )
  <> "]"
}

fn stable_list_update_helpers() -> String {
  "fn toggle_at(todos: List(TodoItem), index: Int) -> List(TodoItem) {\n"
  <> "  case todos { [] -> [] [item, ..rest] if index == 0 -> [TodoItem(..item, completed: !item.completed), ..rest] [item, ..rest] -> [item, ..toggle_at(rest, index - 1)] }\n"
  <> "}\n"
}

fn checkbox_filter_update_cases(filterable: Bool) -> String {
  case filterable {
    True ->
      "    ClickButton(1) -> #(State(..state, filter: \"active\"), [])\n"
      <> "    ClickButton(_) -> #(State(..state, filter: \"all\"), [])\n"
      <> "    ClickText(\"Active\") -> #(State(..state, filter: \"active\"), [])\n"
      <> "    ClickText(\"All\") -> #(State(..state, filter: \"all\"), [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
    False ->
      "    ClickButton(_) -> #(state, [])\n"
      <> "    ClickText(_) -> #(state, [])\n"
  }
}

fn crud_update_helpers() -> String {
  "fn update_selected(state: State) -> #(State, List(Effect)) {\n"
  <> "  let new_title = state.surname_input <> \", \" <> state.name_input\n"
  <> "  #(State(..state, selected: new_title, todos: list.map(state.todos, fn(item) { case item.title == state.selected { True -> TodoItem(..item, title: new_title) False -> item } })), [])\n"
  <> "}\n\n"
  <> "fn find_title(todos: List(TodoItem), text: String, default: String) -> String {\n"
  <> "  case todos { [] -> default [item, ..rest] -> case string.contains(item.title, text) { True -> item.title False -> find_title(rest, text, default) } }\n"
  <> "}\n"
}

fn crud_view_helpers() -> String {
  "fn render_crud(todos: List(TodoItem), filter_prefix: String, selected: String) -> String {\n"
  <> "  let visible = list.filter(todos, fn(item) { string.starts_with(surname(item.title), filter_prefix) })\n"
  <> "  \"CRUD\\nFilter prefix:\\n\" <> string.join(list.map(visible, fn(item) { case item.title == selected { True -> \"► \" <> item.title False -> item.title } }), with: \"\\n\") <> \"\\nName:\\nSurname:\\nCreate\\nUpdate\\nDelete\"\n"
  <> "}\n\n"
  <> "fn surname(title: String) -> String { case string.split_once(title, \",\") { Ok(#(value, _)) -> value Error(_) -> title } }\n"
}

fn append_text_list_view_helpers(mode: String) -> String {
  case mode {
    "retain_count" ->
      "fn render_items(items: List(String)) -> String {\n"
      <> "  let count = int.to_string(list.length(items))\n"
      <> "  \"All count: \" <> count <> \"Retain count: \" <> count <> string.join(items, with: \"\")\n"
      <> "}\n"
    _ ->
      "fn render_items(items: List(String)) -> String {\n"
      <> "  \"Add items with EnterCount: \" <> int.to_string(list.length(items)) <> string.join(list.map(items, fn(item) { \"- \" <> item }), with: \"\")\n"
      <> "}\n"
  }
}

fn router_pages_view_helpers(spec: RouterPagesSpec) -> String {
  "fn router_text(path: String) -> String {\n"
  <> "  let content = case path {\n"
  <> "    \"/about\" -> \""
  <> escape_string(spec.about_title <> spec.about_description)
  <> "\"\n"
  <> "    \"/contact\" -> \""
  <> escape_string(spec.contact_title <> spec.contact_description)
  <> "\"\n"
  <> "    _ -> \""
  <> escape_string(spec.home_title <> spec.home_description)
  <> "\"\n"
  <> "  }\n"
  <> "  \""
  <> escape_string(string.join(spec.nav_labels, with: ""))
  <> "\" <> content\n"
  <> "}\n"
}

fn switch_hold_view_helpers() -> String {
  "fn switch_text(showing_b: Bool, counts: List(Int)) -> String {\n"
  <> "  let a_count = int.to_string(int_at(counts, 0))\n"
  <> "  let b_count = int.to_string(int_at(counts, 1))\n"
  <> "  let content = case showing_b {\n"
  <> "    True -> \"Showing: Item BToggle ViewItem B clicks: \" <> b_count <> \"Click Item B\"\n"
  <> "    False -> \"Showing: Item AToggle ViewItem A clicks: \" <> a_count <> \"Click Item A\"\n"
  <> "  }\n"
  <> "  content <> \"Test: Click button, toggle view, click again. Counts should increment correctly.\"\n"
  <> "}\n\n"
  <> "fn int_at(items: List(Int), index: Int) -> Int { case items, index { [], _ -> 0 [item, ..], 0 -> item [_, ..rest], _ -> int_at(rest, index - 1) } }\n"
}

fn timer_operation_view_helpers(mode: String) -> String {
  let buttons = case mode {
    "then" -> "A + B"
    _ -> "A + BA - B"
  }
  "fn timer_text(elapsed: Int, result: String) -> String {\n"
  <> "  let a = int.to_string(elapsed / 500)\n"
  <> "  let b = int.to_string(elapsed / 1000 * 10)\n"
  <> "  \"A: \" <> a <> \"B: \" <> b <> \""
  <> escape_string(buttons)
  <> "\" <> result\n"
  <> "}\n"
}

fn timer_widget_view_helpers(spec: TimerWidgetSpec) -> String {
  // Guardrail allowlist: the generated timer view contains a literal UI title,
  // not a runtime Timer adapter import.
  "fn timer_widget_text(elapsed: Int, duration: Int) -> String {\n"
  <> "  let max_ms = duration * 1000\n"
  <> "  let capped = case elapsed > max_ms { True -> max_ms False -> elapsed }\n"
  <> "  let percent = case max_ms <= 0 { True -> 100 False -> capped * 100 / max_ms }\n"
  <> "  \""
  <> escape_string(spec.title <> spec.elapsed_label)
  <> "\" <> int.to_string(percent) <> \"%\" <> int.to_string(capped / 1000) <> \"s"
  <> escape_string(spec.duration_label)
  <> "\" <> int.to_string(duration) <> \"s"
  <> escape_string(spec.reset_label)
  <> "\"\n"
  <> "}\n"
}

fn checkbox_list_view_helpers(
  filterable: Bool,
  instructions: String,
) -> String {
  case filterable {
    True ->
      "fn render_items(todos: List(TodoItem), filter: String) -> String {\n"
      <> "  let visible = case filter { \"active\" -> list.filter(todos, fn(item) { !item.completed }) _ -> todos }\n"
      <> "  let label = case filter { \"active\" -> \"ACTIVE\" _ -> \"ALL\" }\n"
      <> "  \"Filter: \" <> case filter { \"active\" -> \"Active\" _ -> \"All\" } <> \"AllActive\" <> string.join(list.map(visible, fn(item) { item.title <> \" (\" <> label <> \") - checked: \" <> case item.completed { True -> \"True\" False -> \"False\" } }), with: \"\") <> \""
      <> escape_string(instructions)
      <> "\"\n"
      <> "}\n"
    False ->
      "fn render_items(todos: List(TodoItem), _filter: String) -> String {\n"
      <> "  string.join(list.map(todos, fn(item) { item.title <> case item.completed { True -> \"(checked)\" False -> \"(unchecked)\" } }), with: \"\")\n"
      <> "}\n"
  }
}

fn stable_list_view_helpers(title: String) -> String {
  "fn render_items(todos: List(TodoItem)) -> String {\n"
  <> "  let active_count = list.count(todos, fn(item) { !item.completed })\n"
  <> "  let completed_count = list.count(todos, fn(item) { item.completed })\n"
  <> "  let rows = todos |> list.map(fn(item) { item.title <> case item.completed { True -> \" [X]\" False -> \" [ ]\" } }) |> string.join(with: \"\\n\")\n"
  <> "  \""
  <> escape_string(title)
  <> "\\nAdd Item\\n\" <> case completed_count > 0 { True -> \"Clear completed\\n\" False -> \"\" } <> rows <> \"\\nActive: \" <> int.to_string(active_count) <> \", Completed: \" <> int.to_string(completed_count)\n"
  <> "}\n"
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
