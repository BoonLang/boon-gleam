import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import support/file

pub type Expected {
  Expected(text: String, steps: List(ExpectedStep))
}

pub type ExpectedStepKind {
  SequenceStep
  PersistenceStep
}

pub type ExpectedStep {
  ExpectedStep(
    kind: ExpectedStepKind,
    actions: List(ExpectedAction),
    expect: String,
  )
}

pub type ExpectedAction {
  AssertButtonHasOutline(String)
  AssertCheckboxChecked(Int)
  AssertCheckboxCount(Int)
  AssertContains(String)
  AssertFocused(Int)
  AssertInputEmpty(Int)
  AssertInputPlaceholder(Int, String)
  AssertInputTypeable(Int)
  AssertNotContains(String)
  ClickButton(Int)
  ClickButtonNearText(String, String)
  ClickCheckbox(Int)
  ClickCheckboxNearText(String)
  ClickText(String)
  ClearStates
  DblClickText(String)
  FocusInput(Int)
  HoverText(String)
  KeyPress(String)
  Run
  TypeText(String)
  Wait(Int)
}

pub fn load(example_path: String) -> Result(Expected, List(Diagnostic)) {
  let path = expected_path(example_path)
  case file.read_text_file(path) {
    Ok(contents) -> parse(path, contents)
    Error(message) ->
      Error([
        error(
          code: "expected_read_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "copy the `.expected` file from the pinned Boon corpus",
        ),
      ])
  }
}

pub fn parse_text(
  path: String,
  contents: String,
) -> Result(Expected, List(Diagnostic)) {
  parse(path, contents)
}

pub fn expected_path(example_path: String) -> String {
  case string.ends_with(example_path, ".bn") {
    True -> replace_extension(example_path, ".expected")
    False -> example_path <> "/" <> example_name(example_path) <> ".expected"
  }
}

fn parse(path: String, contents: String) -> Result(Expected, List(Diagnostic)) {
  let lines = string.split(contents, on: "\n")
  case parse_output_text(lines, False) {
    Ok(text) -> {
      use steps <- result_try(parse_steps(path, lines))
      Ok(Expected(text: text, steps: steps))
    }
    Error(_) ->
      Error([
        error(
          code: "expected_output_missing",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "expected file does not contain `[output] text = ...`",
          help: "Phase 2 verifies semantic snapshot text",
        ),
      ])
  }
}

fn parse_output_text(
  lines: List(String),
  in_output: Bool,
) -> Result(String, Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "[output]" -> parse_output_text(rest, True)
        _ ->
          case in_output && string.starts_with(trimmed, "text = ") {
            True -> Ok(trim_quotes(string.drop_start(trimmed, up_to: 7)))
            False ->
              case in_output && string.starts_with(trimmed, "[") {
                True -> parse_output_text(rest, False)
                False -> parse_output_text(rest, in_output)
              }
          }
      }
    }
  }
}

fn parse_steps(
  path: String,
  lines: List(String),
) -> Result(List(ExpectedStep), List(Diagnostic)) {
  parse_step_lines(
    path,
    lines,
    line_number: 1,
    step_kind: SequenceStep,
    pending_actions: [],
    action_lines: [],
    collecting_actions: False,
    steps: [],
  )
}

fn parse_step_lines(
  path: String,
  lines: List(String),
  line_number line_number: Int,
  step_kind step_kind: ExpectedStepKind,
  pending_actions pending_actions: List(ExpectedAction),
  action_lines action_lines: List(String),
  collecting_actions collecting_actions: Bool,
  steps steps: List(ExpectedStep),
) -> Result(List(ExpectedStep), List(Diagnostic)) {
  case lines {
    [] ->
      case collecting_actions {
        True ->
          Error([
            expected_parse_error(
              path,
              line_number,
              "unterminated expected action array",
            ),
          ])
        False -> Ok(list.reverse(steps))
      }
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case collecting_actions {
        True -> {
          let next_action_lines = case string.starts_with(trimmed, "#") {
            True -> action_lines
            False -> [trimmed, ..action_lines]
          }
          case action_block_complete(list.reverse(next_action_lines)) {
            True -> {
              use parsed_actions <- result_try(parse_action_block(
                path,
                line_number,
                list.reverse(next_action_lines),
              ))
              parse_step_lines(
                path,
                rest,
                line_number + 1,
                step_kind,
                list.append(list.reverse(parsed_actions), pending_actions),
                [],
                False,
                steps,
              )
            }
            False ->
              parse_step_lines(
                path,
                rest,
                line_number + 1,
                step_kind,
                pending_actions,
                next_action_lines,
                True,
                steps,
              )
          }
        }
        False ->
          case string.starts_with(trimmed, "#") {
            True ->
              parse_step_lines(
                path,
                rest,
                line_number + 1,
                step_kind,
                pending_actions,
                [],
                False,
                steps,
              )
            False ->
              case parse_step_section(trimmed) {
                Ok(next_kind) ->
                  parse_step_lines(
                    path,
                    rest,
                    line_number + 1,
                    next_kind,
                    pending_actions,
                    [],
                    False,
                    steps,
                  )
                Error(_) ->
                  case string.starts_with(trimmed, "actions = ") {
                    True -> {
                      let action_lines = [trimmed]
                      case action_block_complete(action_lines) {
                        True -> {
                          use parsed_actions <- result_try(parse_action_block(
                            path,
                            line_number,
                            action_lines,
                          ))
                          parse_step_lines(
                            path,
                            rest,
                            line_number + 1,
                            step_kind,
                            list.append(
                              list.reverse(parsed_actions),
                              pending_actions,
                            ),
                            [],
                            False,
                            steps,
                          )
                        }
                        False ->
                          parse_step_lines(
                            path,
                            rest,
                            line_number + 1,
                            step_kind,
                            pending_actions,
                            action_lines,
                            True,
                            steps,
                          )
                      }
                    }
                    False ->
                      case parse_expect_line(trimmed) {
                        Ok(expect) ->
                          parse_step_lines(
                            path,
                            rest,
                            line_number + 1,
                            step_kind,
                            [],
                            [],
                            False,
                            [
                              ExpectedStep(
                                kind: step_kind,
                                actions: list.reverse(pending_actions),
                                expect: expect,
                              ),
                              ..steps
                            ],
                          )
                        Error(_) ->
                          parse_step_lines(
                            path,
                            rest,
                            line_number + 1,
                            step_kind,
                            pending_actions,
                            [],
                            False,
                            steps,
                          )
                      }
                  }
              }
          }
      }
    }
  }
}

fn parse_step_section(line: String) -> Result(ExpectedStepKind, Nil) {
  case line {
    "[[sequence]]" -> Ok(SequenceStep)
    "[[persistence]]" -> Ok(PersistenceStep)
    _ -> Error(Nil)
  }
}

fn parse_expect_line(line: String) -> Result(String, Nil) {
  case string.starts_with(line, "expect = ") {
    True -> Ok(trim_quotes(string.drop_start(line, up_to: 9)))
    False -> Error(Nil)
  }
}

fn parse_action(line: String) -> Result(ExpectedAction, Nil) {
  parse_uncommented_action(line)
}

fn parse_uncommented_action(line: String) -> Result(ExpectedAction, Nil) {
  case string.contains(line, "\"assert_button_has_outline\"") {
    True -> Ok(AssertButtonHasOutline(first_string_arg(line)))
    False ->
      case string.contains(line, "\"assert_checkbox_checked\"") {
        True -> Ok(AssertCheckboxChecked(first_int_arg(line)))
        False ->
          case string.contains(line, "\"assert_checkbox_count\"") {
            True -> Ok(AssertCheckboxCount(first_int_arg(line)))
            False ->
              case string.contains(line, "\"assert_contains\"") {
                True -> Ok(AssertContains(first_string_arg(line)))
                False ->
                  case string.contains(line, "\"assert_focused\"") {
                    True -> Ok(AssertFocused(first_int_arg(line)))
                    False ->
                      case string.contains(line, "\"assert_input_empty\"") {
                        True -> Ok(AssertInputEmpty(first_int_arg(line)))
                        False ->
                          case
                            string.contains(
                              line,
                              "\"assert_input_placeholder\"",
                            )
                          {
                            True ->
                              Ok(AssertInputPlaceholder(
                                first_int_arg(line),
                                first_string_arg(line),
                              ))
                            False ->
                              case
                                string.contains(
                                  line,
                                  "\"assert_input_typeable\"",
                                )
                              {
                                True ->
                                  Ok(AssertInputTypeable(first_int_arg(line)))
                                False ->
                                  case
                                    string.contains(
                                      line,
                                      "\"assert_not_contains\"",
                                    )
                                  {
                                    True ->
                                      Ok(
                                        AssertNotContains(first_string_arg(line)),
                                      )
                                    False -> parse_non_assert_action(line)
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

fn parse_non_assert_action(line: String) -> Result(ExpectedAction, Nil) {
  case string.contains(line, "\"type\"") {
    True -> Ok(TypeText(first_string_arg(line)))
    False ->
      case string.contains(line, "\"key\"") {
        True -> Ok(KeyPress(first_string_arg(line)))
        False -> parse_click_action(line)
      }
  }
}

fn parse_click_action(line: String) -> Result(ExpectedAction, Nil) {
  case
    string.contains(line, "\"click_button_near_text\""),
    string.contains(line, "\"click_button\""),
    string.contains(line, "\"click_checkbox_near_text\""),
    string.contains(line, "\"click_checkbox\""),
    string.contains(line, "\"click_text\""),
    string.contains(line, "\"dblclick_text\"")
  {
    True, _, _, _, _, _ ->
      Ok(ClickButtonNearText(first_string_arg(line), second_string_arg(line)))
    _, True, _, _, _, _ -> Ok(ClickButton(first_int_arg(line)))
    _, _, True, _, _, _ -> Ok(ClickCheckboxNearText(first_string_arg(line)))
    _, _, _, True, _, _ -> Ok(ClickCheckbox(first_int_arg(line)))
    _, _, _, _, True, _ -> Ok(ClickText(first_string_arg(line)))
    _, _, _, _, _, True -> Ok(DblClickText(first_string_arg(line)))
    _, _, _, _, _, _ -> parse_misc_action(line)
  }
}

fn parse_misc_action(line: String) -> Result(ExpectedAction, Nil) {
  case string.contains(line, "\"clear_states\"") {
    True -> Ok(ClearStates)
    False ->
      case string.contains(line, "\"focus_input\"") {
        True -> Ok(FocusInput(first_int_arg(line)))
        False ->
          case string.contains(line, "\"hover_text\"") {
            True -> Ok(HoverText(first_string_arg(line)))
            False ->
              case string.contains(line, "\"run\"") {
                True -> Ok(Run)
                False ->
                  case string.contains(line, "\"wait\"") {
                    True -> Ok(Wait(first_int_arg(line)))
                    False -> Error(Nil)
                  }
              }
          }
      }
  }
}

fn parse_action_block(
  path: String,
  line_number: Int,
  lines: List(String),
) -> Result(List(ExpectedAction), List(Diagnostic)) {
  let text = string.join(lines, with: " ")
  let rows = extract_action_rows(string.to_graphemes(text), 0, False, "", [])
  parse_action_rows(path, line_number, rows, [])
}

fn extract_action_rows(
  graphemes: List(String),
  depth: Int,
  in_string: Bool,
  current: String,
  rows: List(String),
) -> List(String) {
  case graphemes {
    [] -> list.reverse(rows)
    [grapheme, ..rest] ->
      case grapheme, in_string, depth {
        "\"", _, _ ->
          extract_action_rows(
            rest,
            depth,
            !in_string,
            append_if_inner(current, depth, grapheme),
            rows,
          )
        "[", False, _ ->
          extract_action_rows(rest, depth + 1, in_string, current, rows)
        "]", False, 2 -> {
          let row = string.trim(current)
          extract_action_rows(
            rest,
            1,
            in_string,
            "",
            case string.contains(row, "\"") {
              True -> [row, ..rows]
              False -> rows
            },
          )
        }
        "]", False, _ ->
          extract_action_rows(rest, depth - 1, in_string, current, rows)
        _, _, _ ->
          extract_action_rows(
            rest,
            depth,
            in_string,
            append_if_inner(current, depth, grapheme),
            rows,
          )
      }
  }
}

fn append_if_inner(current: String, depth: Int, grapheme: String) -> String {
  case depth >= 2 {
    True -> current <> grapheme
    False -> current
  }
}

fn parse_action_rows(
  path: String,
  line_number: Int,
  rows: List(String),
  acc: List(ExpectedAction),
) -> Result(List(ExpectedAction), List(Diagnostic)) {
  case rows {
    [] -> Ok(list.reverse(acc))
    [row, ..rest] ->
      case parse_action(row) {
        Ok(action) ->
          parse_action_rows(path, line_number, rest, [action, ..acc])
        Error(_) ->
          Error([
            expected_parse_error(
              path,
              line_number,
              "unsupported or malformed expected action: [" <> row <> "]",
            ),
          ])
      }
  }
}

fn action_block_complete(lines: List(String)) -> Bool {
  let text = string.join(lines, with: " ")
  count_grapheme(text, "[") == count_grapheme(text, "]")
}

fn count_grapheme(text: String, needle: String) -> Int {
  text
  |> string.to_graphemes
  |> list.count(fn(grapheme) { grapheme == needle })
}

fn expected_parse_error(
  path: String,
  line_number: Int,
  message: String,
) -> Diagnostic {
  error(
    code: "expected_parse_failed",
    path: path,
    line: line_number,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: message,
    help: "expected actions must match the pinned action schema",
  )
}

fn first_int_arg(line: String) -> Int {
  int_arg(line, 0)
}

fn int_arg(line: String, index: Int) -> Int {
  case list.drop(numeric_args(line), index) {
    [value, ..] ->
      value
      |> strip_arg_token
      |> int.parse
      |> result.unwrap(0)
    _ -> 0
  }
}

fn first_string_arg(line: String) -> String {
  string_arg(line, 0)
}

fn second_string_arg(line: String) -> String {
  string_arg(line, 1)
}

fn string_arg(line: String, index: Int) -> String {
  case list.drop(quoted_values(line), index + 1) {
    [value, ..] -> value
    _ -> ""
  }
}

fn numeric_args(line: String) -> List(String) {
  let after_action = case string.split(line, on: "\"") {
    [_, _, rest, ..] -> rest
    _ -> ""
  }
  after_action
  |> string.split(on: ",")
  |> list.drop(up_to: 1)
  |> list.map(string.trim)
}

fn quoted_values(line: String) -> List(String) {
  quoted_values_loop(string.split(line, on: "\""), 0, [])
}

fn quoted_values_loop(
  parts: List(String),
  index: Int,
  acc: List(String),
) -> List(String) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] ->
      quoted_values_loop(rest, index + 1, case index % 2 == 1 {
        True -> [part, ..acc]
        False -> acc
      })
  }
}

fn strip_arg_token(value: String) -> String {
  value
  |> strip_quotes
  |> string.replace(each: "]", with: "")
  |> string.replace(each: ",", with: "")
  |> string.trim
}

fn strip_quotes(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> value |> string.drop_start(up_to: 1) |> string.drop_end(up_to: 1)
    False -> value
  }
}

fn trim_quotes(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> value |> string.drop_start(up_to: 1) |> string.drop_end(up_to: 1)
    False -> value
  }
}

fn replace_extension(path: String, extension: String) -> String {
  let parts = string.split(path, on: ".")
  case parts {
    [] -> path <> extension
    [_] -> path <> extension
    _ -> {
      let without_last = list.take(parts, list.length(parts) - 1)
      string.join(without_last, with: ".") <> extension
    }
  }
}

fn example_name(path: String) -> String {
  path
  |> string.split(on: "/")
  |> list.filter(fn(part) { !string.is_empty(part) })
  |> list.last
  |> result.unwrap(path)
}

fn result_try(
  result: Result(a, List(Diagnostic)),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(errors) -> Error(errors)
  }
}
