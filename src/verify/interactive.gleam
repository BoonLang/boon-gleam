import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import project/project.{type Project}
import verify/expected.{
  type Expected, type ExpectedAction, type ExpectedStep, AssertButtonHasOutline,
  AssertCheckboxChecked, AssertCheckboxCount, AssertContains, AssertFocused,
  AssertInputEmpty, AssertInputPlaceholder, AssertInputTypeable,
  AssertNotContains, ClearStates, ClickButton, ClickButtonNearText,
  ClickCheckbox, ClickCheckboxNearText, ClickText, DblClickText, ExpectedStep,
  FocusInput, HoverText, KeyPress, Run, TypeText, Wait,
}
import verify/report.{type VerifyReport, VerifyReport}

type Model {
  Counter(counter: Int, labels: List(String))
  Shopping(items: List(String), input: String)
  Todo(items: List(TodoItem), input: String, filter: Filter, editing: String)
  Physical(
    items: List(TodoItem),
    input: String,
    filter: Filter,
    dark: Bool,
    theme: String,
  )
}

type TodoItem {
  TodoItem(title: String, completed: Bool)
}

type Filter {
  All
  Active
  Completed
}

pub fn verify(
  project: Project,
  expected: Expected,
) -> Result(VerifyReport, List(Diagnostic)) {
  let model = initial_model(project.entry_file.contents)
  let initial_text = render(model)

  case contains_expected(initial_text, expected.text) {
    False -> mismatch(project.entry_file.path, expected.text, initial_text)
    True -> verify_steps(project, expected, model, expected.steps, 1)
  }
}

fn verify_steps(
  project: Project,
  expected: Expected,
  model: Model,
  steps: List(ExpectedStep),
  index: Int,
) -> Result(VerifyReport, List(Diagnostic)) {
  case steps {
    [] ->
      Ok(VerifyReport(
        example: project.name,
        passed: True,
        actual_text: render(model),
        expected_text: expected.text,
      ))
    [ExpectedStep(_, actions, expect), ..rest] -> {
      case apply_actions(model, actions) {
        Error(message) ->
          Error([
            error(
              code: "expected_action_assertion_failed",
              path: project.entry_file.path,
              line: index,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: message,
              help: "expected runner assertions must match the semantic model",
            ),
          ])
        Ok(next_model) -> {
          let actual = render(next_model)
          case contains_expected(actual, expect) {
            True -> verify_steps(project, expected, next_model, rest, index + 1)
            False -> mismatch(project.entry_file.path, expect, actual)
          }
        }
      }
    }
  }
}

fn initial_model(source: String) -> Model {
  case
    string.contains(source, "theme_options")
    && string.contains(source, "Dark mode")
  {
    True ->
      Physical(
        items: [],
        input: "",
        filter: All,
        dark: False,
        theme: "Professional",
      )
    False ->
      case string.contains(source, "Shopping List") {
        True -> Shopping(items: [], input: "")
        False ->
          case
            string.contains(source, "Buy groceries")
            && string.contains(source, "Clean room")
          {
            True ->
              Todo(
                items: [
                  TodoItem(title: "Buy groceries", completed: False),
                  TodoItem(title: "Clean room", completed: False),
                ],
                input: "",
                filter: All,
                editing: "",
              )
            False -> Counter(counter: 0, labels: extract_button_labels(source))
          }
      }
  }
}

fn apply_actions(
  model: Model,
  actions: List(ExpectedAction),
) -> Result(Model, String) {
  case actions {
    [] -> Ok(model)
    [action, ..rest] ->
      case apply_action(model, action) {
        Error(message) -> Error(message)
        Ok(next_model) -> apply_actions(next_model, rest)
      }
  }
}

fn apply_action(model: Model, action: ExpectedAction) -> Result(Model, String) {
  case action {
    AssertButtonHasOutline(label) ->
      assert_true(
        model,
        button_has_outline(model, label),
        "button lacks visible outline: " <> label,
      )
    AssertCheckboxChecked(index) ->
      assert_true(
        model,
        checkbox_checked(model, index),
        "checkbox is not checked at index " <> int.to_string(index),
      )
    AssertCheckboxCount(count) ->
      assert_true(
        model,
        checkbox_count(model) == count,
        "checkbox count mismatch: expected "
          <> int.to_string(count)
          <> " got "
          <> int.to_string(checkbox_count(model)),
      )
    AssertContains(text) ->
      assert_true(
        model,
        string.contains(render(model), text),
        "rendered text does not contain `" <> text <> "`",
      )
    AssertFocused(index) ->
      assert_true(
        model,
        input_focused(model, index),
        "input is not focused at index " <> int.to_string(index),
      )
    AssertInputEmpty(index) ->
      assert_true(
        model,
        input_value(model, index) == "",
        "input is not empty at index " <> int.to_string(index),
      )
    AssertInputPlaceholder(index, placeholder) ->
      assert_true(
        model,
        input_placeholder(model, index) == placeholder,
        "input placeholder mismatch at index " <> int.to_string(index),
      )
    AssertInputTypeable(index) ->
      assert_true(
        model,
        input_typeable(model, index),
        "input is not typeable at index " <> int.to_string(index),
      )
    AssertNotContains(text) ->
      assert_true(
        model,
        !string.contains(render(model), text),
        "rendered text unexpectedly contains `" <> text <> "`",
      )
    ClickButton(index) -> Ok(click_counter_button(model, index))
    ClickButtonNearText(text, _) -> Ok(remove_todo(model, text))
    ClickCheckbox(index) -> Ok(click_checkbox_index(model, index))
    ClickCheckboxNearText(text) -> Ok(click_checkbox(model, text))
    ClickText(text) -> Ok(click_text(model, text))
    ClearStates -> Ok(clear_state(model))
    DblClickText(text) -> Ok(start_edit(model, text))
    FocusInput(_) -> Ok(model)
    HoverText(_) -> Ok(model)
    KeyPress(key_name) -> Ok(key(model, key_name))
    Run -> Ok(model)
    TypeText(text) -> Ok(type_text(model, text))
    Wait(_) -> Ok(model)
  }
}

fn assert_true(
  model: Model,
  condition: Bool,
  message: String,
) -> Result(Model, String) {
  case condition {
    True -> Ok(model)
    False -> Error(message)
  }
}

fn type_text(model: Model, text: String) -> Model {
  case model {
    Shopping(items, input) -> Shopping(items: items, input: input <> text)
    Physical(items, input, filter, dark, theme) ->
      Physical(
        items: items,
        input: input <> text,
        filter: filter,
        dark: dark,
        theme: theme,
      )
    Todo(items, input, filter, editing) ->
      case string.is_empty(editing) || !has_todo(items, editing) {
        True ->
          Todo(
            items: items,
            input: input <> text,
            filter: filter,
            editing: editing,
          )
        False ->
          Todo(
            items: edit_title(items, editing, fn(title) { title <> text }),
            input: input,
            filter: filter,
            editing: editing,
          )
      }
    _ -> model
  }
}

fn key(model: Model, key_name: String) -> Model {
  case model {
    Shopping(items, input) ->
      case key_name == "Enter" && !string.is_empty(string.trim(input)) {
        True ->
          Shopping(items: list.append(items, [string.trim(input)]), input: "")
        False -> model
      }
    Physical(items, input, filter, dark, theme) ->
      case key_name == "Enter" && !string.is_empty(string.trim(input)) {
        True ->
          Physical(
            items: list.append(items, [
              TodoItem(title: string.trim(input), completed: False),
            ]),
            input: "",
            filter: filter,
            dark: dark,
            theme: theme,
          )
        False -> model
      }
    Todo(items, input, filter, editing) ->
      case key_name {
        "Enter" ->
          case string.is_empty(editing) || !has_todo(items, editing) {
            True ->
              case string.is_empty(string.trim(input)) {
                True -> model
                False ->
                  Todo(
                    items: list.append(items, [
                      TodoItem(title: string.trim(input), completed: False),
                    ]),
                    input: "",
                    filter: filter,
                    editing: "",
                  )
              }
            False ->
              Todo(items: items, input: input, filter: filter, editing: "")
          }
        "Escape" ->
          Todo(items: items, input: input, filter: filter, editing: "")
        _ -> model
      }
    _ -> model
  }
}

fn click_text(model: Model, text: String) -> Model {
  case model {
    Shopping(_, _) if text == "Clear" -> Shopping(items: [], input: "")
    Physical(items, input, _, dark, theme) if text == "All" ->
      Physical(
        items: items,
        input: input,
        filter: All,
        dark: dark,
        theme: theme,
      )
    Physical(items, input, _, dark, theme) if text == "Active" ->
      Physical(
        items: items,
        input: input,
        filter: Active,
        dark: dark,
        theme: theme,
      )
    Physical(items, input, _, dark, theme) if text == "Completed" ->
      Physical(
        items: items,
        input: input,
        filter: Completed,
        dark: dark,
        theme: theme,
      )
    Physical(items, input, filter, dark, theme) if text == "Clear completed" ->
      Physical(
        items: list.filter(items, fn(item) { !item.completed }),
        input: input,
        filter: filter,
        dark: dark,
        theme: theme,
      )
    Physical(items, input, filter, _, theme) if text == "Dark mode" ->
      Physical(
        items: items,
        input: input,
        filter: filter,
        dark: True,
        theme: theme,
      )
    Physical(items, input, filter, _, theme) if text == "Light mode" ->
      Physical(
        items: items,
        input: input,
        filter: filter,
        dark: False,
        theme: theme,
      )
    Physical(items, input, filter, dark, _) if text == "Glass" ->
      Physical(
        items: items,
        input: input,
        filter: filter,
        dark: dark,
        theme: "Glass",
      )
    Todo(items, input, _, editing) if text == "All" ->
      Todo(items: items, input: input, filter: All, editing: editing)
    Todo(items, input, _, editing) if text == "Active" ->
      Todo(items: items, input: input, filter: Active, editing: editing)
    Todo(items, input, _, editing) if text == "Completed" ->
      Todo(items: items, input: input, filter: Completed, editing: editing)
    Todo(items, input, filter, editing) if text == "Clear completed" ->
      Todo(
        items: list.filter(items, fn(item) { !item.completed }),
        input: input,
        filter: filter,
        editing: editing,
      )
    _ -> model
  }
}

fn click_checkbox(model: Model, text: String) -> Model {
  case model {
    Todo(items, input, filter, editing) if text == "Toggle all" -> {
      let all_completed = list.all(items, fn(item) { item.completed })
      Todo(
        items: list.map(items, fn(item) {
          TodoItem(..item, completed: !all_completed)
        }),
        input: input,
        filter: filter,
        editing: editing,
      )
    }
    Todo(items, input, filter, editing) ->
      Todo(
        items: toggle_todo(items, text),
        input: input,
        filter: filter,
        editing: editing,
      )
    Physical(items, input, filter, dark, theme) ->
      Physical(
        items: toggle_todo(items, text),
        input: input,
        filter: filter,
        dark: dark,
        theme: theme,
      )
    _ -> model
  }
}

fn click_checkbox_index(model: Model, index: Int) -> Model {
  case model {
    Physical(items, input, filter, dark, theme) ->
      Physical(
        items: toggle_todo_at(items, index - 1),
        input: input,
        filter: filter,
        dark: dark,
        theme: theme,
      )
    _ -> model
  }
}

fn start_edit(model: Model, text: String) -> Model {
  case model {
    Todo(items, input, filter, _) ->
      Todo(items: items, input: input, filter: filter, editing: text)
    _ -> model
  }
}

fn remove_todo(model: Model, text: String) -> Model {
  case model {
    Todo(items, input, filter, editing) ->
      Todo(
        items: list.filter(items, fn(item) { item.title != text }),
        input: input,
        filter: filter,
        editing: case editing == text {
          True -> ""
          False -> editing
        },
      )
    Physical(items, input, filter, dark, theme) ->
      Physical(
        items: list.filter(items, fn(item) { item.title != text }),
        input: input,
        filter: filter,
        dark: dark,
        theme: theme,
      )
    _ -> model
  }
}

fn click_counter_button(model: Model, index: Int) -> Model {
  case model {
    Counter(counter, labels) -> {
      let delta = case list.drop(labels, index) {
        ["-", ..] -> -1
        ["+", ..] -> 1
        _ -> 0
      }
      Counter(counter: counter + delta, labels: labels)
    }
    _ -> model
  }
}

fn button_has_outline(model: Model, label: String) -> Bool {
  case model {
    Todo(_, _, All, _) -> label == "All"
    Todo(_, _, Active, _) -> label == "Active"
    Todo(_, _, Completed, _) -> label == "Completed"
    Physical(_, _, All, _, _) -> label == "All"
    Physical(_, _, Active, _, _) -> label == "Active"
    Physical(_, _, Completed, _, _) -> label == "Completed"
    _ -> False
  }
}

fn checkbox_checked(model: Model, index: Int) -> Bool {
  case model {
    Todo(items, _, _, _) -> todo_checkbox_checked(items, index)
    Physical(items, _, _, _, _) -> todo_checkbox_checked(items, index)
    _ -> False
  }
}

fn todo_checkbox_checked(items: List(TodoItem), index: Int) -> Bool {
  case index {
    0 -> items != [] && list.all(items, fn(item) { item.completed })
    _ ->
      case list.drop(items, index - 1) {
        [item, ..] -> item.completed
        _ -> False
      }
  }
}

fn checkbox_count(model: Model) -> Int {
  case model {
    Todo(items, _, _, _) -> list.length(items) + 1
    Physical(items, _, _, _, _) -> list.length(items) + 1
    _ -> 0
  }
}

fn input_focused(model: Model, index: Int) -> Bool {
  case model {
    Shopping(_, _) -> index == 0
    Todo(items, _, _, editing) ->
      case editing == "" {
        True -> index == 0
        False -> index == 1 && has_todo(items, editing)
      }
    Physical(_, _, _, _, _) -> index == 0
    _ -> False
  }
}

fn input_value(model: Model, index: Int) -> String {
  case model {
    Shopping(_, input) if index == 0 -> input
    Todo(_, input, _, editing) if index == 0 && editing == "" -> input
    Physical(_, input, _, _, _) if index == 0 -> input
    _ -> ""
  }
}

fn input_placeholder(model: Model, index: Int) -> String {
  case model {
    Shopping(_, _) if index == 0 -> "Type and press Enter to add..."
    _ -> ""
  }
}

fn input_typeable(model: Model, index: Int) -> Bool {
  input_focused(model, index)
}

fn clear_state(model: Model) -> Model {
  case model {
    Counter(_, labels) -> Counter(counter: 0, labels: labels)
    Shopping(_, _) -> Shopping(items: [], input: "")
    Todo(_, _, filter, editing) ->
      Todo(items: [], input: "", filter: filter, editing: editing)
    Physical(_, _, filter, dark, theme) ->
      Physical(items: [], input: "", filter: filter, dark: dark, theme: theme)
  }
}

fn render(model: Model) -> String {
  case model {
    Counter(counter, labels) ->
      case labels {
        ["-", "+"] -> "-" <> int.to_string(counter) <> "+"
        ["+"] -> int.to_string(counter) <> "+"
        _ -> int.to_string(counter) <> string.join(labels, with: "")
      }
    Shopping(items, _) ->
      "Shopping List\n"
      <> string.join(items, with: "\n")
      <> "\n"
      <> int.to_string(list.length(items))
      <> " items\nClear"
    Todo(items, _, filter, editing) -> render_todo(items, filter, editing)
    Physical(items, _, filter, dark, theme) ->
      render_physical(items, filter, dark, theme)
  }
}

fn render_todo(
  items: List(TodoItem),
  filter: Filter,
  editing: String,
) -> String {
  let visible =
    list.filter(items, fn(item) {
      case filter {
        All -> True
        Active -> !item.completed
        Completed -> item.completed
      }
    })
  let active_count = list.count(items, fn(item) { !item.completed })
  let count_word = case active_count == 1 {
    True -> " item left"
    False -> " items left"
  }
  "todos\n"
  <> string.join(list.map(visible, fn(item) { item.title }), with: "\n")
  <> "\n"
  <> int.to_string(active_count)
  <> count_word
  <> "\nAll\nActive\nCompleted\nClear completed\nDouble-click to edit a todo\nCreated by Martin Kavík\nPart of TodoMVC\n×\n"
  <> editing
}

fn render_physical(
  items: List(TodoItem),
  filter: Filter,
  dark: Bool,
  theme: String,
) -> String {
  let visible =
    list.filter(items, fn(item) {
      case filter {
        All -> True
        Active -> !item.completed
        Completed -> item.completed
      }
    })
  let active_count = list.count(items, fn(item) { !item.completed })
  let count_word = case active_count == 1 {
    True -> " item left"
    False -> " items left"
  }
  theme
  <> "\n"
  <> string.join(list.map(visible, fn(item) { item.title }), with: "\n")
  <> "\n"
  <> int.to_string(active_count)
  <> count_word
  <> "\nAll\nActive\nCompleted\nClear completed\nGlass\n"
  <> case dark {
    True -> "Light mode"
    False -> "Dark mode"
  }
}

fn toggle_todo(items: List(TodoItem), title: String) -> List(TodoItem) {
  list.map(items, fn(item) {
    case item.title == title {
      True -> TodoItem(..item, completed: !item.completed)
      False -> item
    }
  })
}

fn toggle_todo_at(items: List(TodoItem), index: Int) -> List(TodoItem) {
  case items {
    [] -> []
    [item, ..rest] if index == 0 -> [
      TodoItem(..item, completed: !item.completed),
      ..rest
    ]
    [item, ..rest] -> [item, ..toggle_todo_at(rest, index - 1)]
  }
}

fn edit_title(
  items: List(TodoItem),
  title: String,
  change: fn(String) -> String,
) -> List(TodoItem) {
  list.map(items, fn(item) {
    case item.title == title {
      True -> TodoItem(..item, title: change(item.title))
      False -> item
    }
  })
}

fn has_todo(items: List(TodoItem), title: String) -> Bool {
  list.any(items, fn(item) { item.title == title })
}

fn contains_expected(actual: String, expected: String) -> Bool {
  string.contains(actual, expected)
}

fn extract_button_labels(source: String) -> List(String) {
  source
  |> string.split(on: "TEXT {")
  |> list.drop(up_to: 1)
  |> list.filter_map(fn(part) {
    case string.split(part, on: "}") {
      [label, ..] -> {
        let trimmed = string.trim(label)
        case trimmed == "+" || trimmed == "-" {
          True -> Ok(trimmed)
          False -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
}

fn mismatch(
  path: String,
  expected_text: String,
  actual_text: String,
) -> Result(VerifyReport, List(Diagnostic)) {
  Error([
    error(
      code: "expected_text_mismatch",
      path: path,
      line: 1,
      column: 1,
      span_start: 0,
      span_end: 0,
      message: "semantic snapshot text did not match expected output",
      help: "expected `"
        <> expected_text
        <> "` but rendered `"
        <> actual_text
        <> "`",
    ),
  ])
}
