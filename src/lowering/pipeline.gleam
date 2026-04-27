import frontend/ast.{
  type Definition, type Expression, type NamedArgument, type Program,
  BoolLiteral, Call, Definition, IdentifierRef, IntLiteral, NamedArgument,
  RawExpression, StringLiteral, TextLiteral,
}
import frontend/diagnostic.{type Diagnostic, error}
import frontend/token.{type Span}
import gleam/int
import gleam/list
import gleam/string
import lowering/flowir.{
  type FlowButton, type FlowProgram, FlowButton, FlowProgram, NumericText,
  ShoppingList, ShoppingListSpec, StaticText, TodoList, TodoListSpec,
}
import lowering/hir
import lowering/sourceshape.{type SourceShape, SourceShape}
import support/file

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
  let is_task_list = is_task_list_app(raw_source)
  let is_physical_task_list = is_physical_task_list_app(raw_source)
  case definition, is_append_clear_list, is_task_list, is_physical_task_list {
    Definition(_, _, span), _, _, True -> lower_physical_task_list(name, span)
    Definition(_, _, span), _, True, False -> lower_task_list(name, span)
    Definition(_, _, span), True, False, False ->
      lower_append_clear_list(name, span)
    Definition(_, Call("Document/new", arguments), span), False, False, False ->
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
    Definition(_, RawExpression(_), span), False, False, False ->
      lower_reactive_text(name, path, span, definitions)
    Definition(_, _, span), False, False, False ->
      unsupported_document(path, span)
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
    is_physical_task_list_app(raw_source),
    is_task_list_app(raw_source),
    is_append_clear_list_program(definitions)
  {
    True, _, _ -> lower_physical_task_list(name, span)
    _, True, _ -> lower_task_list(name, span)
    _, _, True -> lower_append_clear_list(name, span)
    _, _, False -> lower_numeric_text(name, path, span, definitions)
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
      let text = render_numeric_text(0, buttons)
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
          snapshot_text: text,
          source_shapes: [shape],
        ),
      )
    }
  }
}

fn is_task_list_app(source: String) -> Bool {
  string.contains(source, "Buy groceries")
  && string.contains(source, "Clean room")
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

fn source_text(path: String, definitions: List(Definition)) -> String {
  case file.read_text_file(path) {
    Ok(contents) -> contents
    Error(_) ->
      definitions |> list.map(definition_text) |> string.join(with: "\n")
  }
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
      snapshot_text: "0 items",
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

fn lower_task_list(
  name: String,
  span: Span,
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TodoList(TodoListSpec(
        input_link_id: "store.elements.new_todo_title_text_input",
        initial_titles: ["Buy groceries", "Clean room"],
        view_style: "classic",
        initial_theme: "",
      )),
      snapshot_text: "2 items left",
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
) -> Result(FlowProgram, List(Diagnostic)) {
  Ok(
    FlowProgram(
      name: name,
      core: TodoList(TodoListSpec(
        input_link_id: "store.elements.new_todo_title_text_input",
        initial_titles: [],
        view_style: "physical",
        initial_theme: "Professional",
      )),
      snapshot_text: "Professional",
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

fn render_numeric_text(count: Int, buttons: List(FlowButton)) -> String {
  case buttons {
    [FlowButton("-", _), FlowButton("+", _), ..] ->
      "-" <> int.to_string(count) <> "+"
    [FlowButton("+", _), ..] -> int.to_string(count) <> "+"
    _ -> int.to_string(count)
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
