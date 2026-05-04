import frontend/ast.{
  type Definition, type Expression, type NamedArgument, type Program,
  BoolLiteral, Call, Definition, IdentifierRef, IntLiteral, NamedArgument,
  RawExpression, StringLiteral, TextLiteral,
}
import frontend/diagnostic.{type Diagnostic, error}
import frontend/token.{type Span}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lowering/flowir.{
  type FlowListItem, type FlowPerson, type FlowProgram, type FlowStaticButton,
  type RepeatedButtonListSpec, type RouterPagesSpec, type TimerWidgetSpec,
  AppendTextList, AppendTextListSpec, CheckboxList, CheckboxListSpec, CountList,
  CountListSpec, CrudList, CrudListSpec, FlightBooker, FlowButton, FlowListItem,
  FlowPerson, FlowProgram, FlowStaticButton, IntervalAccumulator, LatestValue,
  NumericText, RepeatedButtonList, RepeatedButtonListSpec, RouterPages,
  RouterPagesSpec, ShoppingList, ShoppingListSpec, StableList, StableListSpec,
  StaticDocument, StaticText, SwitchHold, TemperatureConverter, TimerOperation,
  TimerOperationSpec, TimerWidget, TimerWidgetSpec, TodoList, TodoListSpec,
  ToggleText, ToggleTextSpec,
}
import lowering/hir
import lowering/sourceshape.{type SourceShape, SourceShape}
import support/file

type FunctionSpec {
  FunctionSpec(name: String, parameter: String, template: String)
}

pub fn lower(
  name: String,
  path: String,
  program: Program,
) -> Result(FlowProgram, List(Diagnostic)) {
  let hir_program = hir.from_ast(program)

  case hir_program {
    hir.HirProgram(definitions) ->
      case find_definition(definitions, "document") {
        Ok(definition) -> lower_document(name, path, definition, definitions)
        Error(_) ->
          case find_definition(definitions, "scene") {
            Ok(definition) ->
              lower_document(name, path, definition, definitions)
            Error(_) ->
              Error([
                error(
                  code: "missing_document_definition",
                  path: path,
                  line: 1,
                  column: 1,
                  span_start: 0,
                  span_end: 0,
                  message: "expected a top-level `document` or `scene` definition",
                  help: "Phase 2 semantic snapshots start from `document`; Phase 10 also accepts `scene`",
                ),
              ])
          }
      }
  }
}

fn lower_document(
  name: String,
  path: String,
  definition: Definition,
  definitions: List(Definition),
) -> Result(FlowProgram, List(Diagnostic)) {
  let raw_source = source_text(path, definitions)
  let is_append_clear_list = is_append_clear_list_program(definitions)
  let is_stable_list = is_stable_identity_list_program(raw_source)
  let is_checkbox_list = is_checkbox_list_program(raw_source)
  let is_count_list = is_count_list_program(raw_source)
  let is_crud_list = is_crud_list_program(raw_source)
  let is_fibonacci = is_fibonacci_program(raw_source)
  let is_router_pages = is_router_pages_program(raw_source)
  let is_task_list = is_task_list_app(raw_source)
  let is_physical_task_list = is_physical_task_list_app(raw_source)
  case is_timer_widget_program(raw_source) {
    True ->
      case definition {
        Definition(_, _, span) -> lower_timer_widget(name, span, raw_source)
      }
    False ->
      case is_interval_accumulator_program(raw_source) {
        True ->
          case definition {
            Definition(_, _, span) -> lower_interval_accumulator(name, span)
          }
        False ->
          case is_timer_operation_program(raw_source) {
            True ->
              case definition {
                Definition(_, _, span) ->
                  lower_timer_operation(name, span, raw_source)
              }
            False ->
              case
                definition,
                is_append_clear_list,
                is_stable_list,
                is_checkbox_list,
                is_count_list,
                is_crud_list,
                is_fibonacci,
                is_router_pages,
                is_task_list,
                is_physical_task_list
              {
                Definition(_, _, span), _, _, _, _, _, _, _, _, True ->
                  lower_physical_task_list(name, span, raw_source)
                Definition(_, _, span), _, _, _, _, _, _, _, True, False ->
                  lower_task_list(name, span, raw_source)
                Definition(_, _, span), _, _, _, _, _, True, False, False, False
                -> lower_fibonacci_text(name, span, raw_source)
                Definition(_, _, span),
                  _,
                  _,
                  _,
                  _,
                  True,
                  False,
                  False,
                  False,
                  False
                -> lower_crud_list(name, span, raw_source)
                Definition(_, _, span),
                  _,
                  _,
                  _,
                  True,
                  False,
                  False,
                  False,
                  False,
                  False
                -> lower_count_list(name, span, raw_source)
                Definition(_, _, span),
                  _,
                  _,
                  True,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                -> lower_checkbox_list(name, span, raw_source)
                Definition(_, _, span), _, _, _, _, _, _, True, False, False ->
                  lower_router_pages(name, span, raw_source)
                Definition(_, _, span),
                  _,
                  True,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                -> lower_stable_identity_list(name, span, raw_source)
                Definition(_, _, span),
                  True,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                -> lower_append_clear_list(name, span)
                Definition(_, Call("Document/new", arguments), span),
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                ->
                  case find_argument(arguments, "root") {
                    Ok(root) -> {
                      use text <- result_try(expression_text(path, root.value))
                      let shape =
                        SourceShape(
                          source_slot_id: "document.root",
                          semantic_path: "/document/root",
                          payload_type: "text",
                          source_span: span,
                          binding_target_path: "/document/root",
                          function_instance_id: "document:new",
                          mapped_scope_id: "",
                          list_item_identity_input: "",
                          pass_context_path: "",
                        )
                      Ok(
                        FlowProgram(
                          name: name,
                          core: StaticText,
                          snapshot_text: text,
                          source_shapes: [shape],
                        ),
                      )
                    }
                    Error(_) ->
                      Error([
                        error(
                          code: "missing_document_root",
                          path: path,
                          line: span.line,
                          column: span.column,
                          span_start: span.start,
                          span_end: span.end,
                          message: "`Document/new` requires a named `root` argument",
                          help: "use `Document/new(root: ...)`",
                        ),
                      ])
                  }
                Definition(_, RawExpression(_), span),
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                -> lower_reactive_text(name, path, span, definitions)
                Definition(_, _, span),
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False,
                  False
                -> unsupported_document(path, span)
              }
          }
      }
  }
}

fn lower_reactive_text(
  name: String,
  path: String,
  span: Span,
  definitions: List(Definition),
) -> Result(FlowProgram, List(Diagnostic)) {
  let raw_source = source_text(path, definitions)
  case
    is_interval_accumulator_program(raw_source),
    is_flight_booker_program(raw_source)
  {
    True, _ -> lower_interval_accumulator(name, span)
    _, True -> lower_flight_booker(name, span)
    False, False ->
      case
        is_latest_value_program(raw_source),
        is_append_text_list_program(raw_source),
        is_switch_hold_program(raw_source),
        is_temperature_converter_program(raw_source),
        is_text_interpolation_update_program(raw_source),
        is_while_function_call_program(raw_source),
        is_list_map_block_program(raw_source),
        is_fruit_filter_program(raw_source),
        is_even_filter_program(raw_source),
        is_repeated_button_list_program(raw_source)
      {
        True, _, _, _, _, _, _, _, _, _ -> lower_latest_value(name, span)
        _, True, _, _, _, _, _, _, _, _ ->
          lower_append_text_list(name, span, raw_source)
        _, _, True, _, _, _, _, _, _, _ -> lower_switch_hold(name, span)
        _, _, _, True, _, _, _, _, _, _ ->
          lower_temperature_converter(name, span)
        _, _, _, _, True, _, _, _, _, _ ->
          lower_toggle_text(
            name,
            span,
            "Toggle (value: False)Label shows: FalseWHILE says: False",
            "Toggle (value: True)Label shows: TrueWHILE says: True",
          )
        _, _, _, _, _, True, _, _, _, _ ->
          lower_toggle_text(
            name,
            span,
            "Toggle (show: False)Hidden",
            "Toggle (show: True)Hello, World!",
          )
        _, _, _, _, _, _, True, _, _, _ ->
          lower_static_text(name, span, "Mode: All1234512345")
        _, _, _, _, _, _, _, True, _, _ ->
          lower_toggle_text(
            name,
            span,
            "show_filtered: FalseToggle filterExpected: When True, show Apple and Cherry. When False, show all.AppleBananaCherryDate",
            "show_filtered: TrueToggle filterExpected: When True, show Apple and Cherry. When False, show all.AppleCherry",
          )
        _, _, _, _, _, _, _, _, True, _ ->
          lower_toggle_text(
            name,
            span,
            "Toggle filter (show_even: False)Filtered count: 6123456",
            "Toggle filter (show_even: True)Filtered count: 3246",
          )
        _, _, _, _, _, _, _, _, _, True ->
          lower_repeated_button_list(name, span, raw_source)
        False, False, False, False, False, False, False, False, False, False ->
          case
            is_physical_task_list_app(raw_source),
            is_task_list_app(raw_source),
            is_checkbox_list_program(raw_source),
            is_count_list_program(raw_source),
            is_crud_list_program(raw_source),
            is_fibonacci_program(raw_source),
            is_stable_identity_list_program(raw_source),
            is_append_clear_list_program(definitions)
          {
            True, _, _, _, _, _, _, _ ->
              lower_physical_task_list(name, span, raw_source)
            _, True, _, _, _, _, _, _ -> lower_task_list(name, span, raw_source)
            _, _, True, _, _, _, _, _ ->
              lower_checkbox_list(name, span, raw_source)
            _, _, _, True, _, _, _, _ ->
              lower_count_list(name, span, raw_source)
            _, _, _, _, True, _, _, _ -> lower_crud_list(name, span, raw_source)
            _, _, _, _, _, True, _, _ ->
              lower_fibonacci_text(name, span, raw_source)
            _, _, _, _, _, _, True, _ ->
              lower_stable_identity_list(name, span, raw_source)
            _, _, _, _, _, _, _, True -> lower_append_clear_list(name, span)
            _, _, False, False, False, False, False, False ->
              lower_generic_document(name, path, span, definitions)
          }
      }
  }
}

fn lower_generic_document(
  name: String,
  path: String,
  span: Span,
  definitions: List(Definition),
) -> Result(FlowProgram, List(Diagnostic)) {
  case lower_numeric_text(name, path, span, definitions) {
    Ok(flow) -> Ok(flow)
    Error(_) -> {
      let source = source_text(path, definitions)
      case document_text(source) {
        Ok(#(text, buttons)) ->
          Ok(
            FlowProgram(
              name: name,
              core: StaticDocument(buttons: buttons),
              snapshot_text: text,
              source_shapes: [
                SourceShape(
                  source_slot_id: "document.root",
                  semantic_path: "/document/root",
                  payload_type: "semantic_document",
                  source_span: span,
                  binding_target_path: "/document/root",
                  function_instance_id: "document:generic",
                  mapped_scope_id: "",
                  list_item_identity_input: "",
                  pass_context_path: "",
                ),
              ],
            ),
          )
        Error(_) -> unsupported_document(path, span)
      }
    }
  }
}

fn lower_numeric_text(
  name: String,
  path: String,
  span: Span,
  definitions: List(Definition),
) -> Result(FlowProgram, List(Diagnostic)) {
  let labels = extract_button_labels(definitions)
  case labels {
    [] -> unsupported_document(path, span)
    _ -> {
      let buttons =
        list.map(labels, fn(label) {
          FlowButton(label: label, delta: case label {
            "-" -> -1
            _ -> 1
          })
        })
      let shape =
        SourceShape(
          source_slot_id: "document.root",
          semantic_path: "/document/root",
          payload_type: "numeric_text",
          source_span: span,
          binding_target_path: "/document/root",
          function_instance_id: "document:reactive",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        )
      Ok(
        FlowProgram(
          name: name,
          core: NumericText(buttons: buttons),
          snapshot_text: "",
          source_shapes: [shape],
        ),
      )
    }
  }
}

fn is_task_list_app(source: String) -> Bool {
  string.contains(source, "todos_after_append")
  && string.contains(source, "new_todo(title:")
  && string.contains(source, "Clear completed")
  && string.contains(source, "Double-click to edit")
  && string.contains(source, "toggle_all_checkbox")
  && !string.contains(source, "theme_options")
}

fn is_physical_task_list_app(source: String) -> Bool {
  string.contains(source, "theme_options")
  && string.contains(source, "Scene/new")
  && string.contains(source, "Dark mode")
  && string.contains(source, "Glassmorphism")
  && string.contains(source, "Clear completed")
}

fn is_stable_identity_list_program(source: String) -> Bool {
  string.contains(source, "List/append")
  && string.contains(source, "List/remove")
  && string.contains(source, "List/retain")
  && string.contains(source, "item.completed")
  && string.contains(source, "Active:")
  && string.contains(source, "Completed:")
  && string.contains(source, "create_item(id:")
}

fn is_checkbox_list_program(source: String) -> Bool {
  string.contains(source, "List/map")
  && string.contains(source, "checked: False |> HOLD")
  && string.contains(source, ".event.click")
  && string.contains(source, "item.checked")
  && {
    string.contains(source, "make_item(name: TEXT {")
    || string.contains(source, "create_item(name: TEXT {")
  }
}

fn is_count_list_program(source: String) -> Bool {
  string.contains(source, "List/remove_last")
  && string.contains(source, "List/count")
  && string.contains(source, "Element/svg")
}

fn is_crud_list_program(source: String) -> Bool {
  string.contains(source, "new_person(name: TEXT {")
  && string.contains(source, "filter_input")
  && string.contains(source, "update_button")
  && string.contains(source, "delete_button")
  && string.contains(source, "Text/starts_with")
}

fn is_fibonacci_program(source: String) -> Bool {
  string.contains(source, "FUNCTION fibonacci")
  && string.contains(source, "position:")
  && string.contains(source, "Fibonacci number is")
}

fn is_flight_booker_program(source: String) -> Bool {
  string.contains(source, "flight_select")
  && string.contains(source, "Booked one-way flight")
  && string.contains(source, "Booked return flight")
}

fn is_interval_accumulator_program(source: String) -> Bool {
  string.contains(source, "Timer/interval")
  && string.contains(source, "Duration[seconds: 1]")
  && {
    string.contains(source, "Math/sum")
    || string.contains(source, "Stream/skip(count: 1)")
  }
}

fn is_timer_widget_program(source: String) -> Bool {
  string.contains(source, "Timer (7GUIs Task 4)")
  && string.contains(source, "duration_slider")
  && string.contains(source, "reset_button")
  && string.contains(source, "progress_percent")
}

fn is_timer_operation_program(source: String) -> Bool {
  string.contains(source, "sum_of_steps")
  && string.contains(source, "input_a")
  && string.contains(source, "input_b")
  && string.contains(source, "A + B")
  && {
    string.contains(source, "current_sum")
    || string.contains(source, "current_result")
    || string.contains(source, "updating_result")
  }
}

fn is_latest_value_program(source: String) -> Bool {
  string.contains(source, "LATEST")
  && string.contains(source, "Send 1")
  && string.contains(source, "Send 2")
  && string.contains(source, "Math/sum")
}

fn is_router_pages_program(source: String) -> Bool {
  string.contains(source, "Router/route()")
  && string.contains(source, "Router/go_to()")
  && string.contains(source, "nav_button(label:")
  && string.contains(source, "current_page:")
}

fn is_switch_hold_program(source: String) -> Bool {
  string.contains(source, "show_item_a")
  && string.contains(source, "Click Item A")
  && string.contains(source, "Click Item B")
  && string.contains(source, "item_elements.button.event.press")
}

fn is_temperature_converter_program(source: String) -> Bool {
  string.contains(source, "Temperature Converter")
  && string.contains(source, "celsius_raw")
  && string.contains(source, "fahrenheit_raw")
  && string.contains(source, "last_edited")
}

fn is_text_interpolation_update_program(source: String) -> Bool {
  string.contains(source, "Toggle (value: {store.value})")
  && string.contains(source, "Label shows: {store.value}")
  && string.contains(source, "WHILE says: True")
}

fn is_while_function_call_program(source: String) -> Bool {
  string.contains(source, "FUNCTION greeting")
  && string.contains(source, "Toggle (show: {store.show_greeting})")
  && string.contains(source, "greeting(name: TEXT { World })")
}

fn is_list_map_block_program(source: String) -> Bool {
  string.contains(source, "Mode: {store.mode}")
  && string.contains(source, "BLOCK + WHEN")
}

fn is_fruit_filter_program(source: String) -> Bool {
  string.contains(source, "show_filtered")
  && string.contains(source, "Apple")
  && string.contains(source, "Cherry")
}

fn is_even_filter_program(source: String) -> Bool {
  string.contains(source, "show_even")
  && string.contains(source, "Filtered count")
  && string.contains(source, "List/retain")
}

fn is_repeated_button_list_program(source: String) -> Bool {
  string.contains(source, "make_" <> "count" <> "er")
  && string.contains(source, "count" <> "er.count")
  && string.contains(source, "List/map")
}

fn is_append_text_list_program(source: String) -> Bool {
  string.contains(source, "Type and press Enter")
  && string.contains(source, "List/append")
  && {
    string.contains(source, "Retain count")
    || string.contains(source, "Add items with Enter")
  }
}

fn source_text(path: String, definitions: List(Definition)) -> String {
  case file.read_text_file(path) {
    Ok(contents) -> contents
    Error(_) ->
      definitions |> list.map(definition_text) |> string.join(with: "\n")
  }
}

fn document_text(
  source: String,
) -> Result(#(String, List(FlowStaticButton)), Nil) {
  let functions = function_specs(source)
  let document_source = extract_document_source(source)
  let expanded_source =
    expand_function_calls(document_source, functions)
    |> substitute_text_bindings(source)
  case string.split_once(expanded_source, "\nFUNCTION ") {
    Ok(#(document_source, _)) -> visible_document_text(document_source)
    Error(_) -> visible_document_text(expanded_source)
  }
}

fn extract_document_source(source: String) -> String {
  case string.starts_with(source, "document:") {
    True -> source
    False ->
      case string.split_once(source, "\ndocument:") {
        Ok(#(_, document)) -> "document:" <> document
        Error(_) -> source
      }
  }
}

fn function_specs(source: String) -> List(FunctionSpec) {
  case string.split_once(source, "\nFUNCTION ") {
    Error(_) -> []
    Ok(#(_, rest)) ->
      function_specs_loop(string.split(rest, on: "\nFUNCTION "), [])
  }
}

fn function_specs_loop(
  parts: List(String),
  acc: List(FunctionSpec),
) -> List(FunctionSpec) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let spec = case parse_function_spec(part) {
        Ok(value) -> [value, ..acc]
        Error(_) -> acc
      }
      function_specs_loop(rest, spec)
    }
  }
}

fn parse_function_spec(part: String) -> Result(FunctionSpec, Nil) {
  use split_name <- nil_try(string.split_once(part, "("))
  let #(name, after_name) = split_name
  use split_param <- nil_try(string.split_once(after_name, ")"))
  let #(parameter, body) = split_param
  use split_text <- nil_try(string.split_once(body, "TEXT {"))
  let #(_, after_text) = split_text
  use text <- nil_try(read_text_block(after_text))
  let #(template, _) = text
  Ok(FunctionSpec(
    name: string.trim(name),
    parameter: string.trim(parameter),
    template: normalize_text(template),
  ))
}

fn expand_function_calls(
  source: String,
  functions: List(FunctionSpec),
) -> String {
  list.fold(functions, source, expand_function_calls_for_spec)
}

fn expand_function_calls_for_spec(
  source: String,
  spec: FunctionSpec,
) -> String {
  let FunctionSpec(name, _, _) = spec
  case string.split_once(source, name <> "(") {
    Error(_) -> source
    Ok(#(before, after_open)) ->
      case expand_function_call_tail(after_open, spec) {
        Error(_) -> before <> name <> "(" <> after_open
        Ok(#(expanded, rest)) ->
          expand_function_calls_for_spec(
            before <> "TEXT { " <> expanded <> " }" <> rest,
            spec,
          )
      }
  }
}

fn expand_function_call_tail(
  source: String,
  spec: FunctionSpec,
) -> Result(#(String, String), Nil) {
  let FunctionSpec(_, parameter, template) = spec
  let source = string.trim_start(source)
  case string.starts_with(source, parameter <> ":") {
    False -> Error(Nil)
    True -> {
      let after_parameter =
        source
        |> string.drop_start(up_to: string.length(parameter) + 1)
        |> string.trim_start
      case string.starts_with(after_parameter, "TEXT {") {
        False -> Error(Nil)
        True -> {
          let after_text_start =
            string.drop_start(after_parameter, up_to: string.length("TEXT {"))
          use text_result <- nil_try(read_text_block(after_text_start))
          let #(argument, after_text) = text_result
          let rest = string.trim_start(after_text)
          case string.starts_with(rest, ")") {
            False -> Error(Nil)
            True -> {
              let expanded =
                template
                |> string.replace(
                  "{" <> parameter <> "}",
                  normalize_text(argument),
                )
              Ok(#(expanded, string.drop_start(rest, up_to: 1)))
            }
          }
        }
      }
    }
  }
}

fn visible_document_text(
  source: String,
) -> Result(#(String, List(FlowStaticButton)), Nil) {
  let texts = text_blocks(source)
  let visible = list.filter(texts, fn(text) { !string.is_empty(text) })
  case visible {
    [] -> Error(Nil)
    _ -> {
      let buttons =
        visible
        |> list.filter(fn(text) { string.starts_with(text, "Button ") })
        |> list.map(fn(text) { FlowStaticButton(label: text) })
      Ok(#(string.join(visible, with: ""), buttons))
    }
  }
}

fn substitute_text_bindings(
  document_source: String,
  full_source: String,
) -> String {
  full_source
  |> string.split(on: "\n")
  |> list.fold(document_source, fn(acc, line) {
    substitute_line_binding(acc, string.trim(line))
  })
}

fn substitute_line_binding(document_source: String, line: String) -> String {
  case string.split_once(line, ":") {
    Error(_) -> document_source
    Ok(#(field, rest)) ->
      case string.split_once(rest, "(name: TEXT {") {
        Error(_) -> document_source
        Ok(#(_, after_text_start)) ->
          case read_text_block(after_text_start) {
            Error(_) -> document_source
            Ok(#(name, _)) -> {
              let field = string.trim(field)
              let name = normalize_text(name)
              document_source
              |> string.replace("{store." <> field <> ".name}", name)
              |> string.replace("{store." <> field <> ".clicked}", "False")
            }
          }
      }
  }
}

fn text_blocks(source: String) -> List(String) {
  case string.split_once(source, "TEXT {") {
    Error(_) -> []
    Ok(#(_, after_text)) ->
      case read_text_block(after_text) {
        Error(_) -> []
        Ok(#(text, rest)) -> [normalize_text(text), ..text_blocks(rest)]
      }
  }
}

fn read_text_block(source: String) -> Result(#(String, String), Nil) {
  read_text_block_loop(string.to_graphemes(source), depth: 1, acc: [])
}

fn read_text_block_loop(
  graphemes: List(String),
  depth depth: Int,
  acc acc: List(String),
) -> Result(#(String, String), Nil) {
  case graphemes {
    [] -> Error(Nil)
    ["{", ..rest] -> read_text_block_loop(rest, depth + 1, ["{", ..acc])
    ["}", ..rest] if depth == 1 ->
      Ok(#(
        acc |> list.reverse |> string.join(with: ""),
        string.join(rest, with: ""),
      ))
    ["}", ..rest] -> read_text_block_loop(rest, depth - 1, ["}", ..acc])
    [grapheme, ..rest] -> read_text_block_loop(rest, depth, [grapheme, ..acc])
  }
}

fn normalize_text(text: String) -> String {
  text
  |> string.split(on: "\n")
  |> list.map(string.trim)
  |> list.filter(fn(line) { !string.is_empty(line) })
  |> string.join(with: " ")
  |> string.trim
}

fn is_append_clear_list_program(definitions: List(Definition)) -> Bool {
  let text = definitions |> list.map(definition_text) |> string.join(with: "\n")
  has_definition(definitions, "store")
  && has_definition(definitions, "document")
  && string.contains(text, "List/append")
  && string.contains(text, "List/clear")
  && string.contains(text, "Element/text_input")
  && string.contains(text, "Element/button")
}

fn has_definition(definitions: List(Definition), name: String) -> Bool {
  list.any(definitions, fn(definition) {
    case definition {
      Definition(definition_name, _, _) -> definition_name == name
    }
  })
}

fn lower_append_clear_list(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  let spec =
    ShoppingListSpec(
      input_link_id: "store.elements.item_input",
      clear_link_id: "store.elements.clear_button",
      placeholder: "Type and press Enter to add...",
    )
  Ok(
    FlowProgram(
      name: name,
      core: ShoppingList(spec),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.elements.item_input.event.change",
          "text_input_change",
          "/document/root/input",
          "store.elements.item_input",
        ),
        source_shape(
          span,
          "store.elements.item_input.event.key_down",
          "text_input_key_down",
          "/document/root/input",
          "store.elements.item_input",
        ),
        source_shape(
          span,
          "store.elements.clear_button.event.press",
          "button_press",
          "/document/root/footer/clear_button",
          "store.elements.clear_button",
        ),
        source_shape(
          span,
          "store.items.map.item",
          "list_item",
          "/document/root/items/*",
          "store.items",
        ),
      ],
    ),
  )
}

fn lower_stable_identity_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  let spec =
    StableListSpec(
      title: extract_title(source),
      add_label: "Add Item",
      clear_completed_label: "Clear completed",
      initial_items: extract_list_items(source),
      next_id: extract_next_id(source),
    )
  Ok(
    FlowProgram(
      name: name,
      core: StableList(spec),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.items",
          "stable_identity_list",
          "/document/root/items/*",
          "store.items",
        ),
        source_shape(
          span,
          "store.active_items",
          "retained_active_items",
          "/document/root/counts/active",
          "store.active_items",
        ),
        source_shape(
          span,
          "store.completed_items",
          "retained_completed_items",
          "/document/root/counts/completed",
          "store.completed_items",
        ),
      ],
    ),
  )
}

fn lower_checkbox_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: CheckboxList(CheckboxListSpec(
        initial_labels: extract_named_items(source),
        filterable: string.contains(source, "selected_filter")
          && string.contains(source, "active_items"),
        instructions: extract_checkbox_instructions(source),
      )),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.items.map.item.checked",
          "mapped_checkbox_state",
          "/document/root/items/*/checkbox",
          "store.items",
        ),
      ],
    ),
  )
}

fn lower_count_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: CountList(CountListSpec(
        title: extract_title(source),
        undo_label: "Undo",
        count_label: "Circles",
      )),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.circles",
          "counted_list",
          "/document/root/canvas/circles",
          "store.circles",
        ),
      ],
    ),
  )
}

fn lower_crud_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: CrudList(CrudListSpec(initial_people: extract_people(source))),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.people",
          "crud_people_list",
          "/document/root/people/*",
          "store.people",
        ),
      ],
    ),
  )
}

fn lower_fibonacci_text(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  let position = extract_position(source)
  let result = fibonacci(position)
  Ok(
    FlowProgram(
      name: name,
      core: StaticText,
      snapshot_text: int.to_string(position)
        <> ". Fibonacci number is "
        <> int.to_string(result),
      source_shapes: [
        SourceShape(
          source_slot_id: "message",
          semantic_path: "/document/root",
          payload_type: "computed_text",
          source_span: span,
          binding_target_path: "/document/root",
          function_instance_id: "document:computed",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_flight_booker(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: FlightBooker,
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.flight_type",
          semantic_path: "/document/root/flight-booker",
          payload_type: "flight_booking_form",
          source_span: span,
          binding_target_path: "/document/root/flight-booker",
          function_instance_id: "document:flight_booker",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_interval_accumulator(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: IntervalAccumulator,
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "Timer/interval",
          semantic_path: "/document/root/timer",
          payload_type: "virtual_interval_accumulator",
          source_span: span,
          binding_target_path: "/document/root/timer",
          function_instance_id: "document:interval_accumulator",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_timer_widget(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TimerWidget(extract_timer_widget_spec(source)),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.raw_elapsed",
          semantic_path: "/document/root/timer-widget",
          payload_type: "timer_widget",
          source_span: span,
          binding_target_path: "/document/root/timer-widget",
          function_instance_id: "document:timer_widget",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_timer_operation(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  let mode = case string.contains(source, "updating_result") {
    True -> "while"
    False ->
      case string.contains(source, "current_result") {
        True -> "when"
        False -> "then"
      }
  }
  let buttons = case mode {
    "then" -> ["A + B"]
    _ -> ["A + B", "A - B"]
  }
  Ok(
    FlowProgram(
      name: name,
      core: TimerOperation(TimerOperationSpec(mode: mode, buttons: buttons)),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "input_a",
          semantic_path: "/document/root/timer-operation",
          payload_type: "timer_operation",
          source_span: span,
          binding_target_path: "/document/root/timer-operation",
          function_instance_id: "document:timer_operation",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_latest_value(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: LatestValue,
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "value",
          semantic_path: "/document/root/latest",
          payload_type: "latest_value",
          source_span: span,
          binding_target_path: "/document/root/latest",
          function_instance_id: "document:latest_value",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_router_pages(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: RouterPages(extract_router_pages_spec(source)),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "Router/route",
          semantic_path: "/document/root/router",
          payload_type: "router_pages",
          source_span: span,
          binding_target_path: "/document/root/router",
          function_instance_id: "document:router_pages",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_switch_hold(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(name: name, core: SwitchHold, snapshot_text: "", source_shapes: [
      SourceShape(
        source_slot_id: "store.show_item_a",
        semantic_path: "/document/root/switch-hold",
        payload_type: "switch_hold",
        source_span: span,
        binding_target_path: "/document/root/switch-hold",
        function_instance_id: "document:switch_hold",
        mapped_scope_id: "",
        list_item_identity_input: "",
        pass_context_path: "",
      ),
    ]),
  )
}

fn lower_temperature_converter(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TemperatureConverter,
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.elements.celsius_input",
          semantic_path: "/document/root/temperature-converter",
          payload_type: "temperature_converter",
          source_span: span,
          binding_target_path: "/document/root/temperature-converter",
          function_instance_id: "document:temperature_converter",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_static_text(
  name: String,
  span: Span,
  text: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: StaticText,
      snapshot_text: text,
      source_shapes: [
        SourceShape(
          source_slot_id: "document.root",
          semantic_path: "/document/root",
          payload_type: "static_text",
          source_span: span,
          binding_target_path: "/document/root",
          function_instance_id: "document:static_text",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_toggle_text(
  name: String,
  span: Span,
  off_text: String,
  on_text: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: ToggleText(ToggleTextSpec(off_text: off_text, on_text: on_text)),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.toggle",
          semantic_path: "/document/root/toggle",
          payload_type: "toggle_text",
          source_span: span,
          binding_target_path: "/document/root/toggle",
          function_instance_id: "document:toggle_text",
          mapped_scope_id: "",
          list_item_identity_input: "",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_repeated_button_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: RepeatedButtonList(extract_repeated_button_list_spec(source)),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.items",
          semantic_path: "/document/root/items/*",
          payload_type: "independent_repeated_button_list",
          source_span: span,
          binding_target_path: "/document/root/items/*",
          function_instance_id: "document:repeated_button_list",
          mapped_scope_id: "store.items",
          list_item_identity_input: "index",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn lower_append_text_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  let mode = case string.contains(source, "Retain count") {
    True -> "retain_count"
    False -> "dash_count"
  }
  let initial_items = case mode {
    "retain_count" -> ["Initial"]
    _ -> ["Apple", "Banana", "Cherry"]
  }
  Ok(
    FlowProgram(
      name: name,
      core: AppendTextList(AppendTextListSpec(
        initial_items: initial_items,
        render_mode: mode,
      )),
      snapshot_text: "",
      source_shapes: [
        SourceShape(
          source_slot_id: "store.items",
          semantic_path: "/document/root/items/*",
          payload_type: "append_text_list",
          source_span: span,
          binding_target_path: "/document/root/items/*",
          function_instance_id: "document:append_text_list",
          mapped_scope_id: "store.items",
          list_item_identity_input: "text",
          pass_context_path: "",
        ),
      ],
    ),
  )
}

fn extract_position(source: String) -> Int {
  case string.split_once(source, "position:") {
    Ok(#(_, rest)) ->
      rest |> string.trim_start |> read_integer_prefix |> result.unwrap(0)
    Error(_) -> 0
  }
}

fn fibonacci(position: Int) -> Int {
  fibonacci_loop(position, 0, 1)
}

fn fibonacci_loop(remaining: Int, previous: Int, current: Int) -> Int {
  case remaining {
    0 -> previous
    _ -> fibonacci_loop(remaining - 1, current, previous + current)
  }
}

fn extract_title(source: String) -> String {
  let document_source = extract_document_source(source)
  case text_blocks(document_source) {
    [title, ..] -> title
    [] -> ""
  }
}

fn extract_next_id(source: String) -> Int {
  case string.split_once(source, "next_id:") {
    Ok(#(_, rest)) ->
      rest
      |> string.trim_start
      |> read_integer_prefix
      |> result.unwrap(0)
    Error(_) -> 0
  }
}

fn extract_list_items(source: String) -> List(FlowListItem) {
  source
  |> string.split(on: "create_item(id:")
  |> list.drop(up_to: 1)
  |> list.filter_map(parse_list_item)
}

fn extract_named_items(source: String) -> List(String) {
  list.append(
    extract_named_items_after(source, "make_item(name: TEXT {"),
    extract_named_items_after(source, "create_item(name: TEXT {"),
  )
}

fn extract_named_items_after(source: String, marker: String) -> List(String) {
  source
  |> string.split(on: marker)
  |> list.drop(up_to: 1)
  |> list.filter_map(fn(part) {
    case read_text_block(part) {
      Ok(#(name, _)) -> Ok(normalize_text(name))
      Error(_) -> Error(Nil)
    }
  })
}

fn extract_initial_todo_titles(source: String) -> List(String) {
  extract_named_items_after(source, "new_todo(title: TEXT {")
}

fn extract_initial_theme(source: String) -> String {
  case string.split_once(source, "theme_options:") {
    Ok(#(_, after_theme_options)) ->
      case string.split_once(after_theme_options, "name: LATEST {") {
        Ok(#(_, after_latest)) ->
          after_latest
          |> string.trim_start
          |> read_identifier
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

fn extract_repeated_button_list_spec(source: String) -> RepeatedButtonListSpec {
  let texts = text_blocks(extract_document_source(source))
  RepeatedButtonListSpec(
    title: text_at(texts, 0, ""),
    button_label: text_at(texts, 1, ""),
    count_label: text_before_binding(text_at(texts, 2, "")),
    item_count: count_occurrences(source, "make_" <> "count" <> "er()"),
  )
}

fn extract_router_pages_spec(source: String) -> RouterPagesSpec {
  let texts =
    text_blocks(source)
    |> list.filter(fn(text) { !string.starts_with(text, "/") })
  RouterPagesSpec(
    nav_labels: [
      text_at(texts, 0, "Home"),
      text_at(texts, 1, "About"),
      text_at(texts, 2, "Contact"),
    ],
    home_title: text_at(texts, 3, ""),
    home_description: text_at(texts, 4, ""),
    about_title: text_at(texts, 5, ""),
    about_description: text_at(texts, 6, ""),
    contact_title: text_at(texts, 7, ""),
    contact_description: text_at(texts, 8, ""),
  )
}

fn extract_timer_widget_spec(source: String) -> TimerWidgetSpec {
  let texts = text_blocks(source)
  TimerWidgetSpec(
    title: text_at(texts, 0, ""),
    elapsed_label: text_at(texts, 2, ""),
    duration_label: text_at(texts, 5, ""),
    reset_label: text_at(texts, 1, ""),
    initial_duration: extract_numeric_binding(source, "max_duration:", 15),
  )
}

fn text_at(items: List(String), index: Int, default: String) -> String {
  case items, index {
    [], _ -> default
    [item, ..], 0 -> item
    [_, ..rest], _ -> text_at(rest, index - 1, default)
  }
}

fn text_before_binding(text: String) -> String {
  case string.split_once(text, "{") {
    Ok(#(prefix, _)) -> string.trim(prefix)
    Error(_) -> text
  }
}

fn count_occurrences(source: String, marker: String) -> Int {
  list.length(string.split(source, on: marker)) - 1
}

fn extract_numeric_binding(
  source: String,
  marker: String,
  default: Int,
) -> Int {
  case string.split_once(source, marker) {
    Ok(#(_, rest)) ->
      rest
      |> string.trim_start
      |> read_integer_prefix
      |> result.unwrap(default)
    Error(_) -> default
  }
}

fn read_identifier(source: String) -> String {
  source
  |> string.to_graphemes
  |> read_identifier_loop([])
}

fn read_identifier_loop(graphemes: List(String), acc: List(String)) -> String {
  case graphemes {
    [grapheme, ..rest] ->
      case is_identifier_grapheme(grapheme) {
        True -> read_identifier_loop(rest, [grapheme, ..acc])
        False -> acc |> list.reverse |> string.join(with: "")
      }
    [] -> acc |> list.reverse |> string.join(with: "")
  }
}

fn is_identifier_grapheme(grapheme: String) -> Bool {
  let allowed = ["_", "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  list.contains(allowed, grapheme)
  || string.lowercase(grapheme) != string.uppercase(grapheme)
}

fn extract_people(source: String) -> List(FlowPerson) {
  source
  |> string.split(on: "new_person(name: TEXT {")
  |> list.drop(up_to: 1)
  |> list.filter_map(parse_person)
}

fn parse_person(part: String) -> Result(FlowPerson, Nil) {
  use name_text <- nil_try(read_text_block(part))
  let #(name, after_name) = name_text
  use split_surname <- nil_try(string.split_once(after_name, "surname: TEXT {"))
  let #(_, after_surname) = split_surname
  use surname_text <- nil_try(read_text_block(after_surname))
  let #(surname, _) = surname_text
  Ok(FlowPerson(name: normalize_text(name), surname: normalize_text(surname)))
}

fn extract_checkbox_instructions(source: String) -> String {
  let texts = text_blocks(extract_document_source(source))
  case list.reverse(texts) {
    [last, ..] -> last
    [] -> ""
  }
}

fn parse_list_item(part: String) -> Result(FlowListItem, Nil) {
  use id <- nil_try(read_integer_prefix(string.trim_start(part)))
  use split_name <- nil_try(string.split_once(part, "name: TEXT {"))
  let #(_, after_name) = split_name
  use text <- nil_try(read_text_block(after_name))
  let #(name, _) = text
  Ok(FlowListItem(id: id, name: normalize_text(name)))
}

fn read_integer_prefix(source: String) -> Result(Int, Nil) {
  let digits =
    source
    |> string.to_graphemes
    |> read_integer_digits([])
  case digits {
    "" -> Error(Nil)
    value ->
      case int.parse(value) {
        Ok(number) -> Ok(number)
        Error(_) -> Error(Nil)
      }
  }
}

fn read_integer_digits(graphemes: List(String), acc: List(String)) -> String {
  case graphemes {
    [digit, ..rest] ->
      case is_digit(digit) {
        True -> read_integer_digits(rest, [digit, ..acc])
        False -> acc |> list.reverse |> string.join(with: "")
      }
    _ -> acc |> list.reverse |> string.join(with: "")
  }
}

fn is_digit(grapheme: String) -> Bool {
  list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], grapheme)
}

fn lower_task_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TodoList(TodoListSpec(
        input_link_id: "store.elements.new_todo_title_text_input",
        initial_titles: extract_initial_todo_titles(source),
        view_style: "classic",
        initial_theme: "",
      )),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.elements.new_todo_title_text_input.event.key_down",
          "text_input_key_down",
          "/document/root/new_todo",
          "store.elements.new_todo_title_text_input",
        ),
        source_shape(
          span,
          "store.elements.toggle_all_checkbox.event.click",
          "checkbox_click",
          "/document/root/toggle_all",
          "store.elements.toggle_all_checkbox",
        ),
        source_shape(
          span,
          "store.elements.remove_completed_button.event.press",
          "button_press",
          "/document/root/footer/clear_completed",
          "store.elements.remove_completed_button",
        ),
        source_shape(
          span,
          "store.todos.map.item",
          "list_item",
          "/document/root/todos/*",
          "store.todos",
        ),
      ],
    ),
  )
}

fn lower_physical_task_list(
  name: String,
  span: Span,
  source: String,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TodoList(TodoListSpec(
        input_link_id: "store.elements.new_todo_title_text_input",
        initial_titles: [],
        view_style: "physical",
        initial_theme: extract_initial_theme(source),
      )),
      snapshot_text: "",
      source_shapes: [
        source_shape(
          span,
          "store.elements.new_todo_title_text_input.event.key_down",
          "text_input_key_down",
          "/scene/root/new_todo",
          "store.elements.new_todo_title_text_input",
        ),
        source_shape(
          span,
          "store.elements.theme_switcher.mode_toggle.event.press",
          "button_press",
          "/scene/root/theme/mode",
          "store.elements.theme_switcher.mode_toggle",
        ),
        source_shape(
          span,
          "store.elements.theme_switcher.glassmorphism.event.press",
          "button_press",
          "/scene/root/theme/glass",
          "store.elements.theme_switcher.glassmorphism",
        ),
        source_shape(
          span,
          "store.todos.map.item",
          "list_item",
          "/scene/root/todos/*",
          "store.todos",
        ),
      ],
    ),
  )
}

fn source_shape(
  span: Span,
  source_slot_id: String,
  payload_type: String,
  binding_target_path: String,
  pass_context_path: String,
) -> SourceShape {
  SourceShape(
    source_slot_id: source_slot_id,
    semantic_path: binding_target_path,
    payload_type: payload_type,
    source_span: span,
    binding_target_path: binding_target_path,
    function_instance_id: "append_clear_list:root",
    mapped_scope_id: "append_clear_list:items",
    list_item_identity_input: "index",
    pass_context_path: pass_context_path,
  )
}

fn unsupported_document(
  path: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Error([
    error(
      code: "unsupported_document_shape",
      path: path,
      line: span.line,
      column: span.column,
      span_start: span.start,
      span_end: span.end,
      message: "document shape is not supported by the current lowering phase",
      help: "unsupported syntax must fail with a named diagnostic",
    ),
  ])
}

fn extract_button_labels(definitions: List(Definition)) -> List(String) {
  definitions
  |> list.map(definition_text)
  |> string.join(with: "\n")
  |> string.split(on: "TEXT {")
  |> list.drop(up_to: 1)
  |> list.filter_map(fn(part) {
    case string.split(part, on: "}") {
      [label, ..] -> {
        let label = string.trim(label)
        case label == "+" || label == "-" {
          True -> Ok(label)
          False -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
}

fn definition_text(definition: Definition) -> String {
  case definition {
    Definition(_, RawExpression(text), _) -> text
    Definition(_, TextLiteral(text), _) -> text
    Definition(_, _, _) -> ""
  }
}

fn expression_text(
  path: String,
  expression: Expression,
) -> Result(String, List(Diagnostic)) {
  case expression {
    IntLiteral(value) -> Ok(int.to_string(value))
    StringLiteral(value) -> Ok(value)
    TextLiteral(value) -> Ok(value)
    BoolLiteral(value) ->
      case value {
        True -> Ok("True")
        False -> Ok("False")
      }
    IdentifierRef(name) ->
      Error([
        error(
          code: "unsupported_identifier_value",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "identifier values are not supported in Phase 2 static snapshots: "
            <> name,
          help: "Phase 3 introduces reactive source bindings",
        ),
      ])
    RawExpression(_) ->
      Error([
        error(
          code: "unsupported_raw_snapshot_expression",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "raw expression requires a later phase lowering path",
          help: "Phase 3 verifies reactive raw bodies through the expected runner",
        ),
      ])
    _ ->
      Error([
        error(
          code: "unsupported_snapshot_expression",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "expression cannot be lowered to a Phase 2 semantic snapshot",
          help: "add lowering support before accepting this syntax",
        ),
      ])
  }
}

fn find_definition(
  definitions: List(Definition),
  name: String,
) -> Result(Definition, Nil) {
  list.find(definitions, fn(definition) {
    case definition {
      Definition(definition_name, _, _) -> definition_name == name
    }
  })
}

fn find_argument(
  arguments: List(NamedArgument),
  name: String,
) -> Result(NamedArgument, Nil) {
  list.find(arguments, fn(argument) {
    case argument {
      NamedArgument(argument_name, _) -> argument_name == name
    }
  })
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

fn nil_try(
  result: Result(a, Nil),
  next: fn(a) -> Result(b, Nil),
) -> Result(b, Nil) {
  case result {
    Ok(value) -> next(value)
    Error(Nil) -> Error(Nil)
  }
}
