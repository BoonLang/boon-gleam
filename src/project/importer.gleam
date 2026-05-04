import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import support/file

pub type ImportReport {
  ImportReport(source_root: String, out_root: String, examples: Int, files: Int)
}

pub fn import_upstream(
  source: String,
  out_root: String,
) -> Result(ImportReport, List(Diagnostic)) {
  let source_root = source_root(source)
  case file.is_directory(source_root) {
    False ->
      Error([
        error(
          code: "import_source_missing",
          path: source,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "source corpus root does not exist: " <> source_root,
          help: "pass either the Boon repo root or playground/frontend/src/examples",
        ),
      ])
    True -> copy_examples(source_root, out_root)
  }
}

fn copy_examples(
  source_root: String,
  out_root: String,
) -> Result(ImportReport, List(Diagnostic)) {
  use copied <- result_try(copy_example_loop(
    source_root,
    out_root,
    examples(),
    0,
  ))
  use manifest <- result_try(manifest_json(source_root, out_root))
  use _ <- result_try(write_manifest(manifest))
  Ok(ImportReport(
    source_root: source_root,
    out_root: out_root,
    examples: list.length(examples()),
    files: copied,
  ))
}

fn copy_example_loop(
  source_root: String,
  out_root: String,
  examples: List(String),
  copied: Int,
) -> Result(Int, List(Diagnostic)) {
  case examples {
    [] -> Ok(copied)
    [example, ..rest] -> {
      let source_path = source_root <> "/" <> example
      let out_path = out_root <> "/" <> example
      case file.is_directory(source_path) {
        False ->
          Error([
            error(
              code: "import_example_missing",
              path: source_path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "manifest example is missing from source corpus: "
                <> example,
              help: "use the pinned Boon corpus commit or update the manifest explicitly",
            ),
          ])
        True -> {
          use count <- result_try(copy_tree(source_path, out_path))
          copy_example_loop(source_root, out_root, rest, copied + count)
        }
      }
    }
  }
}

fn copy_tree(
  source_path: String,
  out_path: String,
) -> Result(Int, List(Diagnostic)) {
  case file.list_files_recursive(source_path) {
    Error(message) ->
      Error([
        error(
          code: "import_list_failed",
          path: source_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "source corpus directories must be readable",
        ),
      ])
    Ok(paths) -> copy_file_loop(source_path, out_path, paths, 0)
  }
}

fn copy_file_loop(
  source_root: String,
  out_root: String,
  paths: List(String),
  copied: Int,
) -> Result(Int, List(Diagnostic)) {
  case paths {
    [] -> Ok(copied)
    [path, ..rest] -> {
      let relative = relative_to(source_root, path)
      let destination = out_root <> "/" <> relative
      case file.copy_file(path, destination) {
        Ok(_) -> copy_file_loop(source_root, out_root, rest, copied + 1)
        Error(message) ->
          Error([
            error(
              code: "import_copy_failed",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: message,
              help: "import-upstream must preserve corpus files byte-for-byte",
            ),
          ])
      }
    }
  }
}

fn source_root(source: String) -> String {
  let repo_examples = source <> "/playground/frontend/src/examples"
  case file.is_directory(repo_examples) {
    True -> repo_examples
    False -> trim_trailing_slash(source)
  }
}

fn examples() -> List(String) {
  [
    "button_hover_test",
    "button_hover_to_click_test",
    "cells",
    "cells_dynamic",
    "chained_list_remove_bug",
    "checkbox_test",
    "circle_drawer",
    "complex_counter",
    "counter",
    "counter_hold",
    "crud",
    "fibonacci",
    "filter_checkbox_bug",
    "flight_booker",
    "hello_world",
    "interval",
    "interval_hold",
    "latest",
    "layers",
    "list_map_block",
    "list_map_external_dep",
    "list_object_state",
    "list_retain_count",
    "list_retain_reactive",
    "list_retain_remove",
    "minimal",
    "pages",
    "shopping_list",
    "switch_hold_test",
    "temperature_converter",
    "text_interpolation_update",
    "then",
    "timer",
    "todo_mvc",
    "todo_mvc_physical",
    "when",
    "while",
    "while_function_call",
  ]
}

fn ignored_paths() -> List(#(String, String)) {
  [
    #(
      "checkbox_test.bn",
      "top-level duplicate of checkbox_test/checkbox_test.bn",
    ),
    #(
      "hw_examples",
      "hardware/SystemVerilog examples are outside the Boon reactive app corpus",
    ),
    #(
      "reference_metadata.json",
      "top-level metadata file, not a standalone example",
    ),
  ]
}

fn manifest_json(
  source_root: String,
  out_root: String,
) -> Result(String, List(Diagnostic)) {
  use example_entries <- result_try(manifest_examples(out_root, examples(), []))
  let ignored_entries =
    ignored_paths()
    |> list.map(ignored_json)
    |> string.join(",\n")

  Ok(
    "{\n"
    <> "  \"schema_version\": 1,\n"
    <> "  \"generated_at_utc\": \"2026-04-27T00:00:00Z\",\n"
    <> "  \"sources\": [\n"
    <> "    {\n"
    <> "      \"name\": \"boon\",\n"
    <> "      \"repo\": \"https://github.com/BoonLang/boon\",\n"
    <> "      \"commit\": \"34251e2938a73f05de14997e167630bb0124ef48\",\n"
    <> "      \"source_root\": \"playground/frontend/src/examples\"\n"
    <> "    },\n"
    <> "    {\n"
    <> "      \"name\": \"boon-gleam-terminal\",\n"
    <> "      \"repo\": \"local\",\n"
    <> "      \"commit\": \"workspace\",\n"
    <> "      \"source_root\": \"examples/terminal\"\n"
    <> "    }\n"
    <> "  ],\n"
    <> "  \"source_root_observed\": "
    <> json_string(source_root)
    <> ",\n"
    <> "  \"examples\": [\n"
    <> string.join(example_entries, ",\n")
    <> terminal_examples_json()
    <> "\n"
    <> "  ],\n"
    <> "  \"ignored\": [\n"
    <> ignored_entries
    <> "\n"
    <> "  ]\n"
    <> "}\n",
  )
}

fn manifest_examples(
  out_root: String,
  examples: List(String),
  acc: List(String),
) -> Result(List(String), List(Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] -> {
      let root = out_root <> "/" <> example
      use files <- result_try(example_files(root))
      manifest_examples(out_root, rest, [example_json(example, files), ..acc])
    }
  }
}

fn example_files(root: String) -> Result(List(String), List(Diagnostic)) {
  case file.list_files_recursive(root) {
    Ok(paths) ->
      paths
      |> list.map(fn(path) { relative_to(root, path) })
      |> list.sort(string.compare)
      |> Ok
    Error(message) ->
      Error([
        error(
          code: "manifest_example_list_failed",
          path: root,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "import-upstream must write manifest metadata after copying each example",
        ),
      ])
  }
}

fn example_json(example: String, files: List(String)) -> String {
  let entry_file = case list.contains(files, example <> ".bn") {
    True -> example <> ".bn"
    False ->
      case list.contains(files, "RUN.bn") {
        True -> "RUN.bn"
        False -> example <> ".bn"
      }
  }
  let expected_file = case list.contains(files, example <> ".expected") {
    True -> example <> ".expected"
    False -> ""
  }
  let kind = case list.length(bn_files(files)) > 1 {
    True -> "multi_file"
    False -> "single_file"
  }

  "    {\n"
  <> "      \"name\": "
  <> json_string(example)
  <> ",\n"
  <> "      \"kind\": "
  <> json_string(kind)
  <> ",\n"
  <> "      \"source_repo\": \"boon\",\n"
  <> "      \"source_commit\": \"34251e2938a73f05de14997e167630bb0124ef48\",\n"
  <> "      \"source_path\": "
  <> json_string(example)
  <> ",\n"
  <> "      \"local_path\": "
  <> json_string("examples/upstream/" <> example)
  <> ",\n"
  <> "      \"entry_file\": "
  <> json_string(entry_file)
  <> ",\n"
  <> "      \"files\": "
  <> json_string_list(files)
  <> ",\n"
  <> "      \"assets\": "
  <> json_string_list(assets(files))
  <> ",\n"
  <> "      \"docs\": "
  <> json_string_list(docs(files))
  <> ",\n"
  <> "      \"scripts\": "
  <> json_string_list(scripts(files))
  <> ",\n"
  <> "      \"expected\": "
  <> json_string(expected_file)
  <> ",\n"
  <> "      \"targets\": "
  <> json_string_list(targets(example))
  <> ",\n"
  <> "      \"phase\": "
  <> json_string(phase(example))
  <> ",\n"
  <> "      \"ignored\": false,\n"
  <> "      \"ignored_reason\": \"\"\n"
  <> "    }"
}

fn terminal_examples_json() -> String {
  ",\n"
  <> "    {\n"
  <> "      \"name\": \"pong\",\n"
  <> "      \"kind\": \"terminal\",\n"
  <> "      \"source_repo\": \"boon-gleam-terminal\",\n"
  <> "      \"source_commit\": \"workspace\",\n"
  <> "      \"source_path\": \"pong\",\n"
  <> "      \"local_path\": \"examples/terminal/pong\",\n"
  <> "      \"entry_file\": \"pong.bn\",\n"
  <> "      \"files\": [\"pong.bn\", \"pong.expected\"],\n"
  <> "      \"assets\": [],\n"
  <> "      \"docs\": [],\n"
  <> "      \"scripts\": [],\n"
  <> "      \"expected\": \"pong.expected\",\n"
  <> "      \"targets\": [\"terminal\"],\n"
  <> "      \"phase\": \"terminal\",\n"
  <> "      \"ignored\": false,\n"
  <> "      \"ignored_reason\": \"\"\n"
  <> "    },\n"
  <> "    {\n"
  <> "      \"name\": \"arkanoid\",\n"
  <> "      \"kind\": \"terminal\",\n"
  <> "      \"source_repo\": \"boon-gleam-terminal\",\n"
  <> "      \"source_commit\": \"workspace\",\n"
  <> "      \"source_path\": \"arkanoid\",\n"
  <> "      \"local_path\": \"examples/terminal/arkanoid\",\n"
  <> "      \"entry_file\": \"arkanoid.bn\",\n"
  <> "      \"files\": [\"arkanoid.bn\", \"arkanoid.expected\"],\n"
  <> "      \"assets\": [],\n"
  <> "      \"docs\": [],\n"
  <> "      \"scripts\": [],\n"
  <> "      \"expected\": \"arkanoid.expected\",\n"
  <> "      \"targets\": [\"terminal\"],\n"
  <> "      \"phase\": \"terminal\",\n"
  <> "      \"ignored\": false,\n"
  <> "      \"ignored_reason\": \"\"\n"
  <> "    }"
}

fn ignored_json(entry: #(String, String)) -> String {
  "    {\n"
  <> "      \"path\": "
  <> json_string(entry.0)
  <> ",\n"
  <> "      \"source_repo\": \"boon\",\n"
  <> "      \"source_commit\": \"34251e2938a73f05de14997e167630bb0124ef48\",\n"
  <> "      \"ignored\": true,\n"
  <> "      \"ignored_reason\": "
  <> json_string(entry.1)
  <> "\n"
  <> "    }"
}

fn bn_files(files: List(String)) -> List(String) {
  files |> list.filter(fn(path) { string.ends_with(path, ".bn") })
}

fn assets(files: List(String)) -> List(String) {
  files
  |> list.filter(fn(path) {
    string.starts_with(path, "assets/")
    || string.ends_with(path, ".png")
    || string.ends_with(path, ".svg")
    || string.ends_with(path, ".json")
  })
}

fn docs(files: List(String)) -> List(String) {
  files
  |> list.filter(fn(path) {
    string.starts_with(path, "docs/") || string.ends_with(path, ".md")
  })
}

fn scripts(files: List(String)) -> List(String) {
  files |> list.filter(fn(path) { string.ends_with(path, ".sh") })
}

fn targets(example: String) -> List(String) {
  case example {
    "pong" | "arkanoid" -> ["terminal"]
    "todo_mvc_physical" -> ["semantic", "backend"]
    _ -> ["semantic", "backend", "web"]
  }
}

fn phase(example: String) -> String {
  case example {
    "minimal" | "hello_world" -> "frontend"
    "counter" | "counter_hold" | "complex_counter" -> "events"
    "pong" -> "terminal"
    "shopping_list" | "todo_mvc" -> "forms"
    "arkanoid" -> "games"
    "todo_mvc_physical" -> "build"
    _ -> "expanded"
  }
}

fn json_string_list(items: List(String)) -> String {
  "[" <> string.join(list.map(items, json_string), ", ") <> "]"
}

fn json_string(value: String) -> String {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
  "\"" <> escaped <> "\""
}

fn write_manifest(contents: String) -> Result(Nil, List(Diagnostic)) {
  case file.write_text_file("fixtures/corpus_manifest.json", contents) {
    Ok(_) -> Ok(Nil)
    Error(message) ->
      Error([
        error(
          code: "manifest_write_failed",
          path: "fixtures/corpus_manifest.json",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "import-upstream must be able to update corpus manifest metadata",
        ),
      ])
  }
}

fn relative_to(root: String, path: String) -> String {
  let prefix = trim_trailing_slash(root) <> "/"
  case string.starts_with(path, prefix) {
    True -> string.drop_start(path, up_to: string.length(prefix))
    False -> path
  }
}

fn trim_trailing_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, up_to: 1)
    False -> path
  }
}

pub fn summary(report: ImportReport) -> String {
  "imported examples="
  <> int.to_string(report.examples)
  <> " files="
  <> int.to_string(report.files)
  <> " source="
  <> report.source_root
  <> " out="
  <> report.out_root
}

fn result_try(
  result: Result(a, List(Diagnostic)),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(diagnostics) -> Error(diagnostics)
  }
}
