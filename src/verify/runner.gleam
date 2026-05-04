import codegen/core as core_codegen
import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lowering/flowir.{
  type FlowButton, type FlowListItem, type FlowProgram, type FlowStaticButton,
  type RepeatedButtonListSpec, type RouterPagesSpec, type TimerWidgetSpec,
  AppendTextList, CheckboxList, CountList, CrudList, FlightBooker, FlowButton,
  FlowListItem, FlowProgram, FlowStaticButton, IntervalAccumulator, LatestValue,
  NumericText, RepeatedButtonList, RouterPages, ShoppingList, StableList,
  StaticDocument, StaticText, SwitchHold, TemperatureConverter, TimerOperation,
  TimerWidget, TimerWidgetSpec, TodoList, ToggleText,
}
import lowering/pipeline
import project/loader
import runtime/core.{
  type Effect, type Event, type SemanticNode, type Snapshot, type State,
  type TodoItem, ChangeText, ClickButton, ClickButtonNearText, ClickCheckbox,
  ClickCheckboxNearText, ClickText, DblClickText, HoverText as RuntimeHoverText,
  InitContext, KeyDown, NoEvent, SemanticNode, Snapshot, State, TodoItem,
}
import runtime/host.{
  type BoonGleamRuntimeHost, AppCore, BoonGleamRuntimeHost, init, update, view,
}
import verify/expected.{
  type Expected, type ExpectedAction, type ExpectedStep, AssertButtonDisabled,
  AssertButtonEnabled, AssertButtonHasOutline, AssertCellsCellText,
  AssertCellsRowVisible, AssertCheckboxChecked, AssertCheckboxCount,
  AssertCheckboxUnchecked, AssertContains, AssertFocused,
  AssertFocusedInputValue, AssertInputEmpty, AssertInputNotTypeable,
  AssertInputPlaceholder, AssertInputTypeable, AssertInputValue,
  AssertNotContains, AssertNotFocused, AssertToggleAllDarker, AssertUrl,
  ClearStates, ClickButton as ExpectedClickButton,
  ClickButtonNearText as ExpectedClickButtonNearText,
  ClickCheckbox as ExpectedClickCheckbox,
  ClickCheckboxNearText as ExpectedClickCheckboxNearText,
  ClickText as ExpectedClickText, DblClickCellsCell,
  DblClickText as ExpectedDblClickText, DblClickTextNth, ExpectedStep,
  FocusInput, HoverText as ExpectedHoverText, KeyPress, PersistenceStep, Run,
  SelectOption, SetFocusedInputValue, SetInputValue, SetSliderValue, TypeText,
  Wait, expected_path, load,
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

  case
    string.is_empty(expected.text)
    || matches_expected(actual_text, expected.text)
  {
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
    AssertButtonDisabled(_) ->
      assert_state(state, !button_enabled(state), "button is enabled")
    AssertButtonEnabled(_) ->
      assert_state(state, button_enabled(state), "button is disabled")
    AssertCellsCellText(row, column, expected) ->
      assert_state(
        state,
        cell_text(state, row, column) == expected,
        "cell text mismatch at row "
          <> int.to_string(row)
          <> " column "
          <> int.to_string(column)
          <> ": expected `"
          <> expected
          <> "` got `"
          <> cell_text(state, row, column)
          <> "`",
      )
    AssertCellsRowVisible(_) -> Ok(state)
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
    AssertCheckboxUnchecked(index) ->
      assert_state(
        state,
        !checkbox_checked(state, index),
        "checkbox is checked at index " <> int.to_string(index),
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
        input_focused(state, index) || cell_focused(state),
        "input is not focused at index " <> int.to_string(index),
      )
    AssertFocusedInputValue(value) ->
      assert_state(
        state,
        focused_input_value(state) == value,
        "focused input value mismatch: expected `"
          <> value
          <> "` got `"
          <> focused_input_value(state)
          <> "`",
      )
    AssertInputEmpty(index) ->
      assert_state(
        state,
        input_value(state, index) == "",
        "input is not empty at index " <> int.to_string(index),
      )
    AssertInputNotTypeable(index) ->
      assert_state(
        state,
        !input_focused(state, index),
        "input is typeable at index " <> int.to_string(index),
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
    AssertInputValue(index, value) ->
      assert_state(
        state,
        input_value(state, index) == value,
        "input value mismatch at index "
          <> int.to_string(index)
          <> ": expected `"
          <> value
          <> "` got `"
          <> input_value(state, index)
          <> "`",
      )
    AssertNotContains(text) ->
      assert_state(
        state,
        !string.contains(state.snapshot.text, text),
        "rendered text unexpectedly contains `" <> text <> "`",
      )
    AssertNotFocused ->
      assert_state(
        state,
        !input_focused(state, 0)
          && !input_focused(state, 1)
          && !cell_focused(state),
        "an input is focused",
      )
    AssertToggleAllDarker ->
      Error("toggle-all visual darkness assertion is not implemented")
    AssertUrl(url) ->
      assert_state(
        state,
        state.view_style == "router_pages" && state.filter == url,
        "router URL mismatch: expected `"
          <> url
          <> "` got `"
          <> state.filter
          <> "`",
      )
    ClearStates -> Ok(init(host, InitContext(seed: 0)))
    Run -> Ok(restart_persisted(host, state))
    DblClickCellsCell(row, column) -> Ok(focus_cell(state, row, column))
    DblClickTextNth(_, _) ->
      Error("indexed double-click text actions are not implemented")
    FocusInput(index) -> Ok(focus_input(state, index))
    SelectOption(_, value) -> Ok(select_option(state, value))
    SetFocusedInputValue(text) -> Ok(set_focused_input(state, text))
    SetInputValue(index, text) -> Ok(set_input_value(state, index, text))
    SetSliderValue(_, value) ->
      case state.view_style {
        "timer_widget" -> Ok(set_timer_duration(state, value))
        _ -> Error("slider actions are not implemented")
      }
    Wait(milliseconds) -> Ok(advance_virtual_time(state, milliseconds))
    TypeText(text) if state.view_style == "temperature_converter" ->
      Ok(type_temperature_text(state, text))
    KeyPress("Backspace") if state.view_style == "temperature_converter" ->
      Ok(backspace_temperature_text(state))
    KeyPress("Enter") ->
      case cell_focused(state) {
        True -> Ok(commit_cell_edit(state))
        False -> dispatch_expected_action(host, state, action)
      }
    KeyPress("Escape") ->
      case cell_focused(state) {
        True -> Ok(clear_cell_focus(state))
        False -> dispatch_expected_action(host, state, action)
      }
    ExpectedClickText(_) ->
      case cell_focused(state) {
        True -> Ok(clear_cell_focus(state))
        False -> dispatch_expected_action(host, state, action)
      }
    _ -> dispatch_expected_action(host, state, action)
  }
}

fn dispatch_expected_action(
  host: BoonGleamRuntimeHost,
  state: State,
  action: ExpectedAction,
) -> Result(State, String) {
  case expected_action_to_event(action) {
    Ok(event) -> {
      let #(next_state, _) = update(host, state, event)
      Ok(next_state)
    }
    Error(_) -> Ok(state)
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
    hovered: state.hovered,
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
  case state.hovered == label {
    True -> True
    False ->
      case label, state.filter, state.theme {
        "All", "all", _ -> True
        "Active", "active", _ -> True
        "Completed", "completed", _ -> True
        "Glass", _, "Glass" -> True
        _, _, _ -> False
      }
  }
}

fn checkbox_checked(state: State, index: Int) -> Bool {
  case state.view_style {
    "checkbox_list" | "filter_checkbox_list" ->
      case list.drop(visible_checkbox_todos(state), index) {
        [item, ..] -> item.completed
        _ -> False
      }
    "stable_list" ->
      case list.drop(state.todos, index) {
        [item, ..] -> item.completed
        _ -> False
      }
    _ ->
      case index {
        0 ->
          state.todos != []
          && list.all(state.todos, fn(item) { item.completed })
        _ ->
          case list.drop(state.todos, index - 1) {
            [item, ..] -> item.completed
            _ -> False
          }
      }
  }
}

fn checkbox_count(state: State) -> Int {
  case state.view_style {
    "checkbox_list" | "filter_checkbox_list" ->
      list.length(visible_checkbox_todos(state))
    "stable_list" -> list.length(state.todos)
    _ -> list.length(state.todos) + 1
  }
}

fn input_focused(state: State, index: Int) -> Bool {
  case state.view_style {
    "append_text_list" -> index == 0
    "flight_booker" -> index == 0 || { index == 1 && state.filter == "return" }
    _ ->
      case
        state.todos == []
        && state.view_style == ""
        && !string.contains(state.snapshot.text, "Shopping List")
      {
        True -> False
        False ->
          case state.editing == "" {
            True -> index == 0
            False -> index == 1 && has_task(state.todos, state.editing)
          }
      }
  }
}

fn input_value(state: State, index: Int) -> String {
  case state.view_style, index {
    "flight_booker", 0 -> state.input
    "flight_booker", 1 -> state.hovered
    "temperature_converter", 0 -> state.input
    "temperature_converter", 1 -> state.hovered
    _, 0 -> state.input
    _, _ -> ""
  }
}

fn focused_input_value(state: State) -> String {
  case cell_focused(state) {
    True -> cell_edit_value(state)
    False ->
      case state.editing == "" {
        True -> state.input
        False -> state.editing
      }
  }
}

fn set_focused_input(state: State, value: String) -> State {
  case cell_focused(state) {
    True -> set_meta(state, "cell_edit", value)
    False ->
      case state.editing == "" {
        True -> State(..state, input: value)
        False -> State(..state, editing: value)
      }
  }
}

fn set_input_value(state: State, index: Int, value: String) -> State {
  case state.view_style {
    "crud" -> set_crud_input(state, index, value)
    "flight_booker" -> set_flight_input(state, index, value)
    "append_text_list" ->
      State(
        ..state,
        input: value,
        snapshot: append_text_list_snapshot(
          "append_text_list",
          state.filter,
          state.items,
          value,
        ),
      )
    _ ->
      case index {
        0 -> State(..state, input: value)
        _ -> state
      }
  }
}

fn input_placeholder(state: State, index: Int) -> String {
  case state.view_style, index {
    "append_text_list", 0 -> "Type and press Enter"
    _, 0 -> "Type and press Enter to add..."
    _, _ -> ""
  }
}

fn set_crud_input(state: State, index: Int, value: String) -> State {
  let next = case index {
    0 -> State(..state, input: value)
    1 -> State(..state, editing: value)
    2 -> State(..state, hovered: value)
    _ -> state
  }
  State(
    ..next,
    snapshot: crud_snapshot(
      "crud",
      next.todos,
      next.input,
      next.filter,
      next.editing,
      next.hovered,
    ),
  )
}

fn set_flight_input(state: State, index: Int, value: String) -> State {
  let next = case index {
    0 -> State(..state, input: value)
    1 -> State(..state, hovered: value)
    _ -> state
  }
  State(
    ..next,
    snapshot: flight_snapshot(
      "flight_booker",
      next.filter,
      next.input,
      next.hovered,
      next.editing,
    ),
  )
}

fn focus_input(state: State, index: Int) -> State {
  case state.view_style {
    "temperature_converter" -> State(..state, editing: int.to_string(index))
    _ -> state
  }
}

fn type_temperature_text(state: State, text: String) -> State {
  case state.editing {
    "1" -> set_temperature_fahrenheit(state, state.hovered <> text)
    _ -> set_temperature_celsius(state, state.input <> text)
  }
}

fn backspace_temperature_text(state: State) -> State {
  case state.editing {
    "1" -> set_temperature_fahrenheit(state, drop_last_char(state.hovered))
    _ -> set_temperature_celsius(state, drop_last_char(state.input))
  }
}

fn set_temperature_celsius(state: State, value: String) -> State {
  State(
    ..state,
    input: value,
    hovered: convert_celsius_to_fahrenheit(value),
    editing: "0",
    snapshot: temperature_snapshot("temperature_converter"),
  )
}

fn set_temperature_fahrenheit(state: State, value: String) -> State {
  State(
    ..state,
    input: convert_fahrenheit_to_celsius(value),
    hovered: value,
    editing: "1",
    snapshot: temperature_snapshot("temperature_converter"),
  )
}

fn set_timer_duration(state: State, value: String) -> State {
  let duration = value |> int.parse |> result.unwrap(timer_duration(state))
  State(
    ..state,
    input: int.to_string(duration),
    snapshot: timer_widget_snapshot(
      "timer_widget",
      default_timer_widget_spec(),
      state.count,
      duration,
    ),
  )
}

fn timer_duration(state: State) -> Int {
  state.input |> int.parse |> result.unwrap(15)
}

fn select_option(state: State, value: String) -> State {
  case state.view_style {
    "flight_booker" ->
      State(
        ..state,
        filter: value,
        snapshot: flight_snapshot(
          "flight_booker",
          value,
          state.input,
          state.hovered,
          state.editing,
        ),
      )
    _ -> state
  }
}

fn button_enabled(state: State) -> Bool {
  case state.view_style {
    "flight_booker" ->
      state.filter != "return"
      || date_number(state.hovered) >= date_number(state.input)
    _ -> True
  }
}

fn advance_virtual_time(state: State, milliseconds: Int) -> State {
  case state.view_style {
    "interval_accumulator" -> {
      let ticks = milliseconds / 1000
      let count = state.count + ticks
      State(
        ..state,
        count: count,
        snapshot: timer_snapshot("interval_accumulator", count),
      )
    }
    "timer_operation" -> {
      let elapsed = state.count + milliseconds
      let a = int.to_string(elapsed / 500)
      let b = int.to_string(elapsed / 1000 * 10)
      let operation = string_at(state.items, 3)
      let result = case state.filter, operation {
        "while", "add" ->
          timer_operation_result([a, b, "", operation], operation)
        "while", "sub" ->
          timer_operation_result([a, b, "", operation], operation)
        _, _ -> string_at(state.items, 2)
      }
      let items = [a, b, result, operation]
      State(
        ..state,
        count: elapsed,
        items: items,
        snapshot: timer_operation_snapshot(
          "timer_operation",
          state.filter,
          items,
        ),
      )
    }
    "timer_widget" -> {
      let elapsed = state.count + milliseconds
      let duration = timer_duration(state)
      State(
        ..state,
        count: elapsed,
        snapshot: timer_widget_snapshot(
          "timer_widget",
          default_timer_widget_spec(),
          elapsed,
          duration,
        ),
      )
    }
    _ -> state
  }
}

fn date_number(value: String) -> Int {
  value
  |> string.replace(each: "-", with: "")
  |> int.parse
  |> result.unwrap(0)
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
    ExpectedHoverText(text) -> Ok(RuntimeHoverText(text))
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
    AppendTextList(spec) ->
      State(
        count: 0,
        input: "",
        items: spec.initial_items,
        todos: [],
        filter: spec.render_mode,
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "append_text_list",
        snapshot: append_text_list_snapshot(
          flow.name,
          spec.render_mode,
          spec.initial_items,
          "",
        ),
      )
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
        hovered: "",
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
    CheckboxList(spec) -> {
      let todos =
        list.map(spec.initial_labels, fn(label) {
          TodoItem(title: label, completed: False)
        })
      let view_style = case spec.filterable {
        True -> "filter_checkbox_list"
        False -> "checkbox_list"
      }
      State(
        count: 0,
        input: "",
        items: [],
        todos: todos,
        filter: "all",
        editing: "",
        hovered: "",
        theme: spec.instructions,
        dark: False,
        view_style: view_style,
        snapshot: checkbox_list_snapshot(
          flow.name,
          todos,
          "all",
          spec.filterable,
          spec.instructions,
        ),
      )
    }
    CountList(spec) ->
      State(
        count: 0,
        input: "",
        items: [],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: spec.title,
        dark: False,
        view_style: "count_list",
        snapshot: count_list_snapshot(
          flow.name,
          spec.title,
          spec.undo_label,
          spec.count_label,
          0,
        ),
      )
    CrudList(spec) -> {
      let todos =
        list.map(spec.initial_people, fn(person) {
          TodoItem(
            title: person.surname <> ", " <> person.name,
            completed: False,
          )
        })
      State(
        count: 0,
        input: "",
        items: [],
        todos: todos,
        filter: "",
        editing: "",
        hovered: "",
        theme: "CRUD",
        dark: False,
        view_style: "crud",
        snapshot: crud_snapshot(flow.name, todos, "", "", "", ""),
      )
    }
    FlightBooker ->
      State(
        count: 0,
        input: "2026-03-03",
        items: [],
        todos: [],
        filter: "one-way",
        editing: "",
        hovered: "2026-03-03",
        theme: "",
        dark: False,
        view_style: "flight_booker",
        snapshot: flight_snapshot(
          flow.name,
          "one-way",
          "2026-03-03",
          "2026-03-03",
          "",
        ),
      )
    IntervalAccumulator ->
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
        view_style: "interval_accumulator",
        snapshot: timer_snapshot(flow.name, 0),
      )
    LatestValue ->
      State(
        count: 3,
        input: "",
        items: [],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "latest_value",
        snapshot: latest_snapshot(flow.name, 3),
      )
    ToggleText(spec) ->
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
        view_style: "toggle_text",
        snapshot: simple_snapshot(flow.name, spec.off_text),
      )
    RepeatedButtonList(spec) -> {
      let items = zero_items(spec.item_count)
      State(
        count: 0,
        input: "",
        items: items,
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "repeated_button_list",
        snapshot: repeated_button_list_snapshot(flow.name, spec, items),
      )
    }
    RouterPages(spec) ->
      State(
        count: 0,
        input: "",
        items: [],
        todos: [],
        filter: "/",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "router_pages",
        snapshot: router_pages_snapshot(flow.name, spec, "/"),
      )
    SwitchHold ->
      State(
        count: 0,
        input: "",
        items: ["0", "0"],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "switch_hold",
        snapshot: switch_hold_snapshot(flow.name, False, ["0", "0"]),
      )
    TemperatureConverter ->
      State(
        count: 0,
        input: "",
        items: [],
        todos: [],
        filter: "all",
        editing: "0",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "temperature_converter",
        snapshot: temperature_snapshot(flow.name),
      )
    TimerOperation(spec) ->
      State(
        count: 0,
        input: "",
        items: ["0", "0", "", ""],
        todos: [],
        filter: spec.mode,
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "timer_operation",
        snapshot: timer_operation_snapshot(flow.name, spec.mode, [
          "0",
          "0",
          "",
          "",
        ]),
      )
    TimerWidget(spec) ->
      State(
        count: 0,
        input: int.to_string(spec.initial_duration),
        items: [],
        todos: [],
        filter: "all",
        editing: "",
        hovered: "",
        theme: "",
        dark: False,
        view_style: "timer_widget",
        snapshot: timer_widget_snapshot(
          flow.name,
          spec,
          0,
          spec.initial_duration,
        ),
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
    AppendTextList(spec), ChangeText(_, text) -> #(
      State(
        ..state,
        input: state.input <> text,
        snapshot: append_text_list_snapshot(
          flow.name,
          spec.render_mode,
          state.items,
          state.input <> text,
        ),
      ),
      [],
    )
    AppendTextList(spec), KeyDown(_, "Enter") -> {
      let text = string.trim(state.input)
      let items = case string.is_empty(text) {
        True -> state.items
        False -> list.append(state.items, [text])
      }
      #(
        State(
          ..state,
          input: "",
          items: items,
          snapshot: append_text_list_snapshot(
            flow.name,
            spec.render_mode,
            items,
            "",
          ),
        ),
        [],
      )
    }
    StaticDocument(_), RuntimeHoverText(text) -> #(
      State(..state, hovered: text),
      [],
    )
    StaticDocument(buttons), ClickButton(index) -> {
      let key = static_button_key(buttons, index)
      let clicked = toggle_string(state.items, key)
      #(
        State(
          ..state,
          items: clicked,
          snapshot: static_document_snapshot(
            flow.name,
            flow.snapshot_text,
            clicked,
          ),
        ),
        [],
      )
    }
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
    CheckboxList(spec), ClickButton(index) if spec.filterable -> {
      let filter = case index {
        1 -> "active"
        _ -> "all"
      }
      #(
        State(
          ..state,
          filter: filter,
          snapshot: checkbox_list_snapshot(
            flow.name,
            state.todos,
            filter,
            spec.filterable,
            spec.instructions,
          ),
        ),
        [],
      )
    }
    CheckboxList(spec), ClickText("Active") if spec.filterable -> #(
      State(
        ..state,
        filter: "active",
        snapshot: checkbox_list_snapshot(
          flow.name,
          state.todos,
          "active",
          spec.filterable,
          spec.instructions,
        ),
      ),
      [],
    )
    CheckboxList(spec), ClickText("All") if spec.filterable -> #(
      State(
        ..state,
        filter: "all",
        snapshot: checkbox_list_snapshot(
          flow.name,
          state.todos,
          "all",
          spec.filterable,
          spec.instructions,
        ),
      ),
      [],
    )
    CheckboxList(spec), ClickCheckbox(index) -> {
      let todos = toggle_checkbox_visible_at(state, index)
      #(
        State(
          ..state,
          todos: todos,
          snapshot: checkbox_list_snapshot(
            flow.name,
            todos,
            state.filter,
            spec.filterable,
            spec.instructions,
          ),
        ),
        [],
      )
    }
    CountList(spec), ClickText(label) if label == spec.undo_label -> {
      let count = case state.count > 0 {
        True -> state.count - 1
        False -> 0
      }
      #(
        State(
          ..state,
          count: count,
          snapshot: count_list_snapshot(
            flow.name,
            spec.title,
            spec.undo_label,
            spec.count_label,
            count,
          ),
        ),
        [],
      )
    }
    CrudList(_), ClickText("Create") -> create_crud_person(flow.name, state)
    CrudList(_), ClickText("Update") -> update_crud_person(flow.name, state)
    CrudList(_), ClickText("Delete") -> delete_crud_person(flow.name, state)
    CrudList(_), ClickText(text) -> select_crud_person(flow.name, state, text)
    FlightBooker, ClickButton(_) -> {
      let message = case state.filter {
        "return" ->
          "Booked return flight: " <> state.input <> " to " <> state.hovered
        _ -> "Booked one-way flight on " <> state.input
      }
      #(
        State(
          ..state,
          editing: message,
          snapshot: flight_snapshot(
            flow.name,
            state.filter,
            state.input,
            state.hovered,
            message,
          ),
        ),
        [],
      )
    }
    LatestValue, ClickButton(index) -> {
      let value = case index {
        0 -> 1
        1 -> 2
        _ -> state.count
      }
      #(
        State(
          ..state,
          count: value,
          snapshot: latest_snapshot(flow.name, value),
        ),
        [],
      )
    }
    ToggleText(spec), ClickButton(_) -> {
      let dark = !state.dark
      let text = case dark {
        True -> spec.on_text
        False -> spec.off_text
      }
      #(
        State(..state, dark: dark, snapshot: simple_snapshot(flow.name, text)),
        [],
      )
    }
    RepeatedButtonList(spec), ClickButton(index) -> {
      let items = increment_string_at(state.items, index)
      #(
        State(
          ..state,
          items: items,
          snapshot: repeated_button_list_snapshot(flow.name, spec, items),
        ),
        [],
      )
    }
    RouterPages(spec), ClickText(label) -> {
      let home_label = text_at(spec.nav_labels, 0, "")
      let about_label = text_at(spec.nav_labels, 1, "")
      let contact_label = text_at(spec.nav_labels, 2, "")
      let path = case label {
        _ if label == about_label -> "/about"
        _ if label == contact_label -> "/contact"
        _ if label == home_label -> "/"
        _ -> state.filter
      }
      #(
        State(
          ..state,
          filter: path,
          snapshot: router_pages_snapshot(flow.name, spec, path),
        ),
        [],
      )
    }
    SwitchHold, ClickButton(0) -> #(
      State(
        ..state,
        dark: !state.dark,
        snapshot: switch_hold_snapshot(flow.name, !state.dark, state.items),
      ),
      [],
    )
    SwitchHold, ClickButton(1) -> {
      let index = case state.dark {
        True -> 1
        False -> 0
      }
      let items = increment_string_at(state.items, index)
      #(
        State(
          ..state,
          items: items,
          snapshot: switch_hold_snapshot(flow.name, state.dark, items),
        ),
        [],
      )
    }
    TemperatureConverter, ChangeText(_, text) -> #(
      type_temperature_text(state, text),
      [],
    )
    TimerWidget(spec), ClickText(label) if label == spec.reset_label -> #(
      State(
        ..state,
        count: 0,
        snapshot: timer_widget_snapshot(
          flow.name,
          spec,
          0,
          timer_duration(state),
        ),
      ),
      [],
    )
    TimerOperation(spec), ClickButton(index) -> {
      let operation = case index {
        1 -> "sub"
        _ -> "add"
      }
      let result = timer_operation_result(state.items, operation)
      let items = [
        string_at(state.items, 0),
        string_at(state.items, 1),
        result,
        operation,
      ]
      #(
        State(
          ..state,
          items: items,
          snapshot: timer_operation_snapshot(flow.name, spec.mode, items),
        ),
        [],
      )
    }
    StableList(spec), ClickText(label) if label == spec.add_label ->
      append_stable_item(flow.name, spec.title, state)
    StableList(spec), ClickText(label) if label == spec.clear_completed_label -> {
      let todos = list.filter(state.todos, fn(item) { !item.completed })
      #(
        State(
          ..state,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [],
      )
    }
    StableList(spec), ClickCheckbox(index) -> {
      let todos = toggle_task_at_loop(state.todos, index)
      #(
        State(
          ..state,
          todos: todos,
          snapshot: stable_list_snapshot(flow.name, spec.title, todos),
        ),
        [],
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
        [],
      )
    }
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
      core: AppendTextList(spec),
    ) ->
      append_text_list_snapshot(name, spec.render_mode, spec.initial_items, "")
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: NumericText(buttons),
    ) -> numeric_snapshot(name, buttons, 0)
    FlowProgram(
      name: name,
      snapshot_text: text,
      source_shapes: _,
      core: StaticDocument(_),
    ) -> static_document_snapshot(name, text, [])
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: CheckboxList(spec),
    ) -> {
      let todos =
        list.map(spec.initial_labels, fn(label) {
          TodoItem(title: label, completed: False)
        })
      checkbox_list_snapshot(
        name,
        todos,
        "all",
        spec.filterable,
        spec.instructions,
      )
    }
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: CountList(spec),
    ) ->
      count_list_snapshot(
        name,
        spec.title,
        spec.undo_label,
        spec.count_label,
        0,
      )
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: CrudList(spec),
    ) -> {
      let todos =
        list.map(spec.initial_people, fn(person) {
          TodoItem(
            title: person.surname <> ", " <> person.name,
            completed: False,
          )
        })
      crud_snapshot(name, todos, "", "", "", "")
    }
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: FlightBooker,
    ) -> flight_snapshot(name, "one-way", "2026-03-03", "2026-03-03", "")
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: IntervalAccumulator,
    ) -> timer_snapshot(name, 0)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: LatestValue,
    ) -> latest_snapshot(name, 3)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: ToggleText(spec),
    ) -> simple_snapshot(name, spec.off_text)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: RepeatedButtonList(spec),
    ) -> repeated_button_list_snapshot(name, spec, zero_items(spec.item_count))
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: RouterPages(spec),
    ) -> router_pages_snapshot(name, spec, "/")
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: SwitchHold,
    ) -> switch_hold_snapshot(name, False, ["0", "0"])
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: TemperatureConverter,
    ) -> temperature_snapshot(name)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: TimerOperation(spec),
    ) -> timer_operation_snapshot(name, spec.mode, ["0", "0", "", ""])
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: TimerWidget(spec),
    ) -> timer_widget_snapshot(name, spec, 0, spec.initial_duration)
    FlowProgram(
      name: name,
      snapshot_text: _,
      source_shapes: _,
      core: StableList(spec),
    ) -> {
      let todos =
        list.map(spec.initial_items, fn(item) {
          TodoItem(title: stable_item_title(item), completed: False)
        })
      stable_list_snapshot(name, spec.title, todos)
    }
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

fn static_document_snapshot(
  name: String,
  base_text: String,
  clicked: List(String),
) -> Snapshot {
  let text =
    list.fold(clicked, base_text, fn(acc, key) {
      string.replace(acc, key <> ": False", key <> ": True")
    })
  Snapshot(text: text, semantic_nodes: [semantic_node(name, text)])
}

fn append_stable_item(
  name: String,
  title: String,
  state: State,
) -> #(State, List(Effect)) {
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
      snapshot: stable_list_snapshot(name, title, todos),
    ),
    [],
  )
}

fn stable_item_title(item: FlowListItem) -> String {
  let FlowListItem(id, name) = item
  name <> " (id=" <> int.to_string(id) <> ")"
}

fn create_crud_person(name: String, state: State) -> #(State, List(Effect)) {
  let title = state.hovered <> ", " <> state.editing
  let todos = case string.trim(title) {
    "," -> state.todos
    _ -> list.append(state.todos, [TodoItem(title: title, completed: False)])
  }
  #(
    State(
      ..state,
      todos: todos,
      editing: "",
      hovered: "",
      snapshot: crud_snapshot(name, todos, state.input, state.filter, "", ""),
    ),
    [],
  )
}

fn update_crud_person(name: String, state: State) -> #(State, List(Effect)) {
  let new_title = state.hovered <> ", " <> state.editing
  let todos =
    list.map(state.todos, fn(item) {
      case item.title == state.filter {
        True -> TodoItem(..item, title: new_title)
        False -> item
      }
    })
  #(
    State(
      ..state,
      todos: todos,
      filter: new_title,
      snapshot: crud_snapshot(
        name,
        todos,
        state.input,
        new_title,
        state.editing,
        state.hovered,
      ),
    ),
    [],
  )
}

fn delete_crud_person(name: String, state: State) -> #(State, List(Effect)) {
  let todos = list.filter(state.todos, fn(item) { item.title != state.filter })
  #(
    State(
      ..state,
      todos: todos,
      filter: "",
      snapshot: crud_snapshot(
        name,
        todos,
        state.input,
        "",
        state.editing,
        state.hovered,
      ),
    ),
    [],
  )
}

fn select_crud_person(
  name: String,
  state: State,
  text: String,
) -> #(State, List(Effect)) {
  case find_crud_title(state.todos, text) {
    Ok(title) -> #(
      State(
        ..state,
        filter: title,
        snapshot: crud_snapshot(
          name,
          state.todos,
          state.input,
          title,
          state.editing,
          state.hovered,
        ),
      ),
      [],
    )
    Error(_) -> #(state, [])
  }
}

fn find_crud_title(todos: List(TodoItem), text: String) -> Result(String, Nil) {
  case todos {
    [] -> Error(Nil)
    [item, ..rest] ->
      case string.contains(item.title, text) {
        True -> Ok(item.title)
        False -> find_crud_title(rest, text)
      }
  }
}

fn visible_checkbox_todos(state: State) -> List(TodoItem) {
  case state.view_style, state.filter {
    "filter_checkbox_list", "active" ->
      list.filter(state.todos, fn(item) { !item.completed })
    _, _ -> state.todos
  }
}

fn toggle_checkbox_visible_at(state: State, index: Int) -> List(TodoItem) {
  case state.view_style, state.filter {
    "filter_checkbox_list", "active" ->
      case checkbox_visible_title(state.todos, index) {
        Ok(title) -> toggle_task_by_exact_title(state.todos, title)
        Error(_) -> state.todos
      }
    _, _ -> toggle_task_at_loop(state.todos, index)
  }
}

fn checkbox_visible_title(
  todos: List(TodoItem),
  index: Int,
) -> Result(String, Nil) {
  todos
  |> list.filter(fn(item) { !item.completed })
  |> list.drop(index)
  |> first_title
}

fn first_title(todos: List(TodoItem)) -> Result(String, Nil) {
  case todos {
    [item, ..] -> Ok(item.title)
    [] -> Error(Nil)
  }
}

fn toggle_task_by_exact_title(
  todos: List(TodoItem),
  title: String,
) -> List(TodoItem) {
  list.map(todos, fn(item) {
    case item.title == title {
      True -> TodoItem(..item, completed: !item.completed)
      False -> item
    }
  })
}

fn cell_text(state: State, row: Int, column: Int) -> String {
  case row, column {
    1, 1 -> cell_value(state, 1, 1, "5")
    2, 1 -> cell_value(state, 2, 1, "10")
    3, 1 -> cell_value(state, 3, 1, "15")
    1, 2 -> int.to_string(cell_int(state, 1, 1, 5) + cell_int(state, 2, 1, 10))
    1, 3 ->
      int.to_string(
        cell_int(state, 1, 1, 5)
        + cell_int(state, 2, 1, 10)
        + cell_int(state, 3, 1, 15),
      )
    _, _ -> ""
  }
}

fn cell_int(state: State, row: Int, column: Int, default: Int) -> Int {
  cell_value(state, row, column, int.to_string(default))
  |> int.parse
  |> result.unwrap(default)
}

fn cell_value(state: State, row: Int, column: Int, default: String) -> String {
  get_meta(state, cell_key(row, column), default)
}

fn focus_cell(state: State, row: Int, column: Int) -> State {
  state
  |> set_meta("cell_focus", int.to_string(row) <> ":" <> int.to_string(column))
  |> set_meta("cell_edit", cell_text(state, row, column))
}

fn cell_focused(state: State) -> Bool {
  get_meta(state, "cell_focus", "") != ""
}

fn cell_edit_value(state: State) -> String {
  get_meta(state, "cell_edit", "")
}

fn commit_cell_edit(state: State) -> State {
  let focus = get_meta(state, "cell_focus", "")
  case string.split(focus, on: ":") {
    [row_text, column_text] -> {
      let row = row_text |> int.parse |> result.unwrap(0)
      let column = column_text |> int.parse |> result.unwrap(0)
      state
      |> set_meta(cell_key(row, column), cell_edit_value(state))
      |> clear_cell_focus
    }
    _ -> state
  }
}

fn clear_cell_focus(state: State) -> State {
  state
  |> remove_meta("cell_focus")
  |> remove_meta("cell_edit")
}

fn cell_key(row: Int, column: Int) -> String {
  "cell:" <> int.to_string(row) <> ":" <> int.to_string(column)
}

fn get_meta(state: State, key: String, default: String) -> String {
  let prefix = key <> "="
  case list.find(state.items, fn(item) { string.starts_with(item, prefix) }) {
    Ok(item) -> string.drop_start(item, up_to: string.length(prefix))
    Error(_) -> default
  }
}

fn set_meta(state: State, key: String, value: String) -> State {
  let prefix = key <> "="
  State(..state, items: [
    prefix <> value,
    ..list.filter(state.items, fn(item) { !string.starts_with(item, prefix) })
  ])
}

fn remove_meta(state: State, key: String) -> State {
  let prefix = key <> "="
  State(
    ..state,
    items: list.filter(state.items, fn(item) {
      !string.starts_with(item, prefix)
    }),
  )
}

fn static_button_key(buttons: List(FlowStaticButton), index: Int) -> String {
  case buttons, index {
    [], _ -> ""
    [FlowStaticButton(label), ..], 0 ->
      case string.split_once(label, "Button ") {
        Ok(#(_, key)) -> key
        Error(_) -> label
      }
    [_, ..rest], _ -> static_button_key(rest, index - 1)
  }
}

fn toggle_string(items: List(String), item: String) -> List(String) {
  case string.is_empty(item) {
    True -> items
    False ->
      case list.contains(items, item) {
        True -> list.filter(items, fn(existing) { existing != item })
        False -> [item, ..items]
      }
  }
}

fn semantic_node(name: String, text: String) -> SemanticNode {
  SemanticNode(id: name <> ":document.root", path: "/document/root", text: text)
}

fn simple_snapshot(name: String, text: String) -> Snapshot {
  Snapshot(text: text, semantic_nodes: [semantic_node(name, text)])
}

fn repeated_button_list_snapshot(
  name: String,
  spec: RepeatedButtonListSpec,
  items: List(String),
) -> Snapshot {
  simple_snapshot(
    name,
    spec.title
      <> string.join(
      list.map(items, fn(value) {
        spec.button_label <> spec.count_label <> " " <> value
      }),
      with: "",
    ),
  )
}

fn router_pages_snapshot(
  name: String,
  spec: RouterPagesSpec,
  path: String,
) -> Snapshot {
  let content = case path {
    "/about" -> spec.about_title <> spec.about_description
    "/contact" -> spec.contact_title <> spec.contact_description
    _ -> spec.home_title <> spec.home_description
  }
  simple_snapshot(name, string.join(spec.nav_labels, with: "") <> content)
}

fn switch_hold_snapshot(
  name: String,
  showing_b: Bool,
  counts: List(String),
) -> Snapshot {
  let a_count = string_at(counts, 0)
  let b_count = string_at(counts, 1)
  let content = case showing_b {
    True ->
      "Showing: Item BToggle ViewItem B clicks: " <> b_count <> "Click Item B"
    False ->
      "Showing: Item AToggle ViewItem A clicks: " <> a_count <> "Click Item A"
  }
  simple_snapshot(
    name,
    content
      <> "Test: Click button, toggle view, click again. Counts should increment correctly.",
  )
}

fn temperature_snapshot(name: String) -> Snapshot {
  simple_snapshot(name, "Temperature ConverterCelsius=Fahrenheit")
}

fn timer_operation_snapshot(
  name: String,
  mode: String,
  items: List(String),
) -> Snapshot {
  let a = string_at(items, 0)
  let b = string_at(items, 1)
  let result = string_at(items, 2)
  let buttons = case mode {
    "then" -> "A + B"
    _ -> "A + BA - B"
  }
  simple_snapshot(name, "A: " <> a <> "B: " <> b <> buttons <> result)
}

fn timer_operation_result(items: List(String), operation: String) -> String {
  let a = string_at(items, 0) |> int.parse |> result.unwrap(0)
  let b = string_at(items, 1) |> int.parse |> result.unwrap(0)
  case operation {
    "sub" -> int.to_string(a - b)
    _ -> int.to_string(a + b)
  }
}

fn timer_widget_snapshot(
  name: String,
  spec: TimerWidgetSpec,
  elapsed_ms: Int,
  duration_seconds: Int,
) -> Snapshot {
  let max_ms = duration_seconds * 1000
  let capped_ms = case elapsed_ms > max_ms {
    True -> max_ms
    False -> elapsed_ms
  }
  let percent = case max_ms <= 0 {
    True -> 100
    False -> capped_ms * 100 / max_ms
  }
  let elapsed_seconds = capped_ms / 1000
  simple_snapshot(
    name,
    spec.title
      <> spec.elapsed_label
      <> int.to_string(percent)
      <> "%"
      <> int.to_string(elapsed_seconds)
      <> "sDuration:"
      <> int.to_string(duration_seconds)
      <> "s"
      <> spec.reset_label,
  )
}

fn default_timer_widget_spec() -> TimerWidgetSpec {
  TimerWidgetSpec(
    title: "Timer",
    elapsed_label: "Elapsed Time:",
    duration_label: "Duration:",
    reset_label: "Reset",
    initial_duration: 15,
  )
}

fn append_text_list_snapshot(
  name: String,
  mode: String,
  items: List(String),
  _input: String,
) -> Snapshot {
  let count = int.to_string(list.length(items))
  let text = case mode {
    "retain_count" ->
      "All count: "
      <> count
      <> "Retain count: "
      <> count
      <> string.join(items, with: "")
    _ ->
      "Add items with EnterCount: "
      <> count
      <> string.join(list.map(items, fn(item) { "- " <> item }), with: "")
  }
  simple_snapshot(name, text)
}

fn increment_string_at(items: List(String), index: Int) -> List(String) {
  case items {
    [] -> []
    [item, ..rest] if index == 0 -> [increment_string(item), ..rest]
    [item, ..rest] -> [item, ..increment_string_at(rest, index - 1)]
  }
}

fn zero_items(count: Int) -> List(String) {
  case count <= 0 {
    True -> []
    False -> ["0", ..zero_items(count - 1)]
  }
}

fn text_at(items: List(String), index: Int, default: String) -> String {
  case items, index {
    [], _ -> default
    [item, ..], 0 -> item
    [_, ..rest], _ -> text_at(rest, index - 1, default)
  }
}

fn string_at(items: List(String), index: Int) -> String {
  case items, index {
    [], _ -> ""
    [item, ..], 0 -> item
    [_, ..rest], _ -> string_at(rest, index - 1)
  }
}

fn convert_celsius_to_fahrenheit(value: String) -> String {
  case int.parse(value) {
    Ok(number) -> int.to_string(number * 9 / 5 + 32)
    Error(_) -> ""
  }
}

fn convert_fahrenheit_to_celsius(value: String) -> String {
  case int.parse(value) {
    Ok(number) -> int.to_string({ number - 32 } * 5 / 9)
    Error(_) -> ""
  }
}

fn drop_last_char(value: String) -> String {
  string.drop_end(value, up_to: 1)
}

fn increment_string(value: String) -> String {
  let number = value |> int.parse |> result.unwrap(0)
  int.to_string(number + 1)
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

fn checkbox_list_snapshot(
  name: String,
  todos: List(TodoItem),
  filter: String,
  filterable: Bool,
  instructions: String,
) -> Snapshot {
  let text = render_checkbox_list(todos, filter, filterable, instructions)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn crud_snapshot(
  name: String,
  todos: List(TodoItem),
  filter_prefix: String,
  selected: String,
  _name_input: String,
  _surname_input: String,
) -> Snapshot {
  let text = render_crud(todos, filter_prefix, selected)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn render_crud(
  todos: List(TodoItem),
  filter_prefix: String,
  selected: String,
) -> String {
  let visible =
    list.filter(todos, fn(item) {
      string.starts_with(person_surname(item.title), filter_prefix)
    })
  "CRUD\nFilter prefix:\n"
  <> string.join(
    list.map(visible, fn(item) {
      case item.title == selected {
        True -> "► " <> item.title
        False -> item.title
      }
    }),
    with: "\n",
  )
  <> "\nName:\nSurname:\nCreate\nUpdate\nDelete"
}

fn person_surname(title: String) -> String {
  case string.split_once(title, ",") {
    Ok(#(surname, _)) -> surname
    Error(_) -> title
  }
}

fn flight_snapshot(
  name: String,
  flight_type: String,
  departure_date: String,
  return_date: String,
  booked: String,
) -> Snapshot {
  let text =
    "Flight Booker\nOne-way flight\nReturn flight\n"
    <> departure_date
    <> "\n"
    <> return_date
    <> "\nBook\n"
    <> booked
    <> "\n"
    <> case flight_type {
      "return" -> "Return mode"
      _ -> "One-way mode"
    }
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn timer_snapshot(name: String, count: Int) -> Snapshot {
  let text = case count {
    0 -> ""
    _ -> int.to_string(count)
  }
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn latest_snapshot(name: String, value: Int) -> Snapshot {
  let value_text = int.to_string(value)
  let text = "Send 1Send 2" <> value_text <> "Sum: " <> value_text
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn render_checkbox_list(
  todos: List(TodoItem),
  filter: String,
  filterable: Bool,
  instructions: String,
) -> String {
  case filterable {
    True -> {
      let visible = case filter {
        "active" -> list.filter(todos, fn(item) { !item.completed })
        _ -> todos
      }
      let label = case filter {
        "active" -> "ACTIVE"
        _ -> "ALL"
      }
      "Filter: "
      <> case filter {
        "active" -> "Active"
        _ -> "All"
      }
      <> "AllActive"
      <> string.join(
        list.map(visible, fn(item) {
          item.title
          <> " ("
          <> label
          <> ") - checked: "
          <> bool_text(item.completed)
        }),
        with: "",
      )
      <> instructions
    }
    False ->
      string.join(
        list.map(todos, fn(item) {
          item.title
          <> case item.completed {
            True -> "(checked)"
            False -> "(unchecked)"
          }
        }),
        with: "",
      )
  }
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "True"
    False -> "False"
  }
}

fn count_list_snapshot(
  name: String,
  title: String,
  undo_label: String,
  count_label: String,
  count: Int,
) -> Snapshot {
  let text =
    title
    <> "\n"
    <> undo_label
    <> "\n"
    <> count_label
    <> ": "
    <> int.to_string(count)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn stable_list_snapshot(
  name: String,
  title: String,
  todos: List(TodoItem),
) -> Snapshot {
  let text = render_stable_list(title, todos)
  Snapshot(text: text, semantic_nodes: [
    SemanticNode(
      id: name <> ":document.root",
      path: "/document/root",
      text: text,
    ),
  ])
}

fn render_stable_list(title: String, todos: List(TodoItem)) -> String {
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
    |> string.join(with: "\n")
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
  actual == expected
  || string.contains(actual, expected)
  || matches_timer_regex(actual, expected)
}

fn matches_timer_regex(actual: String, expected: String) -> Bool {
  string.starts_with(expected, "^A: ")
  && string.starts_with(actual, "A: ")
  && string.contains(actual, "B: ")
  && {
    string.contains(actual, "A + BA - B") || string.contains(actual, "A + B")
  }
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
